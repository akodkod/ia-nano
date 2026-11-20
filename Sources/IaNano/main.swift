import AppKit
import NanoCore
import Darwin

let launchStarted = ProcessInfo.processInfo.systemUptime

let help = """
iA Nano — a small native editor for terminal workflows

Usage: ia-nano [FILE | - | --help | --version]

  FILE       Edit a UTF-8 file; wait until it is saved and closed.
  -          Read stdin, edit, then write the result to stdout.
  No args    Open an empty buffer and write the result to stdout.
  -- FILE    Edit a filename that starts with a dash.

Ctrl+W / Cmd+W  Save or submit and close
Cmd+S          Save a file without closing
Cmd+Escape     Cancel (earlier Cmd+S saves remain on disk)

Exit codes: 0 completed, 1 cancelled, 2 invocation or input error.
"""

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var controller: EditorController?
    private var settingsController: SettingsController?
    let document: TextDocument
    let highlighter: SyntaxHighlighter

    init(document: TextDocument, highlighter: SyntaxHighlighter) {
        self.document = document
        self.highlighter = highlighter
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        controller = EditorController(buffer: document, highlighter: highlighter) { code in
            Darwin.exit(code)
        }
        controller?.present()
        NotificationCenter.default.addObserver(self, selector: #selector(updateAccent),
            name: AppSettings.didChange, object: AppSettings.shared)
        if ProcessInfo.processInfo.environment["IA_NANO_METRICS"] == "1" {
            let milliseconds = (ProcessInfo.processInfo.systemUptime - launchStarted) * 1000
            let message = String(format: "ia-nano: window presented in %.1f ms (after process entry)\n", milliseconds)
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.finish()
        return .terminateCancel
    }

    @objc private func updateAccent() {
        controller?.editor.insertionPointColor = AppSettings.shared.accent.color
        controller?.editor.needsDisplay = true
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsController(settings: AppSettings.shared)
            settingsController?.onClose = { [weak self] in self?.controller?.present() }
        }
        settingsController?.present()
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
    let invocation = try Invocation.parse(Array(CommandLine.arguments.dropFirst()))
    let document: TextDocument
    switch invocation {
    case .help: print(help); exit(0)
    case .version: print("iA Nano 0.1.0"); exit(0)
    case .file(let path): document = try TextDocument.open(path: path)
    case .pipe: document = try TextDocument(data: FileHandle.standardInput.readToEnd() ?? Data())
    case .empty: document = try TextDocument(data: Data())
    }
    let highlighter = try SyntaxHighlighter()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = ApplicationDelegate(document: document, highlighter: highlighter)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("ia-nano: \(error.localizedDescription)\n".utf8))
    exit(2)
}
