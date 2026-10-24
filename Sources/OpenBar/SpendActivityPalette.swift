import SwiftUI

struct SpendActivityPalette {
    let colorScheme: ColorScheme
    var contrast: ColorSchemeContrast = .standard

    func color(forLevel level: Int) -> Color {
        let colors: [UInt32] = switch (self.colorScheme, self.contrast) {
        case (.dark, .increased): [0x484C52, 0x469960, 0x58B872, 0x7DDF96, 0xADF0BC]
        case (.dark, _): [0x30353A, 0x347D4E, 0x43985D, 0x58B872, 0x7DDF96]
        case (_, .increased): [0xE1E5E9, 0x519C66, 0x34804C, 0x24693B, 0x17552E]
        default: [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
        }
        return Self.rgb(colors[min(max(level, 0), 4)])
    }

    var unavailableFill: Color {
        Self.rgb(self.colorScheme == .dark ? 0x282D34 : 0xE1E6EC)
    }

    var unavailableStroke: Color {
        Self.rgb(self.colorScheme == .dark ? 0x8A959F : 0x6D7888)
    }

    /// Fills each cell with its level color. Missing history keeps an outline and a slash, which preserve
    /// the distinction from a confirmed zero without relying on hue. The legend and both activity grids
    /// share this drawing.
    ///
    /// One plain shape per color instead of a `Canvas`: Canvas renders through RenderBox's Metal backend
    /// on macOS 26+, which commits about 100 MB of GPU memory the first time a window draws one.
    func cells(_ cells: [SpendActivityCell], corner: CGFloat) -> some View {
        var fills: [Int?: Path] = [:]
        var missingOutline = Path()
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        for cell in cells {
            fills[cell.level, default: Path()].addPath(shape.path(in: cell.rect))
            guard cell.level == nil else { continue }
            missingOutline.addPath(shape.path(in: cell.rect.insetBy(dx: 0.5, dy: 0.5)))
            let inset = min(cell.rect.width * 0.25, 2)
            missingOutline.move(to: CGPoint(x: cell.rect.minX + inset, y: cell.rect.maxY - inset))
            missingOutline.addLine(to: CGPoint(x: cell.rect.maxX - inset, y: cell.rect.minY + inset))
        }
        let layers = fills.map { level, path in
            (color: level.map { self.color(forLevel: $0) } ?? self.unavailableFill, path: path, order: level ?? -1)
        }
        .sorted { $0.order < $1.order }
        return ZStack(alignment: .topLeading) {
            ForEach(layers, id: \.order) { layer in
                layer.path.fill(layer.color)
            }
            missingOutline.stroke(self.unavailableStroke, lineWidth: 0.75)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct SpendActivityCell {
    let rect: CGRect
    /// Nil marks a day without recorded history.
    let level: Int?
}

struct SpendActivitySwatch: View {
    let palette: SpendActivityPalette
    var level: Int?

    var body: some View {
        let cell = SpendActivityCell(rect: CGRect(x: 0, y: 0, width: 10, height: 10), level: self.level)
        self.palette.cells([cell], corner: 2)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
