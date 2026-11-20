import AppKit
import NanoCore
import NanoIPC
import Darwin

final class ResidentServer {
    let endpoint: Endpoint
    let lock: Int32
    let socket: Int32
    let build: String
    weak var delegate: ApplicationDelegate?
    init(endpoint: Endpoint, lock: Int32) throws {
        self.endpoint = endpoint; self.lock = lock; self.build = endpoint.build
        socket = try endpoint.listen()
    }
    deinit { Darwin.close(socket); Darwin.close(lock) }
    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            while true {
                let fd = accept(socket, nil, nil)
                if fd < 0 { if errno == EINTR { continue }; return }
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    guard let connection = try? Connection(fd) else { return }
                    serve(connection)
                }
            }
        }
    }
    private func serve(_ connection: Connection) {
        var requestID: String?
        do {
            connection.timeout(5)
            try connection.send(Packet("hello", message: build))
            let request = try connection.receive()
            if request.kind == "quitIfIdle" {
                DispatchQueue.main.async { [weak self] in self?.delegate?.quitIfIdle(connection) }
                return
            }
            guard request.version == 1 else { throw NanoError.message("Incompatible IPC version.") }
            if request.kind == "activate" {
                DispatchQueue.main.async { [weak self] in self?.delegate?.reopen() }
                return
            }
            guard request.kind == "open", !request.id.isEmpty,
                  request.path == nil || request.path!.hasPrefix("/") else {
                throw NanoError.message("Invalid open request.")
            }
            requestID = request.id
            var data = Data()
            while true {
                let packet = try connection.receive()
                guard packet.version == 1, packet.id == request.id else { throw NanoError.message("Mismatched input frame.") }
                if packet.kind == "end" { break }
                guard packet.kind == "chunk", let chunk = packet.data else { throw NanoError.message("Invalid input chunk.") }
                data.append(chunk)
            }
            connection.timeout(0)
            let input = data
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.open(id: request.id, path: request.path, data: input, connection: connection)
            }
            while true {
                let packet = try connection.receive()
                guard packet.id == request.id, packet.version == 1 else { throw NanoError.message("Mismatched session response.") }
                switch packet.kind {
                case "ack":
                    DispatchQueue.main.async { [weak self] in self?.delegate?.acknowledge(request.id, success: packet.code == 0) }
                case "cancel":
                    DispatchQueue.main.async { [weak self] in self?.delegate?.cancel(request.id) }
                default: throw NanoError.message("Unexpected session response.")
                }
            }
        } catch {
            if let requestID {
                DispatchQueue.main.async { [weak self] in self?.delegate?.disconnected(requestID) }
            }
            connection.shutdown()
        }
    }
}

final class EditingSession {
    let editor: EditorController
    var connection: Connection?
    var awaitingDelivery = false
    init(editor: EditorController, connection: Connection?) {
        self.editor = editor; self.connection = connection
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let server: ResidentServer
    private(set) var sessions: [String: EditingSession] = [:]
    private var settingsController: SettingsController?
    private var settingsVisible = false
    private var quitting = false
    private var finishingAll = false
    private let background: Bool
    private let terminate: () -> Void
    init(server: ResidentServer, background: Bool, terminate: @escaping () -> Void = { Darwin.exit(0) }) {
        self.server = server; self.background = background; self.terminate = terminate
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(updateAccent),
            name: AppSettings.didChange, object: AppSettings.shared)
        server.delegate = self
        server.start()
        if !background { reopen() }
    }

    func open(id: String, path: String?, data: Data, connection: Connection?) {
        do {
            guard sessions[id] == nil, !quitting else { throw NanoError.message("App is quitting; request was not opened.") }
            let document = try path.map { try TextDocument.open(path: $0) } ?? TextDocument(data: data)
            let editor = EditorController(buffer: document, highlighter: try SyntaxHighlighter()) { [weak self] code in
                self?.completed(id, code: code)
            }
            let session = EditingSession(editor: editor, connection: connection)
            sessions[id] = session
            if connection != nil {
                editor.deliverOutput = { [weak self] output in self?.deliver(id, data: output) }
            }
            editor.onFailure = { [weak self] in self?.quitting = false }
            NSApp.setActivationPolicy(.regular)
            editor.present()
            if let connection {
                do { try connection.send(Packet("ready", id: id)) }
                catch { connection.shutdown() }
            }
        } catch {
            if let connection {
                try? connection.send(Packet("done", id: id, code: 2, message: error.localizedDescription))
                connection.shutdown()
            } else { NSAlert(error: error).runModal() }
        }
    }

    private func deliver(_ id: String, data: Data) {
        guard let session = sessions[id], let connection = session.connection else {
            sessions[id]?.editor.markDisconnected(); return
        }
        session.awaitingDelivery = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try connection.sendData(data, id: id)
                try connection.send(Packet("outputEnd", id: id))
            } catch { connection.shutdown() }
        }
    }

    func acknowledge(_ id: String, success: Bool) {
        guard let session = sessions[id], session.awaitingDelivery else { return }
        session.awaitingDelivery = false
        if success { session.editor.completeSession(0) }
        else { disconnected(id) }
    }

    func cancel(_ id: String) {
        guard let session = sessions[id], !session.awaitingDelivery else { return }
        session.editor.completeSession(1)
    }

    func disconnected(_ id: String) {
        guard let session = sessions[id] else { return }
        session.connection?.shutdown()
        session.connection = nil
        session.awaitingDelivery = false
        session.editor.markDisconnected()
    }

    private func completed(_ id: String, code: Int32) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        if let connection = session.connection {
            // Completion is tiny; finish it before a pending application quit.
            try? connection.send(Packet("done", id: id, code: code))
            connection.shutdown()
        }
        updateVisibility()
        if quitting && sessions.isEmpty && !finishingAll { terminateHost() }
    }

    private func updateVisibility() {
        NSApp.setActivationPolicy(sessions.isEmpty && !settingsVisible ? .accessory : .regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true
        finishingAll = true
        for session in Array(sessions.values) { session.editor.finish() }
        finishingAll = false
        if quitting && sessions.isEmpty { terminateHost() }
        return .terminateCancel
    }

    func quitIfIdle(_ connection: Connection) {
        guard sessions.isEmpty, !settingsVisible else {
            try? connection.send(Packet("busy", message: "Editors or settings are still open. Close them before updating or quitting the idle host."))
            connection.shutdown(); return
        }
        unlink(server.endpoint.socketPath)
        try? connection.send(Packet("stopped"))
        connection.shutdown()
        terminate()
    }

    private func terminateHost() {
        unlink(server.endpoint.socketPath)
        terminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen(); return false
    }
    func reopen() {
        if let editor = sessions.values.first(where: { $0.editor.window?.isKeyWindow == true })?.editor ?? sessions.values.first?.editor {
            editor.present()
        } else { open(id: UUID().uuidString, path: nil, data: Data(), connection: nil) }
    }
    @objc private func updateAccent() { for session in sessions.values { session.editor.updateAccent() } }
    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsController(settings: AppSettings.shared)
            settingsController?.onClose = { [weak self] in
                self?.settingsVisible = false
                self?.updateVisibility()
            }
        }
        settingsVisible = true
        updateVisibility()
        settingsController?.present()
    }
    @objc private func saveAs() {
        sessions.values.first(where: { $0.editor.window?.isKeyWindow == true })?.editor.saveAs()
    }
    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu(title: "iA Nano")
        appItem.submenu = appMenu
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit iA Nano", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        let file = NSMenu(title: "File")
        fileItem.submenu = file
        let saveAsItem = file.addItem(withTitle: "Save As…", action: #selector(saveAs), keyEquivalent: "S")
        saveAsItem.target = self
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        NSApp.mainMenu = menu
    }
}

signal(SIGPIPE, SIG_IGN)
do {
    let endpoint = try Endpoint()
    guard let lock = try endpoint.acquireLock() else {
        if !CommandLine.arguments.contains("--background"), let existing = try endpoint.connect() {
            existing.timeout(5)
            _ = try existing.receive()
            try existing.send(Packet("activate"))
        }
        exit(0)
    }
    let server = try ResidentServer(endpoint: endpoint, lock: lock)
    let app = NSApplication.shared
    if let iconURL = Bundle.main.url(forResource: "Nano", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
        app.applicationIconImage = icon
    }
    app.setActivationPolicy(.accessory)
    let delegate = ApplicationDelegate(server: server, background: CommandLine.arguments.contains("--background"))
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("ia-nano: \(error.localizedDescription)\n".utf8))
    exit(2)
}
