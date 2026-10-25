import AppKit
import OpenBarCore
import SwiftUI

/// Chart marks, axes, and grid from docs/design/README.md §8, shared by the submenu, dashboard, and
/// window charts. Everything here draws with plain shapes; nothing animates or allocates a layer of its own.
extension OpenBarTheme {
    enum Chart {
        /// Rounded data end of a bar. The baseline end stays square.
        static let barCornerRadius = CGFloat(OpenBarRadius.chartBar)
        /// Surface gap between adjacent bars and between stacked segments, where the width allows it.
        static let markGap: CGFloat = 2
        /// Narrowest a bar gets while it keeps the gap. A bar never vanishes.
        static let minimumBarWidth: CGFloat = 1
        static let lineWidth: CGFloat = 2
        static let baselineWidth: CGFloat = 1
        static let gridLineWidth: CGFloat = 0.5
        static let maximumGridLines = 3
        /// Opacity of the marks that are not hovered while one is.
        static let dimmedOpacity = 0.55
        /// Height of the track-colored stub that stands in for a day without a value.
        static let missingStubHeight: CGFloat = 2
        /// Reset, ideal, and limit rules.
        static let ruleStyle = StrokeStyle(lineWidth: 1, dash: [3, 3])

        static let baselineColor = Color(nsColor: .tertiaryLabelColor)
        /// Grid lines recede to half strength; Increase Contrast keeps them at full tertiary strength.
        static func gridColor(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? self.baselineColor : self.baselineColor.opacity(0.5)
        }

        static let axisLabelColor = Color(nsColor: .tertiaryLabelColor)
        static let ruleColor = Color(nsColor: .secondaryLabelColor)
        /// The folded "Other" series, and any series past the last palette slot.
        static let otherSeriesColor = Color(nsColor: .tertiaryLabelColor)
        static let axisFont = OpenBarTheme.Fonts.caption
        /// The axis font for text measurement in AppKit units.
        static var axisNSFont: NSFont {
            OpenBarTheme.Fonts.nsFont(.caption)
        }

        /// Activity heatmap ramp, levels 0–4 (docs/design/README.md §9.4): one Iris hue, interpolated in
        /// OKLCH from `#E4E2FB` to `#2F27A8` (light) and `#2A2850` to `#BDB9FF` (dark). Level 0 is a confirmed
        /// zero and stays quiet. In dark mode level 1 starts at a mid Iris so every active day keeps at
        /// least 3:1 against the window background; Increase Contrast widens both ends.
        static let activityRamp: [OpenBarDynamicColor] = [
            Self.rampStep(light: 0xE4E2FB, dark: 0x2A2850, lightHighContrast: 0xD9D6F8, darkHighContrast: 0x3A3768),
            Self.rampStep(light: 0xB4B1F5, dark: 0x6A62F2, lightHighContrast: 0xA7A4EE, darkHighContrast: 0x7F78F8),
            Self.rampStep(light: 0x8483E5, dark: 0x8580F7, lightHighContrast: 0x7674D9, darkHighContrast: 0x9C95FF),
            Self.rampStep(light: 0x5656CA, dark: 0xA19DFB, lightHighContrast: 0x4847B6, darkHighContrast: 0xBAB5FF),
            Self.rampStep(light: 0x2F27A8, dark: 0xBDB9FF, lightHighContrast: 0x221A8A, darkHighContrast: 0xD9D6FF),
        ]

        private static func rampStep(
            light: UInt32,
            dark: UInt32,
            lightHighContrast: UInt32,
            darkHighContrast: UInt32) -> OpenBarDynamicColor
        {
            OpenBarDynamicColor(
                light: .init(hex: light),
                dark: .init(hex: dark),
                lightHighContrast: .init(hex: lightHighContrast),
                darkHighContrast: .init(hex: darkHighContrast))
        }

        /// Categorical color for a non-provider series, in the fixed §2.5 order; never cycles.
        static func seriesColor(_ index: Int) -> Color {
            OpenBarTheme.Colors.series(index) ?? self.otherSeriesColor
        }

        /// Width that leaves `markGap` before the next slot when the slot is wide enough.
        static func barWidth(_ width: CGFloat, pitch: CGFloat) -> CGFloat {
            min(width, max(self.minimumBarWidth, pitch - self.markGap))
        }

        /// The gap cut from the baseline side of a stacked segment, keeping at least 1 pt of it visible.
        static func stackGap(segmentHeight: CGFloat) -> CGFloat {
            min(self.markGap, max(0, segmentHeight - 1))
        }

        /// At most `maximumGridLines` nonzero tick values: the top value and evenly spaced ones below it.
        static func gridValues(_ ticks: [Double]) -> [Double] {
            let values = ticks.filter { $0 > 0 }.sorted()
            guard values.count > self.maximumGridLines else { return values }
            let step = Int((Double(values.count) / Double(self.maximumGridLines)).rounded(.up))
            return Array(stride(from: values.count - 1, through: 0, by: -step).map { values[$0] }.reversed())
        }

        /// Horizontal grid lines at `values`, across `width`.
        static func gridPath(values: [Double], width: CGFloat, y: (Double) -> CGFloat) -> Path {
            var path = Path()
            for value in values {
                let lineY = y(value)
                path.move(to: CGPoint(x: 0, y: lineY))
                path.addLine(to: CGPoint(x: width, y: lineY))
            }
            return path
        }

        /// The 1-pt baseline drawn just below a plot whose bottom edge is `bottom`.
        static func baselinePath(width: CGFloat, bottom: CGFloat) -> Path {
            var path = Path()
            let lineY = bottom + self.baselineWidth / 2
            path.move(to: CGPoint(x: 0, y: lineY))
            path.addLine(to: CGPoint(x: width, y: lineY))
            return path
        }
    }
}

extension View {
    /// Opaque chart tooltip: `cardFill` over the window background with a hairline. No material, no shadow.
    func chartTooltipBackground(cornerRadius: CGFloat = OpenBarRadius.control) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape.fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    shape.fill(OpenBarTheme.Colors.cardFill)
                }
                .overlay {
                    shape.strokeBorder(OpenBarTheme.Colors.cardStroke, lineWidth: 1)
                }
        }
    }
}
