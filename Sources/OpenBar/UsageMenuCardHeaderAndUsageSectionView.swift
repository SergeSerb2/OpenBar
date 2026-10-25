import SwiftUI

/// The provider card of a sectioned menu (one hosting view that owns the usage submenu): header and
/// quota lanes in a single soft card.
struct UsageMenuCardHeaderAndUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let layoutModel: UsageMenuCardView.Model
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        UsageMenuCardHeaderAndUsageCard(model: self.model, layoutModel: self.layoutModel)
            .frame(width: self.width, alignment: .leading)
    }
}
