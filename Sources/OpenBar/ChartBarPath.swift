import SwiftUI

/// Bar outlines with the corner rounding Swift Charts used on macOS 26: bars that grow from zero round
/// their top corners, and floating ranges round every corner.
enum ChartBarPath {
    static let cornerRadius: CGFloat = 2

    static func path(_ rects: [CGRect], roundsBottom: Bool) -> Path {
        var path = Path()
        for rect in rects where rect.width > 0 && rect.height > 0 {
            let radius = min(Self.cornerRadius, rect.width / 2, roundsBottom ? rect.height / 2 : rect.height)
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
