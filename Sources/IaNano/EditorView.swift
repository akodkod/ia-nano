import AppKit
import NanoCore

private enum EditorColors {
    static let background = NSColor(name: "EditorBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.12, alpha: 1)
            : .white
    }
    static let text = NSColor(name: "EditorText") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .textColor
            : NSColor(calibratedWhite: 0.18, alpha: 1)
    }
}

private final class EditorBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        EditorColors.background.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class EditorView: NSTextView {
    var complete: (() -> Void)?
    var cancel: (() -> Void)?
    var save: (() -> Void)?
    var appearanceChanged: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers?.lowercased() == "w", modifiers == .control || modifiers == .command {
            complete?()
            return true
        }
        if event.keyCode == 53, modifiers == .command {
            cancel?()
            return true
        }
        if event.charactersIgnoringModifiers?.lowercased() == "s", modifiers == .command {
            save?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String)
        if let text {
            super.insertText(TextDocument.normalize(text), replacementRange: replacementRange)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caret = rect
        caret.size.width = 3
        if flag {
            insertionPointColor.setFill()
            NSBezierPath(roundedRect: caret, xRadius: 1.5, yRadius: 1.5).fill()
        } else {
            super.drawInsertionPoint(in: caret, color: insertionPointColor, turnedOn: false)
        }
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -4, dy: 0), avoidAdditionalLayout: flag)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}

final class DragRegion: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class EditorController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let editor: EditorView
    private var buffer: TextDocument
    private let onExit: (Int32) -> Void
    private let highlighter: SyntaxHighlighter
    private let highlightingQueue = DispatchQueue(label: "app.ianano.highlight", qos: .userInitiated)
    private var pendingHighlight: DispatchWorkItem?
    private var revision = 0
    private var highlights: [Highlight] = []
    private var finishing = false

    init(buffer: TextDocument, highlighter: SyntaxHighlighter, onExit: @escaping (Int32) -> Void) {
        self.buffer = buffer
        self.highlighter = highlighter
        self.onExit = onExit
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        editor = EditorView(frame: NSRect(x: 0, y: 0, width: 720, height: 520), textContainer: container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = buffer.url?.lastPathComponent ?? "iA Nano"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 360, height: 240)
        window.backgroundColor = EditorColors.background
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.delegate = self
        let content = EditorBackgroundView()
        window.contentView = content
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        content.addSubview(scroll)
        let drag = DragRegion()
        drag.translatesAutoresizingMaskIntoConstraints = false
        drag.setAccessibilityLabel("Drag to move iA Nano")
        content.addSubview(drag)
        NSLayoutConstraint.activate([
            drag.topAnchor.constraint(equalTo: content.topAnchor),
            drag.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            drag.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: drag.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 42, height: 22)
        editor.font = .monospacedSystemFont(ofSize: 19, weight: .regular)
        editor.textColor = EditorColors.text
        editor.backgroundColor = EditorColors.background
        editor.insertionPointColor = AppSettings.shared.accent.color
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.tabStops = []
        paragraph.defaultTabInterval = 46
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .foregroundColor: EditorColors.text, .paragraphStyle: paragraph]
        editor.string = buffer.text
        editor.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (buffer.text as NSString).length))
        editor.setAccessibilityLabel("Plain text editor")
        scroll.documentView = editor
        editor.delegate = self
        editor.complete = { [weak self] in self?.finish() }
        editor.cancel = { [weak self] in self?.onExit(1) }
        editor.save = { [weak self] in self?.save() }
        editor.appearanceChanged = { [weak self] in self?.applyHighlights() }
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setContentSize(NSSize(width: min(780, visible.width - 48), height: min(600, visible.height - 48)))
        }
        window.center()
        scheduleHighlight()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
    }

    func textDidChange(_ notification: Notification) { scheduleHighlight() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(); return false }

    @objc func save() {
        guard buffer.url != nil else { return }
        do { try buffer.save(editor.string) }
        catch { show(error) }
    }

    @objc func finish() {
        guard !finishing else { return }
        do {
            if buffer.url != nil { try buffer.save(editor.string) }
            else { try FileHandle.standardOutput.write(contentsOf: buffer.encoded(editor.string)) }
            finishing = true
            onExit(0)
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Couldn’t finish editing"
        alert.informativeText = error.localizedDescription
        if let window { alert.beginSheetModal(for: window) }
    }

    private func scheduleHighlight() {
        revision += 1
        let version = revision
        let text = editor.string
        pendingHighlight?.cancel()
        let highlighter = highlighter
        let item = DispatchWorkItem { [weak self] in
            let spans = highlighter.highlights(in: text)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == version else { return }
                self.highlights = spans
                self.applyHighlights()
            }
        }
        pendingHighlight = item
        highlightingQueue.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func updateAccent() {
        editor.insertionPointColor = AppSettings.shared.accent.color
        applyHighlights()
        editor.needsDisplay = true
    }

    private func applyHighlights() {
        guard let layout = editor.layoutManager else { return }
        let length = (editor.string as NSString).length
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for span in highlights where NSMaxRange(span.range) <= length {
            let color: NSColor
            switch span.kind {
            case .comment, .fence: color = .secondaryLabelColor
            case .string: color = .systemGreen
            case .number: color = .systemOrange
            case .keyword: color = .systemPurple
            case .type: color = .systemTeal
            case .function: color = .systemBlue
            case .inlineCode: color = AppSettings.shared.accent.color
            }
            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: span.range)
        }
    }
}
