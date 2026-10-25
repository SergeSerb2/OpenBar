import AppKit
import OpenBarCore

final class ClaudeSwapAccountSwitcherView: NSView {
    private let accounts: [ProviderAccountUsageSnapshot]
    private let onSelect: (ProviderAccountIdentity) -> Void
    private var buttons: [NSButton] = []
    private var pressedAccountID: ProviderAccountIdentity?
    private var selectionPending: Bool
    private let preferredSize: NSSize
    /// The button stack doubles as the rail: `cardFill`, radius 9, 2-pt padding around the segments.
    private let rail = NSStackView()
    private static let railInset = OpenBarTheme.Switcher.railInset
    private static let railPadding = OpenBarTheme.Switcher.railPadding

    init(
        display: ClaudeSwapAccountMenuDisplay,
        hidePersonalInfo: Bool,
        width: CGFloat,
        onSelect: @escaping (ProviderAccountIdentity) -> Void)
    {
        self.accounts = display.accounts
        self.onSelect = onSelect
        self.selectionPending = display.switchingAccountID != nil
        let rows = display.accounts.count > 3 ? 2 : 1
        self.preferredSize = NSSize(
            width: width,
            height: CGFloat(rows * 26 + (rows - 1) * 4) + Self.railPadding * 2)
        super.init(frame: NSRect(origin: .zero, size: self.preferredSize))

        let stack = self.rail
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(
            top: Self.railPadding,
            left: Self.railPadding,
            bottom: Self.railPadding,
            right: Self.railPadding)
        stack.wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        let columns = max(1, (self.accounts.count + rows - 1) / rows)
        for start in stride(from: 0, to: self.accounts.count, by: columns) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 4
            for index in start..<min(start + columns, self.accounts.count) {
                let account = self.accounts[index]
                let label = ClaudeSwapAccountMenuDisplay.label(for: account, hidePersonalInfo: hidePersonalInfo)
                let button = PaddedToggleButton(title: label, target: self, action: #selector(self.handleSelect))
                button.tag = index
                let help = ClaudeSwapAccountMenuDisplay.chipHelp(for: account, hidePersonalInfo: hidePersonalInfo)
                button.toolTip = help
                button.setAccessibilityLabel(help)
                button.isBordered = false
                button.setButtonType(.toggle)
                button.controlSize = .small
                button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                button.cell?.lineBreakMode = label.contains("@") ? .byTruncatingMiddle : .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                SwitcherChrome.prepareSegment(button)
                button.state = account.isActive ? .on : .off
                button.isEnabled = !self.selectionPending
                row.addArrangedSubview(button)
                self.buttons.append(button)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -Self.railPadding * 2).isActive = true
            row.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: Self.railInset),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -Self.railInset),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
        self.updateStyles()
        SwitcherChrome.observeAccessibilityDisplayOptions(self, selector: #selector(self.displayOptionsDidChange))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        self.preferredSize
    }

    override var fittingSize: NSSize {
        self.preferredSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.updateStyles()
    }

    /// Increase Contrast changes the rail border and the resolved layer colors.
    @objc private func displayOptionsDidChange(_: Notification) {
        self.updateStyles()
    }

    /// Rail and segment colors for the current appearance. The active account is the selected segment.
    private func updateStyles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let appearance = self.effectiveAppearance
        SwitcherChrome.styleRail(self.rail.layer, appearance: appearance)
        for button in self.buttons {
            SwitcherChrome.styleSegment(button, selected: button.state == .on, appearance: appearance)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let descendant = super.hitTest(point)
        if descendant != nil, descendant !== self {
            self.toolTip = (descendant as? NSButton)?.toolTip
            return self
        }
        self.toolTip = nil
        return descendant
    }

    override func mouseDown(with event: NSEvent) {
        self.pressedAccountID = self.accountID(at: self.convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { self.pressedAccountID = nil }
        guard let id = self.pressedAccountID,
              self.accountID(at: self.convert(event.locationInWindow, from: nil)) == id
        else { return }
        self.select(id)
    }

    private func accountID(at point: NSPoint) -> ProviderAccountIdentity? {
        guard let button = self.buttons.first(where: { self.convert($0.bounds, from: $0).contains(point) })
        else { return nil }
        return self.accounts[button.tag].id
    }

    @objc private func handleSelect(_ sender: NSButton) {
        guard self.accounts.indices.contains(sender.tag) else { return }
        self.select(self.accounts[sender.tag].id)
    }

    private func select(_ id: ProviderAccountIdentity) {
        guard !self.selectionPending, let account = self.accounts.first(where: { $0.id == id }) else { return }
        if ClaudeSwapAccountMenuDisplay.activatesAccount(account) {
            self.selectionPending = true
            for button in self.buttons {
                button.isEnabled = false
            }
        }
        self.onSelect(id)
    }

    #if DEBUG
    func _test_select(_ id: ProviderAccountIdentity) {
        self.select(id)
    }
    #endif
}
