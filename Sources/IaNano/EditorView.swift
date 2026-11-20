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
    private var isPasting = false

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
            if text == "`", !isPasting, !hasMarkedText() {
                insertBacktick(replacementRange: replacementRange)
                return
            }
            super.insertText(TextDocument.normalize(text), replacementRange: replacementRange)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func paste(_ sender: Any?) {
        isPasting = true
        defer { isPasting = false }
        super.paste(sender)
    }

    private func insertBacktick(replacementRange: NSRange) {
        let source = string as NSString
        let selection = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if selection.length > 0 {
            super.insertText("`" + source.substring(with: selection) + "`", replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + 1, length: selection.length))
            return
        }
        let prefix = source.substring(to: selection.location)
        let backslashes = prefix.reversed().prefix { $0 == "\\" }.count
        if backslashes % 2 == 1 {
            super.insertText("`", replacementRange: selection)
            return
        }
        let line = source.lineRange(for: selection)
        let beforeCaret = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let indentation = String(beforeCaret.prefix { $0 == " " })
        if indentation.count <= 3, beforeCaret == indentation + "``",
           Fence.scan(source.substring(to: line.location)).last?.markers.count != 1 {
            super.insertText("`\n" + indentation + "```", replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        } else if selection.location < source.length, source.character(at: selection.location) == 96 {
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        } else if indentation.count <= 3,
                  beforeCaret.dropFirst(indentation.count).allSatisfy({ $0 == "`" }),
                  Fence.scan(source.substring(to: line.location)).last?.markers.count == 1 {
            super.insertText("`", replacementRange: selection)
        } else {
            super.insertText("``", replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        }
    }

    override func insertTab(_ sender: Any?) {
        if selectedRange().length == 0 {
            insertText("  ", replacementRange: selectedRange())
        } else {
            indentSelectedLines(outdent: false)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        indentSelectedLines(outdent: true)
    }

    override func insertNewline(_ sender: Any?) {
        let source = string as NSString
        let selection = selectedRange()
        let prefix = source.substring(to: selection.location)
        var indentation = ""
        if Fence.scan(prefix).last?.markers.count == 1 {
            let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let beforeCaret = source.substring(with: NSRange(location: line.location,
                                                            length: selection.location - line.location))
            indentation = String(beforeCaret.prefix { $0 == " " || $0 == "\t" })
                .replacingOccurrences(of: "\t", with: "  ")
        }
        insertText("\n" + indentation, replacementRange: selection)
    }

    private func indentSelectedLines(outdent: Bool) {
        let source = string as NSString
        let selection = selectedRange()
        // A selection ending at the next line's start does not include that line.
        let covered = NSRange(location: selection.location, length: max(0, selection.length - 1))
        let lines = source.lineRange(for: covered)
        var replacement = ""
        var start = selection.location
        var end = NSMaxRange(selection)
        var offset = lines.location
        repeat {
            let lineRange = source.lineRange(for: NSRange(location: offset, length: 0))
            let line = source.substring(with: lineRange)
            let removed = outdent ? (line.hasPrefix("\t") ? 1 : line.prefix(2).prefix { $0 == " " }.count) : 0
            let added = outdent ? 0 : 2
            replacement += (outdent ? "" : "  ") + String(line.dropFirst(removed))
            func adjusted(_ position: Int) -> Int {
                position < offset ? position : position - min(removed, position - offset) + added
            }
            // Map original selection endpoints through each leading-whitespace edit.
            start += adjusted(selection.location) - selection.location
            end += adjusted(NSMaxRange(selection)) - NSMaxRange(selection)
            offset = NSMaxRange(lineRange)
        } while offset < NSMaxRange(lines)
        guard replacement != source.substring(with: lines) else { return }
        super.insertText(replacement, replacementRange: lines)
        setSelectedRange(NSRange(location: start, length: end - start))
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
    private let returnsOutput: Bool
    private let onExit: (Int32) -> Void
    private let highlighter: SyntaxHighlighter
    private let highlightingQueue = DispatchQueue(label: "app.ianano.highlight", qos: .userInitiated)
    private var pendingHighlight: DispatchWorkItem?
    private var revision = 0
    private var highlights: [Highlight] = []
    private var finishing = false
    private var disconnected = false
    var deliverOutput: ((Data) -> Void)?
    var onFailure: (() -> Void)?
    private let notice = NSTextField(wrappingLabelWithString: "")

    init(buffer: TextDocument, highlighter: SyntaxHighlighter, onExit: @escaping (Int32) -> Void) {
        self.buffer = buffer
        returnsOutput = buffer.url == nil
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
        notice.translatesAutoresizingMaskIntoConstraints = false
        notice.textColor = .systemOrange
        notice.font = .systemFont(ofSize: 12)
        notice.isHidden = true
        content.addSubview(notice)
        let drag = DragRegion()
        drag.translatesAutoresizingMaskIntoConstraints = false
        drag.setAccessibilityLabel("Drag to move iA Nano")
        content.addSubview(drag)
        NSLayoutConstraint.activate([
            notice.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            notice.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            notice.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
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
        editor.cancel = { [weak self] in self?.cancelSession() }
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
        if buffer.url == nil { saveAs(); return }
        do { try buffer.save(editor.string) }
        catch { onFailure?(); show(error) }
    }

    @objc func saveAs() {
        let panel = NSSavePanel()
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.saveAs(to: url)
            } catch { self.onFailure?(); self.show(error) }
        }
    }

    func saveAs(to url: URL) throws {
        let data = buffer.encoded(editor.string)
        try data.write(to: url, options: .atomic)
        buffer = try TextDocument(data: data, url: url)
        window?.title = url.lastPathComponent
    }

    func markDisconnected() {
        disconnected = true
        finishing = false
        editor.isEditable = true
        notice.stringValue = "Terminal disconnected. Output cannot reach the caller. Save with Cmd+S or copy your text."
        notice.isHidden = false
        editor.textContainerInset.height = 58
        onFailure?()
    }

    func deliveryFailed() { markDisconnected() }

    func completeSession(_ code: Int32) {
        pendingHighlight?.cancel()
        pendingHighlight = nil
        revision += 1
        editor.undoManager?.removeAllActions()
        window?.close()
        window?.delegate = nil
        window = nil
        editor.delegate = nil
        onExit(code)
    }

    private func cancelSession() {
        guard !finishing else { return }
        if disconnected { confirmDiscard(); return }
        completeSession(1)
    }

    private func confirmDiscard() {
        guard let window else { return }
        onFailure?()
        let alert = NSAlert()
        alert.messageText = disconnected ? "Discard this disconnected buffer?" : "Save this buffer before closing?"
        alert.informativeText = "Save it with Cmd+S or copy it before discarding."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.completeSession(1) }
        }
    }

    @objc func finish() {
        guard !finishing else { return }
        do {
            if buffer.url != nil { try buffer.save(editor.string) }
            if returnsOutput && !disconnected, let deliverOutput {
                finishing = true
                editor.isEditable = false
                deliverOutput(buffer.encoded(editor.string))
            } else if buffer.url != nil {
                completeSession(0)
            } else {
                confirmDiscard()
            }
        } catch { onFailure?(); show(error) }
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
