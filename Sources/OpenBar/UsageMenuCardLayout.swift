import CoreGraphics

/// Card geometry for hosted menu rows (spec §4, §9.2). Card content sits 8 pt (card inset) + 12 pt
/// (card padding) from the menu row edge.
enum UsageMenuCardLayout {
    /// Card content inset from the row edge; text rows without a card use it too, so they align.
    static let horizontalPadding = OpenBarMenuStyle.cardContentInset
    static let headerOnlyVerticalPadding = OpenBarMenuStyle.cardPaddingVertical
    static let headerContentSpacing = OpenBarMenuStyle.headerToLanes
    static let sectionTopPadding = OpenBarMenuStyle.cardPaddingVertical
    static let usageSectionTopPadding = OpenBarMenuStyle.headerToLanes
    static let sectionBottomPadding = OpenBarMenuStyle.cardPaddingVertical
    /// Name row to account row.
    static let headerLineSpacing: CGFloat = 2
    static let headerColumnSpacing: CGFloat = 8

    /// Header to the first quota lane. Overview rows and full cards share it, so both align.
    static var postHeaderDividerContentSpacing: CGFloat {
        self.headerContentSpacing
    }
}
