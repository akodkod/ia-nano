import AppKit

// Accent is an app preference, independent of syntax-highlighting colors.
enum AccentColor: String, CaseIterable {
    case blue, purple, pink, red, orange, green

    var name: String { rawValue.capitalized }
    var color: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .green: return .systemGreen
        }
    }
}

final class AppSettings: NSObject {
    static let shared = AppSettings()
    static let didChange = Notification.Name("app.ianano.settings.changed")
    private static let distributedChange = Notification.Name("app.ianano.settings.persisted")
    private let defaults = UserDefaults.standard
    private(set) var accent: AccentColor

    private override init() {
        accent = AccentColor(rawValue: UserDefaults.standard.string(forKey: "accentColor") ?? "") ?? .purple
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reload),
            name: Self.distributedChange, object: nil, suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func select(_ accent: AccentColor) {
        guard self.accent != accent else { return }
        self.accent = accent
        defaults.set(accent.rawValue, forKey: "accentColor")
        // Each CLI invocation is a separate process; flush before notifying peers.
        defaults.synchronize()
        NotificationCenter.default.post(name: Self.didChange, object: self)
        DistributedNotificationCenter.default().postNotificationName(Self.distributedChange,
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    @objc private func reload() {
        defaults.synchronize()
        let saved = AccentColor(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .purple
        guard saved != accent else { return }
        accent = saved
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

private final class AccentCardCell: NSButtonCell {
    override func hitTest(for event: NSEvent, in cellFrame: NSRect, of controlView: NSView) -> NSCell.HitResult {
        let point = controlView.convert(event.locationInWindow, from: nil)
        guard isEnabled, cellFrame.contains(point) else { return [] }
        // Native radio cells only hit their indicator and title, not our painted card.
        return [.contentArea, .trackableArea]
    }
}

final class AccentCard: NSButton {
    let accent: AccentColor
    var moveSelection: ((Int) -> Void)?
    var keyboardFocusVisible = false { didSet { needsDisplay = true } }

    init(accent: AccentColor) {
        self.accent = accent
        super.init(frame: .zero)
        cell = AccentCardCell(textCell: accent.name)
        title = accent.name
        setButtonType(.radio)
        isBordered = false
        focusRingType = .none
        setAccessibilityLabel("\(accent.name) accent color")
        toolTip = accent.name
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 86),
            heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func keyDown(with event: NSEvent) {
        keyboardFocusVisible = true
        switch event.keyCode {
        case 123, 126: moveSelection?(-1)
        case 124, 125: moveSelection?(1)
        case 36, 49: performClick(nil)
        default: super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        keyboardFocusVisible = true
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let card = bounds.insetBy(dx: 3, dy: 4)
        let path = NSBezierPath(roundedRect: card, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.09)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.textBackgroundColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        if isHighlighted {
            accent.color.withAlphaComponent(0.08).setFill()
            path.fill()
        }
        (selected ? accent.color : NSColor.separatorColor).setStroke()
        path.lineWidth = selected ? 1.5 : 0.75
        path.stroke()

        let text = "Aa" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 23, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width - 7) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attributes)
        accent.color.setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x + size.width + 3, y: origin.y + 1, width: 3, height: 27),
                     xRadius: 1.5, yRadius: 1.5).fill()
        if keyboardFocusVisible, window?.firstResponder === self {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.charactersIgnoringModifiers?.lowercased() == "w" && (modifiers == .command || modifiers == .control))
            || (event.keyCode == 53 && modifiers.isEmpty) {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsController: NSWindowController, NSWindowDelegate {
    private let settings: AppSettings
    private var cards: [AccentCard] = []
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    var onClose: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 168),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Settings"
        window.backgroundColor = NSColor(name: "SettingsBackground") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 1)
                : NSColor(calibratedWhite: 0.98, alpha: 1)
        }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.delegate = self
        let content = NSView()
        window.contentView = content
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        for (index, accent) in AccentColor.allCases.enumerated() {
            let card = AccentCard(accent: accent)
            card.target = self
            card.action = #selector(selectAccent(_:))
            card.moveSelection = { [weak self] delta in self?.moveSelection(from: index, by: delta) }
            cards.append(card)
            row.addArrangedSubview(card)
        }
        closeButton.target = self
        closeButton.action = #selector(closeSettings)
        closeButton.bezelStyle = .flexiblePush
        closeButton.controlSize = .large
        closeButton.font = .systemFont(ofSize: 15, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(closeButton)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            closeButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            closeButton.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 148),
            closeButton.heightAnchor.constraint(equalToConstant: 34)
        ])
        updateSelection()
        NotificationCenter.default.addObserver(self, selector: #selector(updateSelection), name: AppSettings.didChange, object: settings)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { NotificationCenter.default.removeObserver(self) }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if let selected = cards.first(where: { $0.accent == settings.accent }) {
            window?.makeFirstResponder(selected)
            selected.keyboardFocusVisible = false
        }
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    @objc private func closeSettings() { window?.performClose(nil) }

    @objc private func selectAccent(_ sender: AccentCard) { settings.select(sender.accent) }

    private func moveSelection(from index: Int, by delta: Int) {
        let next = (index + delta + cards.count) % cards.count
        settings.select(cards[next].accent)
        window?.makeFirstResponder(cards[next])
    }

    @objc private func updateSelection() {
        closeButton.bezelColor = settings.accent.color
        for card in cards {
            card.state = card.accent == settings.accent ? .on : .off
            card.needsDisplay = true
        }
    }
}
