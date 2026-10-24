import SwiftUI

enum ChartAxisLabelLayout {
    /// Reserve room for full caption dates at both ends without shifting labels away from their bars.
    static let dateLabelEdgePadding: CGFloat = 32
    /// Space below the plot for one line of caption dates, matching what Swift Charts reserved.
    static let xAxisHeight: CGFloat = 17
    /// Gap between the plot's bottom edge and the top of an x-axis label.
    static let xAxisLabelGap: CGFloat = 4

    @MainActor
    static func dateLabel(_ text: Text) -> some View {
        text
            .font(.caption2)
            // Keep the full date even when the label hangs past the plot edge.
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
    }

    /// Hangs a date label below the plot with its top center at `x`, as a top-anchored axis label.
    @MainActor
    static func xAxisDateLabel(_ text: Text, x: CGFloat, plotBottom: CGFloat) -> some View {
        self.dateLabel(text)
            .frame(width: 0, height: 0, alignment: .top)
            .position(x: x, y: plotBottom + self.xAxisLabelGap)
    }
}
