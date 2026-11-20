import Foundation
import NanoIPC
import Darwin

let started = ProcessInfo.processInfo.systemUptime
func diagnostic(_ text: String) { try? FileHandle.standardError.write(contentsOf: Data("ia-nano: \(text)\n".utf8)) }
let help = """
iA Nano — a small native editor for terminal workflows
Usage: ia-nano [FILE | - | --help | --version | --quit-if-idle]
FILE edits a UTF-8 file. - reads stdin through EOF. No args opens an empty buffer.
Use -- FILE for names beginning with a dash.
Cmd+W / Ctrl+W saves or submits this editor; Cmd+Escape cancels it.
Cmd+S saves; Cmd+Q finishes all editors and quits the resident app.
Exit codes: 0 completed, 1 cancelled, 2 invocation, connection, or input error.
"""
signal(SIGPIPE, SIG_IGN)
do {
    let invocation = try Invocation.parse(Array(CommandLine.arguments.dropFirst()))
    if invocation == .help { print(help); exit(0) }
    if invocation == .version { print("iA Nano 0.1.0"); exit(0) }
    var input = Data(), path: String?
    if case .file(let name) = invocation {
        path = URL(fileURLWithPath: name).standardizedFileURL.resolvingSymlinksInPath().path
    }
    if invocation == .pipe { input = try FileHandle.standardInput.readToEnd() ?? Data() }
    let endpoint = try Endpoint()
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var cold = false
    var launched = false
    var process: Process?
    var connection: Connection?
    while connection == nil {
        if let candidate = try endpoint.connect() {
            candidate.timeout(5)
            let greeting = try candidate.receive()
            guard greeting.kind == "hello" else { throw NanoError.message("Unrecognized resident host protocol. Quit the app before updating.") }
            if invocation == .quitIfIdle || greeting.version != 1 || greeting.message != endpoint.build {
                try candidate.send(Packet("quitIfIdle"))
                let result = try candidate.receive()
                guard result.kind == "stopped" else { throw NanoError.message(result.message ?? "The resident app has open editors or settings; close them before updating.") }
                if invocation == .quitIfIdle { exit(0) }
                candidate.shutdown()
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            connection = candidate
        } else {
            if invocation == .quitIfIdle {
                // A locked endpoint can be a host still starting; do not report it stopped.
                if let lock = try endpoint.acquireLock() { Darwin.close(lock); exit(0) }
            } else if !launched {
                let child = Process()
                child.executableURL = endpoint.gui
                child.arguments = ["--background"]
                child.standardInput = FileHandle.nullDevice
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
                try child.run(); process = child; launched = true; cold = true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if ProcessInfo.processInfo.systemUptime >= deadline {
            throw NanoError.message("Host did not become ready within five seconds\(process.map { $0.isRunning ? "" : " (exit \($0.terminationStatus))" } ?? "").")
        }
    }
    let channel = connection!
    channel.timeout(0)
    let id = UUID().uuidString
    try channel.send(Packet("open", id: id, path: path))
    try channel.sendData(input, id: id)
    try channel.send(Packet("end", id: id))
    var outputError: Error?
    while true {
        let packet = try channel.receive()
        guard packet.version == 1, packet.id == id else { throw NanoError.message("Mismatched response from resident host.") }
        switch packet.kind {
        case "ready":
            if ProcessInfo.processInfo.environment["IA_NANO_METRICS"] == "1" {
                diagnostic(String(format: "%@ window-ready in %.1f ms (client entry; not screen presentation)", cold ? "cold" : "warm", (ProcessInfo.processInfo.systemUptime - started) * 1000))
            }
        case "chunk":
            if outputError == nil {
                do { try FileHandle.standardOutput.write(contentsOf: packet.data ?? Data()) }
                catch { outputError = error }
            }
        case "outputEnd":
            try channel.send(Packet("ack", id: id, code: outputError == nil ? 0 : 2))
            if let outputError { throw NanoError.message("Stdout delivery failed: \(outputError.localizedDescription). Text remains in the editor.") }
        case "done":
            if let message = packet.message { diagnostic(message) }
            exit(packet.code ?? 2)
        default: throw NanoError.message("Unexpected IPC response: \(packet.kind)")
        }
    }
} catch {
    diagnostic(error.localizedDescription)
    exit(2)
}
