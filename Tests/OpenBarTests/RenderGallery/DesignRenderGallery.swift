import AppKit
import OpenBarCore
import SwiftUI
import Testing
@testable import OpenBar

/// Design render gallery: renders real OpenBar views with synthetic data to PNGs, then exits.
///
/// Inert by default. It runs only when `OPENBAR_RENDER_GALLERY_DIR` is set and the scrubbed test
/// environment suppresses Keychain access, so it never shows a Keychain prompt, never touches the
/// network, and never creates a status item. Use `Scripts/render_gallery.sh`; see docs/design/README.md.
///
/// Each surface has its own section file (`DesignRenderGallery+<Surface>.swift`) so parallel
/// implementers can extend their own section without editing shared code.
@MainActor
@Suite(.serialized)
struct DesignRenderGallery {
    @Test
    func `renders the design gallery`() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OPENBAR_RENDER_GALLERY_DIR"], !path.isEmpty else { return }
        guard environment["OPENBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1",
              environment["OPENBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1"
        else {
            Issue.record("Run the gallery through Scripts/render_gallery.sh so Keychain access stays suppressed.")
            return
        }
        let only = environment["OPENBAR_RENDER_GALLERY_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let gallery = try GalleryWriter(root: URL(fileURLWithPath: path, isDirectory: true))
        try OpenBarLocalizationOverride.$appLanguage.withValue("en") {
            let sections: [(String, (GalleryWriter) throws -> Void)] = [
                ("tokens", GalleryTokensSection.render),
                ("menubar", GalleryMenuBarSection.render),
                ("menu", GalleryMenuSection.render),
                ("settings", GallerySettingsSection.render),
                ("widgets", GalleryWidgetsSection.render),
                ("charts", GalleryChartsSection.render),
            ]
            for (name, render) in sections where only?.contains(name) ?? true {
                try render(gallery)
            }
        }
        try gallery.writeIndex()
        print("[render-gallery] wrote \(gallery.items.count) items to \(gallery.root.path)/index.html")
    }
}

// MARK: - Writer

struct GalleryItem {
    let section: String
    let title: String
    let note: String?
    let files: [(label: String, path: String)]
}

@MainActor
final class GalleryWriter {
    let root: URL
    private(set) var items: [GalleryItem] = []

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes one PNG and returns its path relative to the gallery root.
    func write(_ png: Data, section: String, name: String) throws -> String {
        let directory = self.root.appendingPathComponent(section, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let relative = "\(section)/\(name).png"
        try png.write(to: self.root.appendingPathComponent(relative), options: .atomic)
        return relative
    }

    /// Renders `make` once per appearance and records one gallery item with every variant.
    func add(
        section: String,
        title: String,
        name: String,
        note: String? = nil,
        appearances: [GalleryAppearance] = GalleryAppearance.allCases,
        make: (GalleryAppearance) throws -> Data) throws
    {
        var files: [(String, String)] = []
        for appearance in appearances {
            let png = try make(appearance)
            try files.append((
                appearance.label,
                self.write(png, section: section, name: "\(name)-\(appearance.suffix)")))
        }
        self.items.append(GalleryItem(section: section, title: title, note: note, files: files))
    }

    func writeIndex() throws {
        var html = """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>OpenBar render gallery</title>
        <style>
        body{margin:0;padding:32px;font:13px -apple-system,sans-serif;background:#f5f5f7;color:#1d1d1f}
        h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:32px 0 12px;text-transform:capitalize}
        p.meta{color:#6e6e73;margin:0 0 16px}.item{background:#fff;border-radius:12px;padding:16px;margin:0 0 16px}
        .item h3{font-size:13px;margin:0 0 4px}.item p{color:#6e6e73;margin:0 0 10px}
        .row{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-start}figure{margin:0}
        figcaption{color:#6e6e73;font-size:11px;margin-top:4px}img{max-width:100%;height:auto;display:block}
        </style></head><body><h1>OpenBar render gallery</h1>
        <p class="meta">Real views, synthetic data. Images are 2x; open one to see actual pixels.</p>
        """
        var currentSection = ""
        for item in self.items {
            if item.section != currentSection {
                currentSection = item.section
                html += "<h2>\(Self.escape(currentSection))</h2>"
            }
            html += "<div class=\"item\"><h3>\(Self.escape(item.title))</h3>"
            if let note = item.note {
                html += "<p>\(Self.escape(note))</p>"
            }
            html += "<div class=\"row\">"
            for file in item.files {
                html += "<figure><a href=\"\(file.path)\"><img src=\"\(file.path)\" style=\"zoom:0.5\"></a>"
                html += "<figcaption>\(Self.escape(file.label))</figcaption></figure>"
            }
            html += "</div></div>"
        }
        html += "</body></html>\n"
        try Data(html.utf8).write(to: self.root.appendingPathComponent("index.html"), options: .atomic)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Appearance

/// Light and dark. Increase Contrast is a system appearance that an offscreen window cannot adopt,
/// so high-contrast token values are rendered directly by the tokens section instead.
enum GalleryAppearance: CaseIterable {
    case light
    case dark

    var name: NSAppearance.Name {
        self == .dark ? .darkAqua : .aqua
    }

    var appearance: NSAppearance {
        NSAppearance(named: self.name) ?? NSAppearance(named: .aqua)!
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var isDark: Bool {
        self == .dark
    }

    var suffix: String {
        self == .dark ? "dark" : "light"
    }

    var label: String {
        self == .dark ? "Dark" : "Light"
    }

    /// Opaque stand-in for the macOS 26 menu glass over a neutral wallpaper.
    var menuBackdrop: NSColor {
        self.isDark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    }

    /// Stand-in for the menu bar strip behind the status item.
    var menuBarBackdrop: NSColor {
        self.isDark ? NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)
    }

    /// Stand-in for the desktop behind widgets.
    var desktopBackdrop: NSColor {
        self.isDark ? NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
            : NSColor(srgbRed: 0.86, green: 0.87, blue: 0.89, alpha: 1)
    }
}

// MARK: - Capture

/// Captures views through an offscreen, never-ordered-front window so AppKit-backed SwiftUI
/// controls (Form, Toggle, Picker) render the same way they do in the app.
@MainActor
enum GalleryCapture {
    static func hosted(
        _ view: some View,
        appearance: GalleryAppearance,
        size: CGSize? = nil,
        backdrop: NSColor? = nil,
        padding: CGFloat = 0,
        settle: TimeInterval = 0.15) throws -> Data
    {
        let hosting = NSHostingView(rootView: view
            .environment(\.colorScheme, appearance.colorScheme)
            .environment(\.locale, Locale(identifier: "en_US")))
        hosting.appearance = appearance.appearance
        let fitted = size ?? hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: fitted)
        return try self.appKit(
            hosting,
            appearance: appearance,
            size: fitted,
            backdrop: backdrop,
            padding: padding,
            settle: settle)
    }

    static func appKit(
        _ view: NSView,
        appearance: GalleryAppearance,
        size: CGSize? = nil,
        backdrop: NSColor? = nil,
        padding: CGFloat = 0,
        settle: TimeInterval = 0.15) throws -> Data
    {
        let contentSize = size ?? view.fittingSize
        let outer = CGSize(width: contentSize.width + padding * 2, height: contentSize.height + padding * 2)
        let container = GalleryBackdropView(frame: CGRect(origin: .zero, size: outer))
        container.fill = backdrop
        container.appearance = appearance.appearance
        view.frame = CGRect(x: padding, y: padding, width: contentSize.width, height: contentSize.height)
        container.addSubview(view)
        let window = GalleryOffscreenWindow(
            contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance.appearance
        window.contentView = container
        defer {
            window.contentView = nil
            window.close()
        }
        return try self.capture(container, window: window, appearance: appearance, backdrop: nil, settle: settle)
    }

    /// Draws `view` into a 2x sRGB bitmap. The gallery window reports a 2x backing scale and an sRGB
    /// color space; with the defaults (1x, device color) `cacheDisplay` visibly desaturates the palette.
    private static func capture(
        _ view: NSView,
        window: NSWindow,
        appearance: GalleryAppearance,
        backdrop: NSColor?,
        settle: TimeInterval = 0.15) throws -> Data
    {
        window.colorSpace = .sRGB
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(settle)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05)))
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        let bounds = view.bounds
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw GalleryError.bitmap
        }
        if let backdrop {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.appearance.performAsCurrentDrawingAppearance {
                backdrop.setFill()
                NSRect(origin: .zero, size: bounds.size).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryError.encoding
        }
        return png
    }
}

enum GalleryError: Error {
    case bitmap
    case encoding
}

/// Offscreen gallery window: stays at its origin instead of being pulled onscreen, never becomes key,
/// and reports a 2x backing scale so layer contents render at Retina resolution without a screen.
final class GalleryOffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var backingScaleFactor: CGFloat {
        2
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Opaque backdrop that resolves dynamic colors in its own appearance at draw time.
final class GalleryBackdropView: NSView {
    var fill: NSColor?

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let fill else { return }
        fill.setFill()
        dirtyRect.fill()
    }
}

// MARK: - Tokens section

/// Swatches for every color token, resolved through `OpenBarTheme` in each appearance.
@MainActor
enum GalleryTokensSection {
    static func render(_ gallery: GalleryWriter) throws {
        try gallery.add(
            section: "tokens",
            title: "Color tokens",
            name: "colors",
            note: "Resolved through OpenBarTheme for the drawing appearance.")
        { appearance in
            try GalleryCapture.hosted(
                TokenSwatches(),
                appearance: appearance,
                backdrop: appearance.menuBackdrop,
                padding: 16)
        }
        try gallery.add(
            section: "tokens",
            title: "Color tokens · Increase Contrast values",
            name: "colors-hc",
            note: "Raw high-contrast token values. An offscreen window cannot adopt the system's "
                + "Increase Contrast appearance, so these swatches read the values directly.")
        { appearance in
            try GalleryCapture.hosted(
                HighContrastSwatches(isDark: appearance.isDark),
                appearance: appearance,
                backdrop: appearance.isDark ? .black : .white,
                padding: 16)
        }
        try gallery.add(section: "tokens", title: "Type scale", name: "type") { appearance in
            try GalleryCapture.hosted(
                TypeSpecimen(),
                appearance: appearance,
                backdrop: appearance.menuBackdrop,
                padding: 16)
        }
    }

    private struct TokenSwatches: View {
        var body: some View {
            let swatches: [(String, Color)] = [
                ("accent", OpenBarTheme.Colors.accent),
                ("accentFill", OpenBarTheme.Colors.accentFill),
                ("ok", OpenBarTheme.Colors.ok),
                ("warning", OpenBarTheme.Colors.warning),
                ("critical", OpenBarTheme.Colors.critical),
                ("stale", OpenBarTheme.Colors.stale),
                ("cardFill", OpenBarTheme.Colors.cardFill),
                ("meterTrack", OpenBarTheme.Colors.meterTrack),
            ]
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(swatches, id: \.0) { name, color in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: OpenBarRadius.chip, style: .continuous)
                                .fill(color)
                                .frame(width: 56, height: 36)
                            Text(name).font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 6) {
                    ForEach(0..<OpenBarPalette.categorical.count, id: \.self) { index in
                        if let color = OpenBarTheme.Colors.series(index) {
                            RoundedRectangle(cornerRadius: OpenBarRadius.chartBar).fill(color).frame(
                                width: 28,
                                height: 28)
                        }
                    }
                    Text("chart series 1–6").font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    ForEach(OpenBarQuotaTone.allCases, id: \.self) { tone in
                        HStack(spacing: 4) {
                            if let symbol = tone.symbolName {
                                Image(systemName: symbol).foregroundStyle(OpenBarTheme.Colors.tone(tone) ?? .primary)
                            }
                            Text(tone.rawValue).font(OpenBarTheme.Fonts.meta)
                        }
                    }
                }
                Text("Link-style accent text").foregroundStyle(OpenBarTheme.Colors.accent)
                Text("Selected").font(OpenBarTheme.Fonts.laneTitle).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: OpenBarRadius.control, style: .continuous)
                        .fill(OpenBarTheme.Colors.accentFill))
            }
            .fixedSize()
        }
    }

    private struct HighContrastSwatches: View {
        let isDark: Bool

        var body: some View {
            let tokens: [(String, OpenBarDynamicColor)] = [
                ("accent", OpenBarPalette.accent), ("accentFill", OpenBarPalette.accentFill),
                ("ok", OpenBarPalette.ok), ("warning", OpenBarPalette.warning),
                ("critical", OpenBarPalette.critical), ("stale", OpenBarPalette.stale),
                ("cardFill", OpenBarPalette.cardFill), ("meterTrack", OpenBarPalette.meterTrack),
            ]
            HStack(spacing: 10) {
                ForEach(tokens, id: \.0) { name, token in
                    let value = token.value(isDark: self.isDark, increasedContrast: true)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: OpenBarRadius.chip, style: .continuous)
                            .fill(Color(nsColor: value.nsColor))
                            .frame(width: 56, height: 36)
                        Text(name).font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary)
                        Text(value.hexString).font(OpenBarTheme.Fonts.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .fixedSize()
        }
    }

    private struct TypeSpecimen: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(OpenBarTypeRole.allCases, id: \.self) { role in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(role.rawValue).font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(Self.sample(role)).font(OpenBarTheme.Fonts.font(role))
                    }
                }
            }
            .fixedSize()
        }

        private static func sample(_ role: OpenBarTypeRole) -> String {
            switch role {
            case .title: "Usage & Spend"
            case .cardTitle: "Claude"
            case .laneTitle: "Session"
            case .laneValue: "62% left"
            case .meta: "Resets in 2h 14m · Updated 1m ago"
            case .caption: "Mon Tue Wed Thu Fri"
            case .hero: "62%"
            case .code: "~/.config/openbar/config.json"
            }
        }
    }
}
