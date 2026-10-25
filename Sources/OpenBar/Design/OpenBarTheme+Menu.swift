import AppKit
import OpenBarCore
import SwiftUI

// Menu-only design tokens and shared menu chrome (Menu agent, spec §9.2). The lead folds the
// token values below into OpenBarDesignTokens.swift / OpenBarTheme.swift.

/// Menu geometry that the core token file does not define yet.
enum OpenBarMenuStyle {
    /// Horizontal inset from the menu row edge to a card, and the card's own padding.
    static let cardInset = CGFloat(OpenBarMenuMetrics.cardInset)
    static let cardPaddingHorizontal = CGFloat(OpenBarMenuMetrics.cardPaddingHorizontal)
    static let cardPaddingVertical = CGFloat(OpenBarMenuMetrics.cardPaddingVertical)
    /// Card content starts this far from the menu row edge (8 inset + 12 padding).
    static let cardContentInset = cardInset + cardPaddingHorizontal
    /// Gap between two cards that share one hosting view.
    static let cardGap = CGFloat(OpenBarMenuMetrics.cardGap)
    /// Header to the first quota lane.
    static let headerToLanes = CGFloat(OpenBarSpacing.section)
    static let laneSpacing = CGFloat(OpenBarMenuMetrics.laneSpacing)
    static let laneInnerSpacing = CGFloat(OpenBarMenuMetrics.laneInnerSpacing)
    static let logoSize = CGFloat(OpenBarMenuMetrics.logoSize)
    static let logoTitleSpacing = CGFloat(OpenBarSpacing.compact)

    /// Status symbols in lanes and pace lines.
    static let toneSymbolSize: CGFloat = 10
    /// Submenu chevron in a card header.
    static let chevronSize: CGFloat = 9

    /// Native-style row selection plate (agent sessions, compact account rows). Matches
    /// `PersistentRefreshRowMetrics`.
    static let rowPlateHorizontalInset: CGFloat = 5
    static let rowPlateRadius = CGFloat(OpenBarRadius.control)

    // Meter (spec §9.2 "Meter").
    static let meterHeight = CGFloat(OpenBarMenuMetrics.meterHeight)
    static let meterSplitGap = CGFloat(OpenBarMenuMetrics.meterSplitGap)
    /// Quota-warning markers and subtle workday ticks are 1-pt gaps cut into the meter.
    static let meterMarkerGap: CGFloat = 1
    /// High-contrast workday ticks cut a wider gap.
    static let meterHighContrastMarkerGap: CGFloat = 2
    /// Pace tick: a rounded 2 × 10 pt bar with a 1-pt cleared halo on each side.
    static let paceTickWidth: CGFloat = 2
    static let paceTickHeight: CGFloat = 10
    static let paceTickHalo: CGFloat = 1
    /// Track opacity on a highlighted (accent) card.
    static let highlightedTrackOpacity = 0.22
}

extension OpenBarTheme.Fonts {
    /// Lane value ("62% left") one step above `laneValue`, so the figure clearly outranks the
    /// 12-pt lane title (design council, "numbers first"). 15 pt semibold, tabular (`.title3`).
    static let laneValueEmphasis = Font.title3.weight(.semibold).monospacedDigit()
    /// Pace and status lines that carry a warning: same size as `meta`, one weight step up.
    static let metaEmphasis = Font.subheadline.weight(.medium).monospacedDigit()
}

// MARK: - Tones

/// Pace forecast tone for a lane's detail line.
enum MenuPaceTone: Equatable {
    /// The lane lasts until its reset.
    case lastsToReset
    /// The lane runs out before its reset.
    case runsOut

    var symbolName: String {
        switch self {
        case .lastsToReset: "checkmark.circle.fill"
        case .runsOut: OpenBarQuotaTone.warning.symbolName ?? "exclamationmark.triangle.fill"
        }
    }

    func color(highlighted: Bool) -> Color {
        if highlighted { return MenuHighlightStyle.selectionText }
        return switch self {
        case .lastsToReset: OpenBarTheme.Colors.ok
        case .runsOut: OpenBarTheme.Colors.warning
        }
    }
}

extension OpenBarQuotaTone {
    /// Warning and critical are the only tones a lane value shows; stale data keeps the
    /// card-level last-known notice instead.
    var marksLaneValue: Bool {
        self == .warning || self == .critical
    }

    /// Text and symbol color for this tone inside a menu row.
    func menuColor(highlighted: Bool) -> Color? {
        guard self.marksLaneValue else { return nil }
        if highlighted { return MenuHighlightStyle.selectionText }
        return OpenBarTheme.Colors.tone(self)
    }
}

/// A filled status symbol. Hidden from VoiceOver because the words beside it carry the state.
struct MenuToneSymbol: View {
    let systemName: String
    let color: Color
    var size: CGFloat = OpenBarMenuStyle.toneSymbolSize

    var body: some View {
        Image(systemName: self.systemName)
            .font(.system(size: self.size, weight: .semibold))
            .foregroundStyle(self.color)
            .accessibilityHidden(true)
    }
}

// MARK: - Card chrome

extension EnvironmentValues {
    /// True when the hosting menu row owns a submenu; card headers then show their chevron.
    @Entry var menuCardShowsSubmenuChevron: Bool = false
    /// Forces the Increase Contrast card treatment. Render-gallery fixtures only; the app reads
    /// `colorSchemeContrast`.
    @Entry var menuCardIncreasedContrastOverride: Bool?
}

/// How a hosted menu row draws its selection.
enum MenuRowChrome: Equatable {
    /// The row's content draws soft cards (`menuCardChrome()`); a highlighted card fills with
    /// the accent.
    case card
    /// A native-looking text row: no card, an accent plate when highlighted.
    case row
}

/// Soft layered card (spec §2.3, §5): one flat fill inset from the menu edge, no material,
/// no shadow. A highlighted row turns the whole card into the accent fill. Increase Contrast
/// adds the `cardStroke` hairline.
struct MenuCardChromeModifier: ViewModifier {
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.menuCardIncreasedContrastOverride) private var increasedContrastOverride

    /// Reduce Transparency needs no extra step here: NSMenu turns its own background opaque, and the
    /// card's flat fill then sits on an opaque parent.
    private var increasedContrast: Bool {
        self.increasedContrastOverride ?? (self.contrast == .increased)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OpenBarMenuStyle.cardPaddingHorizontal)
            .padding(.vertical, OpenBarMenuStyle.cardPaddingVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = OpenBarTheme.cardShape()
                if self.isHighlighted {
                    shape.fill(OpenBarTheme.Colors.accentFill)
                } else if self.increasedContrast {
                    shape.fill(OpenBarTheme.Colors.cardFill)
                        .overlay { shape.strokeBorder(OpenBarTheme.Colors.cardStroke, lineWidth: 1) }
                } else {
                    shape.fill(OpenBarTheme.Colors.cardFill)
                }
            }
            // A card is a container: its lanes and controls (Copy, plan button) stay separate elements.
            .accessibilityElement(children: .contain)
            .padding(.horizontal, OpenBarMenuStyle.cardInset)
    }
}

extension View {
    func menuCardChrome() -> some View {
        self.modifier(MenuCardChromeModifier())
    }
}

/// Submenu chevron for a card's title row. Renders only when the hosting row owns a submenu.
struct MenuCardSubmenuChevron: View {
    @Environment(\.menuCardShowsSubmenuChevron) private var showsChevron
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        if self.showsChevron {
            Image(systemName: "chevron.right")
                .font(.system(size: OpenBarMenuStyle.chevronSize, weight: .semibold))
                .foregroundStyle(MenuHighlightStyle.tertiary(self.isHighlighted))
                .accessibilityHidden(true)
        }
    }
}
