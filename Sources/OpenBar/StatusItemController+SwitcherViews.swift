import AppKit
import OpenBarCore
import QuartzCore

enum ProviderSwitcherSelection: Hashable {
    case overview
    case provider(ProviderInstanceID)
}

final class ProviderSwitcherView: NSView {
    private struct Segment {
        let selection: ProviderSwitcherSelection
        let image: NSImage
        let title: String
    }

    fileprivate struct QuotaIndicator {
        /// The strip's full-width container. Its track capsule is a sublayer laid out after the fill.
        let track: SwitcherQuotaStripView
        let fill: NSView
        var fillWidthConstraint: NSLayoutConstraint
        var fillRatio: CGFloat
    }

    private let segments: [Segment]
    /// Segment count for `MemoryScenarioProbe`, which cycles every tab.
    var segmentCountForProbe: Int {
        self.segments.count
    }

    private let onSelect: (ProviderSwitcherSelection) -> Void
    private let showsIcons: Bool
    private let weeklyRemainingProvider: (ProviderInstanceID) -> Double?
    private let quotaSummaryProvider: (ProviderInstanceID) -> ProviderSwitcherQuotaSummary?
    private var buttons: [NSButton] = []
    private var quotaIndicators: [ObjectIdentifier: QuotaIndicator] = [:]
    private var hoverTrackingArea: NSTrackingArea?
    private var segmentWidths: [CGFloat] = []
    /// One flat `cardFill` shape behind the segments; `layout()` keeps it on the segments' bounds.
    private let railView = SwitcherRailView()
    private let stackedIcons: Bool
    private let rowCount: Int
    private let rowSpacing: CGFloat
    private let rowHeight: CGFloat
    private var preferredWidth: CGFloat = 0
    private var hoveredButtonTag: Int?
    private var pressedButtonTag: Int?
    private var selectedSegmentIndex: Int?
    fileprivate static let quotaIndicatorHeight: CGFloat = 2
    private static let quotaIndicatorBottomInset: CGFloat = 2
    private static let quotaIndicatorHorizontalInset: CGFloat = 8
    private static let railPadding = OpenBarTheme.Switcher.railPadding

    init(
        providers: [UsageProvider],
        pluginProviders: [UserProviderPlugin] = [],
        selected: ProviderSwitcherSelection?,
        includesOverview: Bool,
        width: CGFloat,
        showsIcons: Bool,
        iconProvider: (UsageProvider) -> NSImage,
        pluginIconProvider: (UserProviderPlugin) -> NSImage = { _ in NSImage() },
        weeklyRemainingProvider: @escaping (ProviderInstanceID) -> Double?,
        quotaSummaryProvider: @escaping (ProviderInstanceID) -> ProviderSwitcherQuotaSummary? = { _ in nil },
        onSelect: @escaping (ProviderSwitcherSelection) -> Void)
    {
        let minimumGap: CGFloat = 1
        var segments = providers.map { provider in
            let fullTitle = Self.switcherTitle(for: provider)
            let icon = iconProvider(provider)
            icon.isTemplate = true
            // Avoid any resampling: we ship exact 16pt/32px assets for crisp rendering.
            icon.size = NSSize(width: 16, height: 16)
            return Segment(
                selection: .provider(provider.instanceID),
                image: icon,
                title: fullTitle)
        }
        segments.append(contentsOf: pluginProviders.map { plugin in
            Segment(
                selection: .provider(plugin.manifest.id),
                image: Self.pluginSwitcherImage(plugin, iconProvider: pluginIconProvider),
                title: plugin.manifest.name)
        })
        if includesOverview {
            let overviewIcon = Self.overviewIcon()
            overviewIcon.isTemplate = true
            overviewIcon.size = NSSize(width: 16, height: 16)
            segments.insert(
                Segment(
                    selection: .overview,
                    image: overviewIcon,
                    title: L("Overview")),
                at: 0)
        }
        self.segments = segments
        self.onSelect = onSelect
        self.showsIcons = showsIcons
        self.weeklyRemainingProvider = weeklyRemainingProvider
        self.quotaSummaryProvider = quotaSummaryProvider
        let quotaSummaries = segments.map { Self.quotaSummary(for: $0.selection, provider: quotaSummaryProvider) }
        self.stackedIcons = Self.usesStackedSegments(
            count: self.segments.count, showsIcons: showsIcons, hasQuotaFigures: quotaSummaries.contains { $0 != nil })
        let initialOuterPadding = Self.switcherOuterPadding(
            for: width,
            count: self.segments.count,
            minimumGap: minimumGap)
        let initialMaxAllowedSegmentWidth = Self.maxAllowedUniformSegmentWidth(
            for: width,
            count: self.segments.count,
            outerPadding: initialOuterPadding,
            minimumGap: minimumGap)
        self.rowCount = Self.switcherRowCount(
            width: width,
            count: self.segments.count,
            maxAllowedSegmentWidth: initialMaxAllowedSegmentWidth,
            stackedIcons: self.stackedIcons)
        self.rowSpacing = self.stackedIcons ? 4 : 2
        self.rowHeight = Self.switcherButtonHeight(stackedIcons: self.stackedIcons, rowCount: self.rowCount)
        // The rail adds its padding above and below the segment rows.
        let height: CGFloat = self.rowHeight * CGFloat(self.rowCount)
            + self.rowSpacing * CGFloat(max(0, self.rowCount - 1))
            + Self.railPadding * 2
        self.preferredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        Self.clearButtonWidthCache()
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.installRail()

        func makeButton(index: Int, segment: Segment) -> NSButton {
            let button: NSButton
            if self.stackedIcons {
                let stacked = StackedToggleButton(
                    title: segment.title,
                    image: segment.image,
                    target: self,
                    action: #selector(self.handleSelection(_:)))
                if self.rowCount >= 4 {
                    // The dense four-row form keeps its title one point smaller, as before.
                    stacked.setTitleFontSize(OpenBarTheme.Switcher.stackedTitleSize - 1)
                }
                button = stacked
            } else if self.showsIcons {
                let inline = InlineIconToggleButton(
                    title: segment.title,
                    image: segment.image,
                    target: self,
                    action: #selector(self.handleSelection(_:)))
                button = inline
            } else {
                button = PaddedToggleButton(
                    title: segment.title,
                    target: self,
                    action: #selector(self.handleSelection(_:)))
            }
            button.tag = index
            // StackedToggleButton and InlineIconToggleButton manage their own image views.
            if !self.showsIcons {
                button.image = nil
                button.imagePosition = .noImage
            }

            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            button.setButtonType(.toggle)
            button.contentTintColor = SwitcherChrome.contentColor(selected: false)
            button.alignment = .center
            SwitcherChrome.prepareSegment(button)
            button.state = (selected == segment.selection) ? .on : .off
            button.toolTip = nil
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: self.rowHeight).isActive = true
            self.buttons.append(button)
            return button
        }

        for (index, segment) in self.segments.enumerated() {
            let button = makeButton(index: index, segment: segment)
            // Before the widths are measured, so a segment's figure counts toward its width.
            (button as? SwitcherQuotaSegment)?.setQuotaSummary(quotaSummaries[index])
            self.addSubview(button)
            self.addQuotaIndicator(
                to: button,
                selection: segment.selection,
                remainingPercent: self.remainingPercent(for: segment.selection))
        }
        self.selectedSegmentIndex = selected.flatMap { selected in
            self.segments.firstIndex { $0.selection == selected }
        }

        let layoutCount = Self.layoutCount(for: self.segments.count, rows: self.rowCount)
        let requiredUniformWidth = self.stackedIcons
            ? nil
            : self.buttons.map(Self.maxToggleWidth(for:)).max()
        let layoutMetrics = Self.switcherLayoutMetrics(
            for: width,
            count: layoutCount,
            minimumGap: minimumGap,
            requiredSegmentWidth: requiredUniformWidth)

        let uniformWidth: CGFloat
        if self.rowCount > 1 || !self.stackedIcons {
            uniformWidth = self.applyUniformSegmentWidth(maxAllowedWidth: layoutMetrics.maxAllowedSegmentWidth)
            if uniformWidth > 0 {
                self.segmentWidths = Array(repeating: uniformWidth, count: self.buttons.count)
            }
        } else {
            self.segmentWidths = self.applyNonUniformSegmentWidths(
                totalWidth: width,
                outerPadding: layoutMetrics.outerPadding,
                minimumGap: minimumGap)
            uniformWidth = 0
        }

        self.applyLayout(
            outerPadding: layoutMetrics.outerPadding,
            minimumGap: minimumGap,
            uniformWidth: uniformWidth)
        if width > 0 {
            self.preferredWidth = width
            self.frame.size.width = width
        }
        self.fitQuotaFigures()

        self.updateButtonStyles()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.updateButtonStyles()
    }

    /// The rail goes in first, behind every segment. Increase Contrast changes its border and the layer colors.
    private func installRail() {
        self.addSubview(self.railView)
        SwitcherChrome.observeAccessibilityDisplayOptions(self, selector: #selector(self.displayOptionsDidChange))
    }

    @objc private func displayOptionsDidChange(_: Notification) {
        self.railView.applyStyle()
        self.updateButtonStyles()
    }

    override func layout() {
        super.layout()
        // The rail hugs the segments with its padding on every side, whatever outer padding the layout chose.
        let segmentBounds = self.buttons.reduce(NSRect.null) { $0.union($1.frame) }
        let railFrame = segmentBounds.isNull
            ? .zero
            : segmentBounds.insetBy(dx: -Self.railPadding, dy: -Self.railPadding)
        guard self.railView.frame != railFrame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        self.railView.frame = railFrame
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            window.acceptsMouseMovedEvents = true
        } else if self.hoveredButtonTag != nil {
            self.hoveredButtonTag = nil
            self.updateButtonStyles()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            self.removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ],
            owner: self,
            userInfo: nil)
        self.addTrackingArea(trackingArea)
        self.hoverTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let location = self.convert(event.locationInWindow, from: nil)
        let hoveredTag = self.button(at: location)?.tag
        guard hoveredTag != self.hoveredButtonTag else { return }
        self.hoveredButtonTag = hoveredTag
        self.updateButtonStyles()
    }

    override func mouseExited(with event: NSEvent) {
        guard self.hoveredButtonTag != nil else { return }
        self.hoveredButtonTag = nil
        self.updateButtonStyles()
    }

    // MARK: - Click handling

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // NSMenu's tracking run loop occasionally drops NSButton target-action dispatch when the
        // menu is rebuilt under the cursor (e.g. after switching back from a provider tab to
        // Overview). The overrides in this section hit-test the parent view, then drive
        // selection from mouseDown/mouseUp here so the click never has to round-trip through
        // NSButton's tracking loop. See issue #867.
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let descendant = super.hitTest(point)
        if descendant != nil, descendant !== self {
            // Swallow any hit on a child NSButton so its tracking loop never sees the click.
            return self
        }
        return descendant
    }

    override func mouseDown(with event: NSEvent) {
        _ = self.handleMenuTrackingMouseDown(event)
    }

    override func mouseUp(with event: NSEvent) {
        _ = self.handleMenuTrackingMouseUp(event)
    }

    @discardableResult
    func handleMenuTrackingMouseDown(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown else { return false }
        let location = self.locationInView(for: event)
        guard let pressedTag = self.button(at: location)?.tag,
              self.segments.indices.contains(pressedTag)
        else {
            return false
        }
        self.pressedButtonTag = pressedTag
        return true
    }

    @discardableResult
    func handleMenuTrackingMouseUp(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseUp else { return false }
        defer { self.pressedButtonTag = nil }
        guard let pressedTag = self.pressedButtonTag else { return false }
        let location = self.locationInView(for: event)
        guard let releasedTag = self.button(at: location)?.tag,
              releasedTag == pressedTag
        else {
            return true
        }
        // Commit only after the matching release. The controller schedules structural menu
        // replacement after this callback returns so AppKit can finish the tracking transaction.
        self.applySelection(at: pressedTag)
        return true
    }

    private func locationInView(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window,
              let viewWindow = self.window,
              eventWindow !== viewWindow
        else {
            return self.convert(event.locationInWindow, from: nil)
        }
        let screenLocation = eventWindow.convertPoint(toScreen: event.locationInWindow)
        return self.convert(viewWindow.convertPoint(fromScreen: screenLocation), from: nil)
    }

    func handleKeyboardSelection(at index: Int) -> Bool {
        guard self.segments.indices.contains(index) else { return false }
        self.applySelection(at: index)
        return true
    }

    private func applySelection(at index: Int) {
        let selection = self.segments[index].selection
        guard self.selectedSegmentIndex != index else {
            self.updateSelection(selection)
            return
        }
        self.updateSelection(selection)
        self.onSelect(selection)
    }

    private func applyLayout(
        outerPadding: CGFloat,
        minimumGap: CGFloat,
        uniformWidth: CGFloat)
    {
        if self.rowCount > 1 {
            self.applyMultiRowLayout(
                rowCount: self.rowCount,
                outerPadding: outerPadding,
                minimumGap: minimumGap,
                uniformWidth: uniformWidth)
            return
        }

        if self.buttons.count == 2 {
            let left = self.buttons[0]
            let right = self.buttons[1]
            let gap = right.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: minimumGap)
            gap.priority = .defaultHigh
            NSLayoutConstraint.activate([
                left.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
                left.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                right.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
                right.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                gap,
            ])
            return
        }

        if self.buttons.count == 3 {
            let left = self.buttons[0]
            let mid = self.buttons[1]
            let right = self.buttons[2]

            let leftGap = mid.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: minimumGap)
            leftGap.priority = .defaultHigh
            let rightGap = right.leadingAnchor.constraint(
                greaterThanOrEqualTo: mid.trailingAnchor,
                constant: minimumGap)
            rightGap.priority = .defaultHigh

            NSLayoutConstraint.activate([
                left.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
                left.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                mid.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                mid.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                right.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
                right.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                leftGap,
                rightGap,
            ])
            return
        }

        if self.buttons.count >= 4 {
            let widths = self.segmentWidths.isEmpty
                ? self.buttons.map { ceil($0.fittingSize.width) }
                : self.segmentWidths
            let layoutWidth = self.preferredWidth > 0 ? self.preferredWidth : self.bounds.width
            let availableWidth = max(0, layoutWidth - outerPadding * 2)
            let gaps = max(1, widths.count - 1)
            let computedGap = gaps > 0
                ? max(minimumGap, (availableWidth - widths.reduce(0, +)) / CGFloat(gaps))
                : 0
            let rowContainer = NSView()
            rowContainer.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(rowContainer)

            NSLayoutConstraint.activate([
                rowContainer.topAnchor.constraint(equalTo: self.topAnchor, constant: Self.railPadding),
                rowContainer.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -Self.railPadding),
                rowContainer.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
                rowContainer.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
            ])

            var xOffset: CGFloat = 0
            for (index, button) in self.buttons.enumerated() {
                let width = index < widths.count ? widths[index] : 0
                if self.stackedIcons {
                    NSLayoutConstraint.activate([
                        button.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: xOffset),
                        button.topAnchor.constraint(equalTo: rowContainer.topAnchor),
                    ])
                } else {
                    NSLayoutConstraint.activate([
                        button.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor, constant: xOffset),
                        button.centerYAnchor.constraint(equalTo: rowContainer.centerYAnchor),
                    ])
                }
                xOffset += width + computedGap
            }
            return
        }

        if let first = self.buttons.first {
            NSLayoutConstraint.activate([
                first.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                first.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            ])
        }
    }

    private func applyMultiRowLayout(
        rowCount: Int,
        outerPadding: CGFloat,
        minimumGap: CGFloat,
        uniformWidth: CGFloat)
    {
        let rows = Self.splitRows(for: self.buttons, rowCount: rowCount)
        let columns = rows.map(\.count).max() ?? 0
        let layoutWidth = self.preferredWidth > 0 ? self.preferredWidth : self.bounds.width
        let availableWidth = max(0, layoutWidth - outerPadding * 2)
        let gaps = max(1, columns - 1)
        let totalWidth = uniformWidth * CGFloat(columns)
        let computedGap = gaps > 0
            ? max(minimumGap, (availableWidth - totalWidth) / CGFloat(gaps))
            : 0
        let gridContainer = NSView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(gridContainer)

        NSLayoutConstraint.activate([
            gridContainer.topAnchor.constraint(equalTo: self.topAnchor, constant: Self.railPadding),
            gridContainer.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -Self.railPadding),
            gridContainer.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: outerPadding),
            gridContainer.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -outerPadding),
        ])

        var rowViews: [NSView] = []
        for _ in 0..<rowCount {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            gridContainer.addSubview(row)
            rowViews.append(row)
        }

        var rowConstraints: [NSLayoutConstraint] = []
        for (index, row) in rowViews.enumerated() {
            rowConstraints.append(row.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor))
            rowConstraints.append(row.trailingAnchor.constraint(equalTo: gridContainer.trailingAnchor))
            rowConstraints.append(row.heightAnchor.constraint(equalToConstant: self.rowHeight))
            if index == 0 {
                rowConstraints.append(row.topAnchor.constraint(equalTo: gridContainer.topAnchor))
            } else {
                rowConstraints.append(row.topAnchor.constraint(
                    equalTo: rowViews[index - 1].bottomAnchor,
                    constant: self.rowSpacing))
            }
            if index == rowViews.count - 1 {
                rowConstraints.append(row.bottomAnchor.constraint(equalTo: gridContainer.bottomAnchor))
            }
        }
        NSLayoutConstraint.activate(rowConstraints)

        for (rowIndex, rowButtons) in rows.enumerated() {
            guard rowIndex < rowViews.count else { continue }
            let rowView = rowViews[rowIndex]
            for (columnIndex, button) in rowButtons.enumerated() {
                let xOffset = CGFloat(columnIndex) * (uniformWidth + computedGap)
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: gridContainer.leadingAnchor, constant: xOffset),
                    button.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                ])
            }
        }
    }

    private static func switcherRowCount(
        width: CGFloat,
        count: Int,
        maxAllowedSegmentWidth: CGFloat,
        stackedIcons: Bool) -> Int
    {
        guard count > 1 else { return 1 }
        let maxRows = min(4, count)
        let fourRowThreshold = 15
        let minimumComfortableAverage: CGFloat = stackedIcons ? 50 : 54
        if count >= fourRowThreshold { return maxRows }
        if maxAllowedSegmentWidth >= minimumComfortableAverage { return 1 }

        for rows in 2...maxRows {
            let perRow = self.layoutCount(for: count, rows: rows)
            let outerPadding = self.switcherOuterPadding(for: width, count: perRow, minimumGap: 1)
            let allowedWidth = self.maxAllowedUniformSegmentWidth(
                for: width,
                count: perRow,
                outerPadding: outerPadding,
                minimumGap: 1)
            if allowedWidth >= minimumComfortableAverage { return rows }
        }

        return maxRows
    }

    private static func layoutCount(for count: Int, rows: Int) -> Int {
        guard rows > 0 else { return count }
        return Int(ceil(Double(count) / Double(rows)))
    }

    private static func splitRows(for buttons: [NSButton], rowCount: Int) -> [[NSButton]] {
        guard rowCount > 1 else { return [buttons] }
        let base = buttons.count / rowCount
        let extra = buttons.count % rowCount
        var rows: [[NSButton]] = []
        var start = 0
        for index in 0..<rowCount {
            let size = base + (index < extra ? 1 : 0)
            if size == 0 {
                rows.append([])
                continue
            }
            let end = min(buttons.count, start + size)
            rows.append(Array(buttons[start..<end]))
            start = end
        }
        return rows
    }

    private static func switcherButtonHeight(stackedIcons: Bool, rowCount: Int) -> CGFloat {
        guard stackedIcons else { return 30 }
        return rowCount >= 3 ? 39 : 36
    }

    private static func switcherOuterPadding(
        for width: CGFloat,
        count: Int,
        minimumGap: CGFloat,
        requiredSegmentWidth: CGFloat? = nil) -> CGFloat
    {
        // Put the rail on the cards' inset when possible: rail inset 8 plus its 2-pt padding. The rail follows the
        // segments when the padding has to shrink.
        let preferred: CGFloat = OpenBarTheme.Switcher.railInset + OpenBarTheme.Switcher.railPadding
        let minimal: CGFloat = 6

        func averageButtonWidth(outerPadding: CGFloat) -> CGFloat {
            let available = width - outerPadding * 2 - minimumGap * CGFloat(max(0, count - 1))
            guard count > 0 else { return 0 }
            return available / CGFloat(count)
        }

        // Only sacrifice padding when we'd otherwise squeeze buttons into unreadable widths.
        let minimumComfortableAverage: CGFloat = count >= 5 ? 50 : 54

        func fits(outerPadding: CGFloat) -> Bool {
            if let requiredSegmentWidth {
                let allowedWidth = self.maxAllowedUniformSegmentWidth(
                    for: width,
                    count: count,
                    outerPadding: outerPadding,
                    minimumGap: minimumGap)
                let evenAllowedWidth = allowedWidth.truncatingRemainder(dividingBy: 2) == 0
                    ? allowedWidth
                    : allowedWidth - 1
                let desiredWidth = ceil(requiredSegmentWidth)
                let evenDesiredWidth = desiredWidth.truncatingRemainder(dividingBy: 2) == 0
                    ? desiredWidth
                    : desiredWidth + 1
                return evenAllowedWidth >= evenDesiredWidth
            }
            return averageButtonWidth(outerPadding: outerPadding) >= minimumComfortableAverage
        }

        if fits(outerPadding: preferred) { return preferred }
        return minimal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: self.preferredWidth, height: self.frame.size.height)
    }

    func updateSelection(_ selection: ProviderSwitcherSelection) {
        var selectedIndex: Int?
        for (index, button) in self.buttons.enumerated() {
            let isSelected = self.segments.indices.contains(index) && self.segments[index].selection == selection
            if isSelected {
                selectedIndex = index
            }
            button.state = isSelected ? .on : .off
        }
        self.selectedSegmentIndex = selectedIndex
        self.updateButtonStyles()
    }

    func updateQuotaIndicators() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (index, button) in self.buttons.enumerated() {
            guard self.segments.indices.contains(index) else { continue }
            let segment = self.segments[index]
            if let quotaSegment = button as? SwitcherQuotaSegment,
               quotaSegment.setQuotaSummary(self.quotaSummary(for: segment.selection))
            {
                quotaSegment.fitQuota(segmentWidth: self.segmentWidth(at: index))
            }
            let remaining = self.remainingPercent(for: segment.selection)

            let key = ObjectIdentifier(button)
            if let remaining {
                if var indicator = self.quotaIndicators[key] {
                    let newRatio = Self.quotaIndicatorRatio(remainingPercent: remaining)
                    if newRatio != indicator.fillRatio {
                        Self.updateQuotaIndicatorFill(
                            indicator: &indicator,
                            remainingPercent: remaining,
                            selection: segment.selection)
                        self.quotaIndicators[key] = indicator
                    } else {
                        // The switcher view outlives a menu update, so refresh the color even when the
                        // ratio holds. A new accent color must not wait for usage to move.
                        indicator.fill.layer?.backgroundColor = Self.quotaIndicatorColor(
                            for: segment.selection,
                            remainingPercent: remaining).cgColor
                    }
                } else {
                    self.addQuotaIndicator(to: button, selection: segment.selection, remainingPercent: remaining)
                }
            } else if let indicator = self.quotaIndicators.removeValue(forKey: key) {
                indicator.track.removeFromSuperview()
                continue
            }
            self.updateQuotaIndicatorVisibility(for: button)
        }
        // New strips and figures take the selected or unselected colors.
        self.updateButtonStyles()
    }

    private func remainingPercent(for selection: ProviderSwitcherSelection) -> Double? {
        switch selection {
        case let .provider(instanceID):
            self.weeklyRemainingProvider(instanceID)
        case .overview:
            nil
        }
    }

    @objc private func handleSelection(_ sender: NSButton) {
        let index = sender.tag
        guard self.segments.indices.contains(index) else { return }
        self.applySelection(at: index)
    }

    private func updateButtonStyles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let appearance = self.effectiveAppearance
        for button in self.buttons {
            let isSelected = button.state == .on
            let isHovered = self.hoveredButtonTag == button.tag
            SwitcherChrome.styleSegment(button, selected: isSelected, hovered: isHovered, appearance: appearance)
            self.updateQuotaIndicatorVisibility(for: button)
            self.styleQuotaIndicator(for: button, selected: isSelected, appearance: appearance)
            (button as? StackedToggleButton)?.setContentTintColor(button.contentTintColor)
            (button as? InlineIconToggleButton)?.setContentTintColor(button.contentTintColor)
            (button as? SwitcherQuotaSegment)?.setQuotaOnAccent(isSelected)
        }
    }

    /// Cache for button width measurements to avoid repeated layout passes.
    private static var buttonWidthCache: [ObjectIdentifier: CGFloat] = [:]

    private static func maxToggleWidth(for button: NSButton) -> CGFloat {
        let buttonId = ObjectIdentifier(button)

        // Return cached value if available.
        if let cached = buttonWidthCache[buttonId] {
            return cached
        }

        let originalState = button.state
        defer { button.state = originalState }

        button.state = .off
        button.layoutSubtreeIfNeeded()
        let offWidth = button.fittingSize.width

        button.state = .on
        button.layoutSubtreeIfNeeded()
        let onWidth = button.fittingSize.width

        let maxWidth = max(offWidth, onWidth)
        self.buttonWidthCache[buttonId] = maxWidth
        return maxWidth
    }

    private static func clearButtonWidthCache() {
        self.buttonWidthCache.removeAll()
    }

    private func applyUniformSegmentWidth(maxAllowedWidth: CGFloat) -> CGFloat {
        guard !self.buttons.isEmpty else { return 0 }

        var desiredWidths: [CGFloat] = []
        desiredWidths.reserveCapacity(self.buttons.count)

        for (index, button) in self.buttons.enumerated() {
            if self.stackedIcons,
               self.segments.indices.contains(index)
            {
                let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                let titleWidth = ceil(
                    (self.segments[index].title as NSString).size(withAttributes: [.font: font])
                        .width)
                // The icon row also carries the quota figure ("◉ 62%") when there is one.
                let iconRowWidth = (button as? StackedToggleButton)?.quotaRowFittingWidth ?? 0
                let contentPadding: CGFloat = 4 + 4
                let extraSlack: CGFloat = 1
                desiredWidths.append(ceil(max(titleWidth, iconRowWidth) + contentPadding + extraSlack))
            } else {
                desiredWidths.append(ceil(Self.maxToggleWidth(for: button)))
            }
        }

        let maxDesired = desiredWidths.max() ?? 0
        let evenMaxDesired = maxDesired.truncatingRemainder(dividingBy: 2) == 0 ? maxDesired : maxDesired + 1
        let evenMaxAllowed = maxAllowedWidth > 0
            ? (maxAllowedWidth.truncatingRemainder(dividingBy: 2) == 0 ? maxAllowedWidth : maxAllowedWidth - 1)
            : 0
        let finalWidth: CGFloat = if evenMaxAllowed > 0 {
            min(evenMaxDesired, evenMaxAllowed)
        } else {
            evenMaxDesired
        }

        if finalWidth > 0 {
            for button in self.buttons {
                button.widthAnchor.constraint(equalToConstant: finalWidth).isActive = true
            }
        }

        return finalWidth
    }

    @discardableResult
    private func applyNonUniformSegmentWidths(
        totalWidth: CGFloat,
        outerPadding: CGFloat,
        minimumGap: CGFloat) -> [CGFloat]
    {
        guard !self.buttons.isEmpty else { return [] }

        let count = self.buttons.count
        let available = totalWidth -
            outerPadding * 2 -
            minimumGap * CGFloat(max(0, count - 1))
        guard available > 0 else { return [] }

        func evenFloor(_ value: CGFloat) -> CGFloat {
            var v = floor(value)
            if Int(v) % 2 != 0 { v -= 1 }
            return v
        }

        self.suppressQuotaSymbolsIfCrowded(available: available)
        let desired = self.buttons.map { ceil(Self.maxToggleWidth(for: $0)) }
        let desiredSum = desired.reduce(0, +)
        let avg = floor(available / CGFloat(count))
        let minWidth = max(24, min(40, avg))

        var widths: [CGFloat]
        if desiredSum <= available {
            widths = desired
        } else {
            let totalCapacity = max(0, desiredSum - minWidth * CGFloat(count))
            if totalCapacity <= 0 {
                widths = Array(repeating: available / CGFloat(count), count: count)
            } else {
                let overflow = desiredSum - available
                widths = desired.map { desiredWidth in
                    let capacity = max(0, desiredWidth - minWidth)
                    let shrink = overflow * (capacity / totalCapacity)
                    return desiredWidth - shrink
                }
            }
        }

        widths = widths.map { max(minWidth, evenFloor($0)) }
        var used = widths.reduce(0, +)

        while available - used >= 2 {
            if let best = widths.indices
                .filter({ desired[$0] - widths[$0] >= 2 })
                .max(by: { lhs, rhs in
                    (desired[lhs] - widths[lhs]) < (desired[rhs] - widths[rhs])
                })
            {
                widths[best] += 2
                used += 2
                continue
            }

            guard let best = widths.indices.min(by: { lhs, rhs in widths[lhs] < widths[rhs] }) else { break }
            widths[best] += 2
            used += 2
        }

        for (index, button) in self.buttons.enumerated() where index < widths.count {
            button.widthAnchor.constraint(equalToConstant: widths[index]).isActive = true
        }

        return widths
    }

    private static func maxAllowedUniformSegmentWidth(
        for totalWidth: CGFloat,
        count: Int,
        outerPadding: CGFloat,
        minimumGap: CGFloat) -> CGFloat
    {
        guard count > 0 else { return 0 }
        let available = totalWidth -
            outerPadding * 2 -
            minimumGap * CGFloat(max(0, count - 1))
        guard available > 0 else { return 0 }
        return floor(available / CGFloat(count))
    }

    private static func overviewIcon() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) {
            return symbol
        }
        return NSImage(size: NSSize(width: 16, height: 16))
    }

    private static func switcherTitle(for provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }
}

extension ProviderSwitcherView {
    private static func switcherLayoutMetrics(
        for width: CGFloat,
        count: Int,
        minimumGap: CGFloat,
        requiredSegmentWidth: CGFloat?) -> (outerPadding: CGFloat, maxAllowedSegmentWidth: CGFloat)
    {
        let outerPadding = self.switcherOuterPadding(
            for: width,
            count: count,
            minimumGap: minimumGap,
            requiredSegmentWidth: requiredSegmentWidth)
        let maxAllowedSegmentWidth = self.maxAllowedUniformSegmentWidth(
            for: width,
            count: count,
            outerPadding: outerPadding,
            minimumGap: minimumGap)
        return (outerPadding, maxAllowedSegmentWidth)
    }
}

extension ProviderSwitcherView {
    fileprivate func button(at location: NSPoint) -> NSButton? {
        self.buttons.first { $0.frame.contains(location) }
    }
}

extension ProviderSwitcherView {
    /// Worst-lane figure for a segment. The Overview segment has none.
    fileprivate static func quotaSummary(
        for selection: ProviderSwitcherSelection,
        provider: (ProviderInstanceID) -> ProviderSwitcherQuotaSummary?) -> ProviderSwitcherQuotaSummary?
    {
        switch selection {
        case let .provider(instanceID): provider(instanceID)
        case .overview: nil
        }
    }

    /// Inline when segments fit, stacked otherwise (spec §9.2). Quota figures stack sooner: three inline segments
    /// cannot fit "◉ Claude 62%" in a third of the menu, and a text-only segment puts its figure over its title.
    private static func usesStackedSegments(count: Int, showsIcons: Bool, hasQuotaFigures: Bool) -> Bool {
        hasQuotaFigures ? !showsIcons || count > 2 : showsIcons && count > 3
    }

    private func quotaSummary(for selection: ProviderSwitcherSelection) -> ProviderSwitcherQuotaSummary? {
        Self.quotaSummary(for: selection, provider: self.quotaSummaryProvider)
    }

    private func segmentWidth(at index: Int) -> CGFloat? {
        self.segmentWidths.indices.contains(index) ? self.segmentWidths[index] : nil
    }

    /// In a crowded single row, measures the widest figures without their tone symbols until the row fits, so every
    /// figure keeps its room. `fitQuotaFigures()` puts a symbol back wherever the final width allows.
    private func suppressQuotaSymbolsIfCrowded(available: CGFloat) {
        var desired = self.buttons.map { ceil(Self.maxToggleWidth(for: $0)) }
        var suppressed = Set<Int>()
        while desired.reduce(0, +) > available,
              let index = desired.indices.filter({ !suppressed.contains($0) }).max(by: { desired[$0] < desired[$1] })
        {
            suppressed.insert(index)
            guard let segment = self.buttons[index] as? SwitcherQuotaSegment else { continue }
            segment.suppressQuotaSymbol()
            Self.buttonWidthCache[ObjectIdentifier(self.buttons[index])] = nil
            desired[index] = ceil(Self.maxToggleWidth(for: self.buttons[index]))
        }
    }

    /// Drops a figure's tone symbol, then the figure, only in a segment too narrow for it.
    private func fitQuotaFigures() {
        for (index, button) in self.buttons.enumerated() {
            (button as? SwitcherQuotaSegment)?.fitQuota(segmentWidth: self.segmentWidth(at: index))
        }
    }
}

#if DEBUG
extension ProviderSwitcherView {
    func _test_mouseDownEvent(buttonTag: Int) -> NSEvent? {
        self._test_mouseEvent(buttonTag: buttonTag, type: .leftMouseDown)
    }

    func _test_mouseUpEvent(buttonTag: Int) -> NSEvent? {
        self._test_mouseEvent(buttonTag: buttonTag, type: .leftMouseUp)
    }

    func _test_quotaIndicatorMouseEvent(buttonTag: Int, type: NSEvent.EventType) -> NSEvent? {
        guard let button = self.buttons.first(where: { $0.tag == buttonTag }),
              let track = self.quotaIndicators[ObjectIdentifier(button)]?.track
        else {
            return nil
        }
        self.updateConstraintsForSubtreeIfNeeded()
        self.layoutSubtreeIfNeeded()
        let point = self.convert(NSPoint(x: track.bounds.midX, y: track.bounds.midY), from: track)
        return self._test_mouseEvent(at: point, type: type)
    }

    private func _test_mouseEvent(buttonTag: Int, type: NSEvent.EventType) -> NSEvent? {
        guard let button = self.buttons.first(where: { $0.tag == buttonTag }) else { return nil }
        self.updateConstraintsForSubtreeIfNeeded()
        self.layoutSubtreeIfNeeded()
        let point = self.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        return self._test_mouseEvent(at: point, type: type)
    }

    private func _test_mouseEvent(at point: NSPoint, type: NSEvent.EventType) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: type == .leftMouseDown ? 1 : 2,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0)
    }

    @discardableResult
    func _test_simulateMouseDown(buttonTag: Int) -> Bool {
        guard let event = self._test_mouseDownEvent(buttonTag: buttonTag) else { return false }
        return self.handleMenuTrackingMouseDown(event)
    }

    /// Simulates the parent-view event path used while NSMenu owns mouse tracking.
    @discardableResult
    func _test_simulateRuntimeClick(buttonTag: Int) -> Bool {
        guard self._test_simulateMouseDown(buttonTag: buttonTag) else { return false }
        guard let event = self._test_mouseUpEvent(buttonTag: buttonTag) else { return false }
        guard self.handleMenuTrackingMouseUp(event) else { return false }
        return self.selectedSegmentIndex == buttonTag
    }

    @discardableResult
    func _test_simulateRuntimeClickOnQuotaIndicator(buttonTag: Int) -> Bool {
        guard let mouseDown = self._test_quotaIndicatorMouseEvent(buttonTag: buttonTag, type: .leftMouseDown),
              self.handleMenuTrackingMouseDown(mouseDown),
              let mouseUp = self._test_quotaIndicatorMouseEvent(buttonTag: buttonTag, type: .leftMouseUp),
              self.handleMenuTrackingMouseUp(mouseUp)
        else {
            return false
        }
        return self.selectedSegmentIndex == buttonTag
    }

    @discardableResult
    func _test_simulateNativeAction(buttonTag: Int, state: NSControl.StateValue) -> Bool {
        guard let button = self.buttons.first(where: { $0.tag == buttonTag }) else { return false }
        button.state = state
        self.handleSelection(button)
        return true
    }

    func _test_buttonFrames() -> [NSRect] {
        self.buttons.map(\.frame)
    }

    func _test_segmentTitles() -> [String] {
        self.segments.map(\.title)
    }

    func _test_buttonFittingSizes() -> [NSSize] {
        self.buttons.map(\.fittingSize)
    }

    func _test_buttonDesiredWidths() -> [CGFloat] {
        self.buttons.map(Self.maxToggleWidth(for:))
    }

    func _test_buttonContentFrames() -> [NSRect?] {
        self.buttons.map { button in
            button.subviews.first(where: { $0 is NSStackView })?.frame
        }
    }

    func _test_rowCount() -> Int {
        self.rowCount
    }

    func _test_rowHeight() -> CGFloat {
        self.rowHeight
    }

    func _test_setHoveredButtonTag(_ tag: Int?) {
        self.hoveredButtonTag = tag
        self.updateButtonStyles()
    }

    func _test_quotaIndicatorFillRatios() -> [CGFloat] {
        self.buttons.compactMap { button in
            self.quotaIndicators[ObjectIdentifier(button)]?.fillRatio
        }
    }

    func _test_quotaIndicatorVisibility() -> [(trackHidden: Bool, fillHidden: Bool)] {
        self.buttons.compactMap { button in
            self.quotaIndicators[ObjectIdentifier(button)].map { indicator in
                (indicator.track.isHidden, indicator.fill.isHidden)
            }
        }
    }

    func _test_quotaIndicatorFillFrames() -> [NSRect] {
        self.buttons.compactMap { button in
            self.quotaIndicators[ObjectIdentifier(button)]?.fill.frame
        }
    }

    func _test_quotaIndicatorTrackFrames() -> [NSRect] {
        self.buttons.compactMap { button in
            guard let track = self.quotaIndicators[ObjectIdentifier(button)]?.track else { return nil }
            return self.convert(track.bounds, from: track)
        }
    }

    func _test_quotaIndicatorConstraintIdentifiers() -> [ObjectIdentifier] {
        self.buttons.compactMap { button in
            self.quotaIndicators[ObjectIdentifier(button)].map { ObjectIdentifier($0.fillWidthConstraint) }
        }
    }
}
#endif

extension ProviderSwitcherView {
    private func addQuotaIndicator(to view: NSView, selection: ProviderSwitcherSelection, remainingPercent: Double?) {
        guard let remainingPercent else { return }

        let track = SwitcherQuotaStripView()
        track.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(track)

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = Self.quotaIndicatorColor(
            for: selection,
            remainingPercent: remainingPercent).cgColor
        fill.layer?.cornerRadius = Self.quotaIndicatorHeight / 2
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        track.fill = fill

        let ratio = Self.quotaIndicatorRatio(remainingPercent: remainingPercent)
        let fillWidthConstraint = Self.quotaIndicatorFillWidthConstraint(fill: fill, track: track, ratio: ratio)

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Self.quotaIndicatorHorizontalInset),
            track.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Self.quotaIndicatorHorizontalInset),
            track.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -Self.quotaIndicatorBottomInset),
            track.heightAnchor.constraint(equalToConstant: Self.quotaIndicatorHeight),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidthConstraint,
        ])

        self.quotaIndicators[ObjectIdentifier(view)] = QuotaIndicator(
            track: track,
            fill: fill,
            fillWidthConstraint: fillWidthConstraint,
            fillRatio: ratio)
        self.updateQuotaIndicatorVisibility(for: view)
    }

    private func updateQuotaIndicatorVisibility(for view: NSView) {
        guard let indicator = self.quotaIndicators[ObjectIdentifier(view)] else { return }
        // Keep the provider's quota visible while its tab is selected as well. The
        // indicator is the cross-provider status cue, not part of the selection chrome.
        indicator.track.isHidden = false
        let fillHidden = indicator.fillRatio <= 0
        if indicator.fill.isHidden != fillHidden {
            indicator.fill.isHidden = fillHidden
            indicator.track.needsLayout = true
        }
    }

    /// Fill in the provider color; track in `meterTrack`, or white 30 % on the selected (`accentFill`) segment.
    /// Both resolve for `appearance`.
    private func styleQuotaIndicator(for button: NSButton, selected: Bool, appearance: NSAppearance) {
        guard let indicator = self.quotaIndicators[ObjectIdentifier(button)],
              self.segments.indices.contains(button.tag)
        else { return }
        let selection = self.segments[button.tag].selection
        let remaining = indicator.fillRatio * 100
        indicator.fill.layer?.backgroundColor = SwitcherChrome.cgColor(
            { Self.quotaIndicatorColor(for: selection, remainingPercent: remaining) },
            for: appearance)
        indicator.track.trackColor = SwitcherChrome.cgColor(
            { selected ? OpenBarTheme.NSColors.switcherSelectedTrack : OpenBarTheme.NSColors.meterTrack },
            for: appearance)
    }

    fileprivate static func updateQuotaIndicatorFill(
        indicator: inout QuotaIndicator,
        remainingPercent: Double,
        selection: ProviderSwitcherSelection)
    {
        let ratio = Self.quotaIndicatorRatio(remainingPercent: remainingPercent)
        indicator.fillWidthConstraint.isActive = false
        let fillWidthConstraint = Self.quotaIndicatorFillWidthConstraint(
            fill: indicator.fill,
            track: indicator.track,
            ratio: ratio)
        fillWidthConstraint.isActive = true
        indicator.fillWidthConstraint = fillWidthConstraint
        indicator.fillRatio = ratio
        indicator.fill.layer?.backgroundColor = Self.quotaIndicatorColor(
            for: selection,
            remainingPercent: remainingPercent).cgColor
        indicator.fill.layer?.cornerRadius = Self.quotaIndicatorHeight / 2
        indicator.track.isHidden = false
        indicator.fill.isHidden = ratio <= 0
        indicator.track.needsLayout = true
    }

    fileprivate static func quotaIndicatorColor(
        for selection: ProviderSwitcherSelection,
        remainingPercent _: Double) -> NSColor
    {
        switch selection {
        case let .provider(instanceID):
            guard let provider = instanceID.firstPartyProvider else { return NSColor.secondaryLabelColor }
            let color = ProviderAccentPalette.color(for: provider)
            return NSColor(deviceRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        case .overview:
            return NSColor.secondaryLabelColor
        }
    }

    fileprivate static func quotaIndicatorRatio(remainingPercent: Double) -> CGFloat {
        CGFloat(max(0, min(1, remainingPercent / 100)))
    }

    private static func quotaIndicatorFillWidthConstraint(
        fill: NSView,
        track: NSView,
        ratio: CGFloat)
        -> NSLayoutConstraint
    {
        guard ratio > 0 else {
            return fill.widthAnchor.constraint(equalToConstant: 0)
        }
        return fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: ratio)
    }
}

/// The weekly strip inside a segment (spec §9.2): the provider-color fill capsule from the leading edge, a 1-pt
/// gap, then a track capsule to the end; no gap and a full track when the fill is empty, no track when it is full.
/// The fill is a subview sized by its width constraint; the track is one sublayer placed from the fill's frame.
final class SwitcherQuotaStripView: NSView {
    weak var fill: NSView?
    private let trackLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.trackLayer.cornerRadius = ProviderSwitcherView.quotaIndicatorHeight / 2
        self.layer?.addSublayer(self.trackLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var trackColor: CGColor? {
        get { self.trackLayer.backgroundColor }
        set { self.trackLayer.backgroundColor = newValue }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var trackStart = self.bounds.minX
        if let fill, !fill.isHidden, fill.frame.width > 0 {
            trackStart = fill.frame.maxX + OpenBarTheme.Switcher.stripSplitGap
        }
        let trackWidth = self.bounds.maxX - trackStart
        self.trackLayer.isHidden = trackWidth <= 0
        self.trackLayer.frame = CGRect(
            x: trackStart,
            y: self.bounds.minY,
            width: max(0, trackWidth),
            height: self.bounds.height)
    }
}

final class TokenAccountSwitcherView: NSView {
    private let accounts: [ProviderTokenAccount]
    private let hidePersonalInfo: Bool
    private let onSelect: (Int) -> Task<Void, Never>?
    private var selectedIndex: Int
    private var buttons: [NSButton] = []
    private let preferredSize: NSSize
    private let rowSpacing: CGFloat = 4
    private let rowHeight: CGFloat = 26
    /// The button stack doubles as the rail: `cardFill`, radius 9, 2-pt padding around the segments.
    private let rail = NSStackView()
    private static let railInset = OpenBarTheme.Switcher.railInset
    private static let railPadding = OpenBarTheme.Switcher.railPadding

    init(
        accounts: [ProviderTokenAccount],
        selectedIndex: Int,
        width: CGFloat,
        hidePersonalInfo: Bool = false,
        onSelect: @escaping (Int) -> Task<Void, Never>?)
    {
        self.accounts = accounts
        self.hidePersonalInfo = hidePersonalInfo
        self.onSelect = onSelect
        self.selectedIndex = min(max(selectedIndex, 0), max(0, accounts.count - 1))
        let useTwoRows = accounts.count > 3
        let rows = useTwoRows ? 2 : 1
        let height = self.rowHeight * CGFloat(rows) + (useTwoRows ? self.rowSpacing : 0) + Self.railPadding * 2
        self.preferredSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.wantsLayer = true
        self.buildButtons(useTwoRows: useTwoRows)
        self.updateButtonStyles()
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
        self.updateButtonStyles()
    }

    /// Increase Contrast changes the rail border and the resolved layer colors.
    @objc private func displayOptionsDidChange(_: Notification) {
        self.updateButtonStyles()
    }

    private func buildButtons(useTwoRows: Bool) {
        let perRow = useTwoRows ? Int(ceil(Double(self.accounts.count) / 2.0)) : self.accounts.count
        let rows: [[ProviderTokenAccount]] = {
            if !useTwoRows { return [self.accounts] }
            let first = Array(self.accounts.prefix(perRow))
            let second = Array(self.accounts.dropFirst(perRow))
            return [first, second]
        }()

        let stack = self.rail
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = self.rowSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: Self.railPadding,
            left: Self.railPadding,
            bottom: Self.railPadding,
            right: Self.railPadding)
        stack.wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        var globalIndex = 0
        for rowAccounts in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = self.rowSpacing
            row.translatesAutoresizingMaskIntoConstraints = false

            for account in rowAccounts {
                let label = PersonalInfoRedactor.redactAccountLabel(
                    account.displayName,
                    isEnabled: self.hidePersonalInfo,
                    ordinal: .init(globalIndex + 1))
                let button = PaddedToggleButton(
                    title: label,
                    target: self,
                    action: #selector(self.handleSelect))
                button.tag = globalIndex
                button.toolTip = label
                button.setAccessibilityLabel(label)
                button.isBordered = false
                button.setButtonType(.toggle)
                button.controlSize = .small
                button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                button.cell?.lineBreakMode = label.contains("@") ? .byTruncatingMiddle : .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                SwitcherChrome.prepareSegment(button)
                row.addArrangedSubview(button)
                self.buttons.append(button)
                globalIndex += 1
            }

            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -Self.railPadding * 2).isActive = true
        }

        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: Self.railInset),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -Self.railInset),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: self.rowHeight * CGFloat(rows.count) +
                (useTwoRows ? self.rowSpacing : 0) + Self.railPadding * 2),
        ])
    }

    private func updateButtonStyles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let appearance = self.effectiveAppearance
        SwitcherChrome.styleRail(self.rail.layer, appearance: appearance)
        for (index, button) in self.buttons.enumerated() {
            let selected = index == self.selectedIndex
            button.state = selected ? .on : .off
            SwitcherChrome.styleSegment(button, selected: selected, appearance: appearance)
        }
    }

    @objc private func handleSelect(_ sender: NSButton) {
        _ = self.select(index: sender.tag)
    }

    @discardableResult
    private func select(index: Int) -> Task<Void, Never>? {
        guard index >= 0, index < self.accounts.count else { return nil }
        self.selectedIndex = index
        self.updateButtonStyles()
        return self.onSelect(index)
    }

    #if DEBUG
    func _test_select(index: Int) -> Task<Void, Never>? {
        guard let button = self.buttons.first(where: { $0.tag == index }) else { return nil }
        return self.select(index: button.tag)
    }

    func _test_buttonTitles() -> [String] {
        self.buttons.map(\.title)
    }
    #endif
}
