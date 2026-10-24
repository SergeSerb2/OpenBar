import SwiftUI

/// Batched bar outlines (docs/design/README.md §8): bars that grow from the baseline round only their
/// data end and keep a square baseline end; floating ranges round every corner.
enum ChartBarPath {
    static let cornerRadius: CGFloat = OpenBarTheme.Chart.barCornerRadius

    static func path(_ rects: [CGRect], roundsBottom: Bool, cornerRadius: CGFloat = Self.cornerRadius) -> Path {
        var path = Path()
        for rect in rects where rect.width > 0 && rect.height > 0 {
            let radius = min(cornerRadius, rect.width / 2, roundsBottom ? rect.height / 2 : rect.height)
            path.addRoundedRect(
                in: rect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: radius,
                    bottomLeading: roundsBottom ? radius : 0,
                    bottomTrailing: roundsBottom ? radius : 0,
                    topTrailing: radius))
        }
        return path
    }
}
