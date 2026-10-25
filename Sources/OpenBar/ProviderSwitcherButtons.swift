import AppKit
import OpenBarCore

// MARK: - Chrome

/// Calm-native switcher chrome shared by the provider and account switchers (docs/design/README.md §9.2):
/// a flat `cardFill` rail behind the segments, segments with radius 7, and a selected segment in
/// `accentFill` with white content. Plain layer properties only: no drawing, materials, shadows, or animation.
@MainActor
enum SwitcherChrome {
    /// Resolves a dynamic color for `appearance` before it becomes a `CGColor`.
    static func cgColor(_ color: () -> NSColor, for appearance: NSAppearance) -> CGColor {
        var resolved = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = color().cgColor
        }
        return resolved
    }

    /// Styles `layer` as the rail: `cardFill`, radius 9, and a 1-pt `cardStroke` with Increase Contrast.
    /// These layers sit outside the SwiftUI tree, so Increase Contrast is read from the workspace.
    static func styleRail(_ layer: CALayer?, appearance: NSAppearance) {
        guard let layer else { return }
        layer.cornerRadius = OpenBarRadius.rail
        layer.cornerCurve = .continuous
        layer.backgroundColor = self.cgColor({ OpenBarTheme.NSColors.cardFill }, for: appearance)
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            layer.borderWidth = 1
            layer.borderColor = self.cgColor({ OpenBarTheme.NSColors.switcherRailStroke }, for: appearance)
        } else {
            layer.borderWidth = 0
            layer.borderColor = nil
        }
    }

    /// Gives a segment its plate shape. Call once after creating the button.
    static func prepareSegment(_ button: NSButton) {
        button.wantsLayer = true
        button.layer?.cornerRadius = OpenBarRadius.control
        button.layer?.cornerCurve = .continuous
    }

    /// Selected: `accentFill` plate with white content. Hovered: `labelColor` 6 % plate. Otherwise no plate and
    /// secondary content.
    static func styleSegment(
        _ button: NSButton,
        selected: Bool,
        hovered: Bool = false,
        appearance: NSAppearance)
    {
        button.layer?.backgroundColor = if selected {
            self.cgColor({ OpenBarTheme.NSColors.accentFill }, for: appearance)
        } else if hovered {
            self.cgColor({ OpenBarTheme.NSColors.switcherHover }, for: appearance)
        } else {
            nil
        }
        button.contentTintColor = self.contentColor(selected: selected)
    }

    static func contentColor(selected: Bool) -> NSColor {
        selected ? .white : .secondaryLabelColor
    }

    /// Calls `selector` when Increase Contrast or another display option changes, so a switcher re-resolves its
    /// layer colors and the rail border. Selector-based: AppKit drops the observer when it deallocates.
    static func observeAccessibilityDisplayOptions(_ observer: NSObject, selector: Selector) {
        NSWorkspace.shared.notificationCenter.addObserver(
            observer,
            selector: selector,
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil)
    }
}

/// The provider switcher's rail: one plain layer-backed view behind the segments. It never draws, so it has no
/// backing store; the owner sets its frame to the segments' bounds plus the rail padding.
final class SwitcherRailView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.applyStyle()
    }

    func applyStyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        SwitcherChrome.styleRail(self.layer, appearance: self.effectiveAppearance)
    }
}

// MARK: - Quota figure

/// A provider segment that can show its worst-lane quota figure ("62%").
@MainActor
protocol SwitcherQuotaSegment: AnyObject {
    /// Sets the figure. Returns true when it changed.
    @discardableResult
    func setQuotaSummary(_ summary: ProviderSwitcherQuotaSummary?) -> Bool
    /// Drops the tone symbol, then the figure, when the segment is too narrow for them. Nil width shows all.
    func fitQuota(segmentWidth: CGFloat?)
    /// Measures the segment without its tone symbol, so a crowded row keeps every figure; `fitQuota` restores the
    /// symbol where the final width allows.
    func suppressQuotaSymbol()
    /// White figure on the selected (`accentFill`) segment. Also re-applies colors after appearance or
    /// Increase Contrast changes.
    func setQuotaOnAccent(_ onAccent: Bool)
}

/// The worst-lane quota figure in a provider segment: an optional tone symbol and a tabular percent, as two plain
/// views the owning button arranges. Colors are dynamic system or token colors that resolve when drawn.
@MainActor
final class SwitcherQuotaNumeral {
    /// Gap between the tone symbol and the figure; the label's own 2-pt inset adds the rest.
    static let symbolGap: CGFloat = 0

    let symbolView = NSImageView()
    let textField = NSTextField(labelWithString: "")
    private(set) var summary: ProviderSwitcherQuotaSummary?
    private var isOnAccent = false
    private var allowsSymbol = true
    private var allowsFigure = true

    init() {
        self.symbolView.imageScaling = .scaleNone
        self.symbolView.translatesAutoresizingMaskIntoConstraints = false
        self.symbolView.setAccessibilityElement(false)
        self.symbolView.isHidden = true
        self.textField.translatesAutoresizingMaskIntoConstraints = false
        self.textField.lineBreakMode = .byClipping
        self.textField.maximumNumberOfLines = 1
        self.textField.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.textField.setContentHuggingPriority(.required, for: .horizontal)
        self.textField.setAccessibilityElement(false)
        self.textField.isHidden = true
    }

    @discardableResult
    func setSummary(_ summary: ProviderSwitcherQuotaSummary?) -> Bool {
        guard summary != self.summary else { return false }
        self.summary = summary
        self.textField.stringValue = summary?.numeralText ?? ""
        self.textField.font = Self.font(emphasized: summary?.isEmphasized ?? false)
        self.symbolView.image = summary?.toneSymbolName.flatMap { Self.symbolImage(named: $0) }
        self.allowsSymbol = true
        self.allowsFigure = true
        self.applyVisibility()
        self.applyColors()
        return true
    }

    /// Also re-applies colors when the appearance or Increase Contrast changes, so call it on every style pass.
    func setOnAccent(_ onAccent: Bool) {
        self.isOnAccent = onAccent
        self.applyColors()
    }

    /// Width of the symbol and figure as the stack lays them out (intrinsic sizes plus the symbol gap).
    func width(includingSymbol: Bool) -> CGFloat {
        guard self.summary != nil else { return 0 }
        var width = self.textField.intrinsicContentSize.width
        if includingSymbol, let image = self.symbolView.image {
            width += image.size.width + Self.symbolGap
        }
        return width
    }

    func suppressSymbol() {
        self.allowsSymbol = false
        self.applyVisibility()
    }

    /// Keeps the symbol and figure only while `fixedWidth + leadingGap + figure` fits `available`. The 1-pt
    /// tolerance absorbs the switcher's even-width rounding; it lands in the segment's 4-pt content padding.
    func fit(available: CGFloat?, fixedWidth: CGFloat, leadingGap: CGFloat) {
        self.allowsSymbol = true
        self.allowsFigure = true
        if let available = available.map({ $0 + 1 }), self.summary != nil {
            let base = fixedWidth + leadingGap
            if base + self.width(includingSymbol: true) > available {
                self.allowsSymbol = false
                self.allowsFigure = base + self.width(includingSymbol: false) <= available
            }
        }
        self.applyVisibility()
    }

    /// Figure color: white on `accentFill`; the tone color at warning or critical; secondary otherwise. Stale is
    /// text, so it stays secondary (spec §2.2) and carries the `clock` symbol instead.
    static func color(for summary: ProviderSwitcherQuotaSummary, onAccent: Bool) -> NSColor {
        guard !onAccent else { return .white }
        return switch summary.tone {
        case .warning, .critical: summary.tone.color?.nsColor ?? .secondaryLabelColor
        case .normal, .stale: .secondaryLabelColor
        }
    }

    static func font(emphasized: Bool) -> NSFont {
        .monospacedDigitSystemFont(
            ofSize: OpenBarTheme.Switcher.numeralSize,
            weight: emphasized ? .semibold : .medium)
    }

    /// The tone symbol as a template image; the image view tints it with the figure color.
    static func symbolImage(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: OpenBarTheme.Switcher.numeralSymbolSize,
            weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func applyVisibility() {
        let showsFigure = self.summary != nil && self.allowsFigure
        self.textField.isHidden = !showsFigure
        self.symbolView.isHidden = !showsFigure || !self.allowsSymbol || self.symbolView.image == nil
    }

    private func applyColors() {
        guard let summary else { return }
        let color = Self.color(for: summary, onAccent: self.isOnAccent)
        self.textField.textColor = color
        self.symbolView.contentTintColor = color
        self.textField.needsDisplay = true
        self.symbolView.needsDisplay = true
    }
}

// MARK: - Buttons

final class PaddedToggleButton: NSButton {
    var contentPadding = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7) {
        didSet {
            if oldValue.top != self.contentPadding.top ||
                oldValue.left != self.contentPadding.left ||
                oldValue.bottom != self.contentPadding.bottom ||
                oldValue.right != self.contentPadding.right
            {
                self.invalidateIntrinsicContentSize()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(
            width: size.width + self.contentPadding.left + self.contentPadding.right,
            height: size.height + self.contentPadding.top + self.contentPadding.bottom)
    }
}

final class InlineIconToggleButton: NSButton {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private let quotaNumeral = SwitcherQuotaNumeral()
    private var paddingConstraints: [NSLayoutConstraint] = []
    private var iconSizeConstraints: [NSLayoutConstraint] = []
    private var isConfiguring = false // Batch invalidation during setup

    private static let iconSize: CGFloat = 16
    private static let iconTitleSpacing: CGFloat = 1
    /// The two labels' 2-pt insets add to this gap.
    private static let titleQuotaSpacing: CGFloat = 2

    var contentPadding = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7) {
        didSet {
            self.paddingConstraints.first { $0.firstAttribute == .top }?.constant = self.contentPadding.top
            self.paddingConstraints.first { $0.firstAttribute == .leading }?.constant = self.contentPadding.left
            self.paddingConstraints.first { $0.firstAttribute == .trailing }?.constant = -self.contentPadding.right
            self.paddingConstraints.first { $0.firstAttribute == .bottom }?.constant = -self.contentPadding.bottom
            if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        }
    }

    override var title: String {
        get { "" }
        set {
            super.title = ""
            super.alternateTitle = ""
            super.attributedTitle = NSAttributedString(string: "")
            super.attributedAlternateTitle = NSAttributedString(string: "")
            self.titleField.stringValue = newValue
            self.setAccessibilityLabel(newValue)
            if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        }
    }

    override var image: NSImage? {
        get { nil }
        set {
            super.image = nil
            super.alternateImage = nil
            self.iconView.image = newValue
            if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        }
    }

    func setContentTintColor(_ color: NSColor?) {
        self.iconView.contentTintColor = color
        self.titleField.textColor = color
    }

    func setTitleFontSize(_ size: CGFloat) {
        self.titleField.font = NSFont.systemFont(ofSize: size)
    }

    override var intrinsicContentSize: NSSize {
        let size = self.stack.fittingSize
        return NSSize(
            width: size.width + self.contentPadding.left + self.contentPadding.right,
            height: size.height + self.contentPadding.top + self.contentPadding.bottom)
    }

    init(title: String, image: NSImage, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.isConfiguring = true // Batch invalidations during setup
        self.configure()
        self.title = title
        self.image = image
        self.isConfiguring = false
        self.invalidateIntrinsicContentSize() // Single invalidation after setup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.toggle)
        self.controlSize = .small
        self.wantsLayer = true
        self.setAccessibilityRole(.button)

        self.iconView.imageScaling = .scaleNone
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.titleField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        self.titleField.alignment = .left
        self.titleField.lineBreakMode = .byTruncatingTail
        self.titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.setContentTintColor(NSColor.secondaryLabelColor)

        self.stack.orientation = .horizontal
        self.stack.alignment = .centerY
        self.stack.spacing = Self.iconTitleSpacing
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.stack.addArrangedSubview(self.iconView)
        self.stack.addArrangedSubview(self.titleField)
        self.stack.addArrangedSubview(self.quotaNumeral.symbolView)
        self.stack.addArrangedSubview(self.quotaNumeral.textField)
        self.stack.setCustomSpacing(Self.titleQuotaSpacing, after: self.titleField)
        self.stack.setCustomSpacing(SwitcherQuotaNumeral.symbolGap, after: self.quotaNumeral.symbolView)
        self.addSubview(self.stack)

        let iconWidth = self.iconView.widthAnchor.constraint(equalToConstant: Self.iconSize)
        let iconHeight = self.iconView.heightAnchor.constraint(equalToConstant: Self.iconSize)
        self.iconSizeConstraints = [iconWidth, iconHeight]

        let top = self.stack.topAnchor.constraint(
            greaterThanOrEqualTo: self.topAnchor,
            constant: self.contentPadding.top)
        let leading = self.stack.leadingAnchor.constraint(
            greaterThanOrEqualTo: self.leadingAnchor,
            constant: self.contentPadding.left)
        let trailing = self.stack.trailingAnchor.constraint(
            lessThanOrEqualTo: self.trailingAnchor,
            constant: -self.contentPadding.right)
        let centerX = self.stack.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        centerX.priority = .defaultHigh
        let centerY = self.stack.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        let bottom = self.stack.bottomAnchor.constraint(
            lessThanOrEqualTo: self.bottomAnchor,
            constant: -self.contentPadding.bottom)
        self.paddingConstraints = [top, leading, trailing, bottom, centerX, centerY]

        NSLayoutConstraint.activate(self.paddingConstraints + self.iconSizeConstraints)
    }
}

extension InlineIconToggleButton: SwitcherQuotaSegment {
    @discardableResult
    func setQuotaSummary(_ summary: ProviderSwitcherQuotaSummary?) -> Bool {
        guard self.quotaNumeral.setSummary(summary) else { return false }
        self.setAccessibilityValue(summary?.numeralText)
        if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        return true
    }

    /// The figure follows the full title; when both do not fit, the title keeps its width as before.
    func fitQuota(segmentWidth: CGFloat?) {
        let available = segmentWidth.map { $0 - self.contentPadding.left - self.contentPadding.right }
        let fixedWidth = Self.iconSize + Self.iconTitleSpacing + self.titleField.intrinsicContentSize.width
        self.quotaNumeral.fit(available: available, fixedWidth: fixedWidth, leadingGap: Self.titleQuotaSpacing)
        self.invalidateIntrinsicContentSize()
    }

    func setQuotaOnAccent(_ onAccent: Bool) {
        self.quotaNumeral.setOnAccent(onAccent)
    }

    func suppressQuotaSymbol() {
        self.quotaNumeral.suppressSymbol()
        self.invalidateIntrinsicContentSize()
    }
}

final class StackedToggleButton: NSButton {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let iconRow = NSStackView()
    private let stack = NSStackView()
    private let quotaNumeral = SwitcherQuotaNumeral()
    private var paddingConstraints: [NSLayoutConstraint] = []
    private var iconSizeConstraints: [NSLayoutConstraint] = []
    private var isConfiguring = false // Batch invalidation during setup
    private var titleFontSize = OpenBarTheme.Switcher.stackedTitleSize

    private static let iconSize: CGFloat = 16
    /// The figure label's 2-pt inset adds to this gap.
    private static let iconQuotaSpacing: CGFloat = 1

    var contentPadding = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4) {
        didSet {
            self.paddingConstraints.first { $0.firstAttribute == .top }?.constant = self.contentPadding.top
            self.paddingConstraints.first { $0.firstAttribute == .leading }?.constant = self.contentPadding.left
            self.paddingConstraints.first { $0.firstAttribute == .trailing }?.constant = -self.contentPadding.right
            self.paddingConstraints.first { $0.firstAttribute == .bottom }?.constant = -self.contentPadding.bottom
            if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        }
    }

    /// The selected segment's title is medium weight (spec §9.2).
    override var state: NSControl.StateValue {
        didSet {
            if oldValue != self.state { self.updateTitleFont() }
        }
    }

    override var title: String {
        get { "" }
        set {
            super.title = ""
            super.alternateTitle = ""
            super.attributedTitle = NSAttributedString(string: "")
            super.attributedAlternateTitle = NSAttributedString(string: "")
            self.titleField.stringValue = newValue
            self.setAccessibilityLabel(newValue)
            if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        }
    }

    /// A nil image hides the icon: the text-only switcher uses this form to put a quota figure over the title.
    override var image: NSImage? {
        get { nil }
        set {
            super.image = nil
            super.alternateImage = nil
            self.iconView.image = newValue
            self.iconView.isHidden = newValue == nil
            if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        }
    }

    func setContentTintColor(_ color: NSColor?) {
        self.iconView.contentTintColor = color
        self.titleField.textColor = color
    }

    func setTitleFontSize(_ size: CGFloat) {
        self.titleFontSize = size
        self.updateTitleFont()
    }

    /// Icon plus the quota figure, as the icon row needs it before the segment width is known.
    var quotaRowFittingWidth: CGFloat {
        let iconWidth = self.iconView.isHidden ? 0 : Self.iconSize
        guard self.quotaNumeral.summary != nil else { return iconWidth }
        let symbolWidth = self.quotaNumeral.width(includingSymbol: !self.quotaNumeral.symbolView.isHidden)
        return iconWidth + self.iconQuotaGap + symbolWidth
    }

    private var iconQuotaGap: CGFloat {
        self.iconView.isHidden ? 0 : Self.iconQuotaSpacing
    }

    override var intrinsicContentSize: NSSize {
        let size = self.stack.fittingSize
        return NSSize(
            width: size.width + self.contentPadding.left + self.contentPadding.right,
            height: size.height + self.contentPadding.top + self.contentPadding.bottom)
    }

    init(title: String, image: NSImage, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.isConfiguring = true // Batch invalidations during setup
        self.configure()
        self.title = title
        self.image = image
        self.isConfiguring = false
        self.invalidateIntrinsicContentSize() // Single invalidation after setup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func updateTitleFont() {
        self.titleField.font = NSFont.systemFont(
            ofSize: self.titleFontSize,
            weight: self.state == .on ? .medium : .regular)
        if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
    }

    private func configure() {
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.setButtonType(.toggle)
        self.controlSize = .small
        self.wantsLayer = true
        self.setAccessibilityRole(.button)

        self.iconView.imageScaling = .scaleNone
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.updateTitleFont()
        self.titleField.alignment = .center
        self.titleField.lineBreakMode = .byTruncatingTail
        self.titleField.maximumNumberOfLines = 1
        self.titleField.usesSingleLineMode = true
        self.setContentTintColor(NSColor.secondaryLabelColor)

        // Icon row: the logo, then the worst-lane figure when there is one ("◉ 62%"), so the segment keeps its
        // height.
        self.iconRow.orientation = .horizontal
        self.iconRow.alignment = .centerY
        self.iconRow.spacing = SwitcherQuotaNumeral.symbolGap
        // Hug the row's views so it stays centered over the title instead of stretching to the segment width.
        self.iconRow.setHuggingPriority(.defaultHigh, for: .horizontal)
        self.iconRow.translatesAutoresizingMaskIntoConstraints = false
        self.iconRow.addArrangedSubview(self.iconView)
        self.iconRow.addArrangedSubview(self.quotaNumeral.symbolView)
        self.iconRow.addArrangedSubview(self.quotaNumeral.textField)
        self.iconRow.setCustomSpacing(Self.iconQuotaSpacing, after: self.iconView)

        self.stack.orientation = .vertical
        self.stack.alignment = .centerX
        self.stack.spacing = 0
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.stack.addArrangedSubview(self.iconRow)
        self.stack.addArrangedSubview(self.titleField)
        self.addSubview(self.stack)

        let iconWidth = self.iconView.widthAnchor.constraint(equalToConstant: Self.iconSize)
        let iconHeight = self.iconView.heightAnchor.constraint(equalToConstant: Self.iconSize)
        self.iconSizeConstraints = [iconWidth, iconHeight]

        // Force an even layout width (button width minus padding) so the icon doesn't land on 0.5pt centers.
        let top = self.stack.topAnchor.constraint(
            greaterThanOrEqualTo: self.topAnchor,
            constant: self.contentPadding.top)
        let leading = self.stack.leadingAnchor.constraint(
            equalTo: self.leadingAnchor,
            constant: self.contentPadding.left)
        let trailing = self.stack.trailingAnchor.constraint(
            equalTo: self.trailingAnchor,
            constant: -self.contentPadding.right)
        let bottom = self.stack.bottomAnchor.constraint(
            lessThanOrEqualTo: self.bottomAnchor,
            constant: -self.contentPadding.bottom)
        let centerY = self.stack.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        self.paddingConstraints = [top, leading, trailing, bottom, centerY]

        NSLayoutConstraint.activate(self.paddingConstraints + self.iconSizeConstraints)
    }
}

extension StackedToggleButton: SwitcherQuotaSegment {
    @discardableResult
    func setQuotaSummary(_ summary: ProviderSwitcherQuotaSummary?) -> Bool {
        guard self.quotaNumeral.setSummary(summary) else { return false }
        self.setAccessibilityValue(summary?.numeralText)
        if !self.isConfiguring { self.invalidateIntrinsicContentSize() }
        return true
    }

    /// The figure shares the icon row; it is dropped (symbol first) only when the row would overflow the segment.
    func fitQuota(segmentWidth: CGFloat?) {
        let available = segmentWidth.map { $0 - self.contentPadding.left - self.contentPadding.right }
        let iconWidth = self.iconView.isHidden ? 0 : Self.iconSize
        self.quotaNumeral.fit(available: available, fixedWidth: iconWidth, leadingGap: self.iconQuotaGap)
        self.invalidateIntrinsicContentSize()
    }

    func setQuotaOnAccent(_ onAccent: Bool) {
        self.quotaNumeral.setOnAccent(onAccent)
    }

    func suppressQuotaSymbol() {
        self.quotaNumeral.suppressSymbol()
        self.invalidateIntrinsicContentSize()
    }
}
