import AppKit
import OpenBarCore
import SwiftUI

/// Settings window metrics (docs/design/README.md §9.4). Owned by the Settings surface until the lead folds
/// them into the token file.
enum OpenBarSettingsMetrics {
    /// Height of the unified titlebar band. The detail header strip fills it and the window's empty toolbar
    /// gives the traffic lights the same vertical center.
    static let titlebarBandHeight: CGFloat = 52
    /// Grouped-form content is at most 600 pt wide; the grouped form adds 20 pt of padding on each side.
    static let formMaxWidth: CGFloat = 640
    static let searchFieldHeight: CGFloat = 28
    static let sidebarRowSymbolSize: CGFloat = 14
    static let sidebarRowSymbolFrame: CGFloat = 20
    static let sidebarLogoSize: CGFloat = 16
    static let sidebarStatusMarkSize: CGFloat = 7
    static let historyButtonWidth: CGFloat = 32
    static let historyButtonHeight: CGFloat = 28
    static let providerHeaderTileSize: CGFloat = 40
    static let providerHeaderLogoSize: CGFloat = 24
    static let aboutIconSize: CGFloat = 96
    /// Usage & Spend panels: card fill, radius 10, padding 16.
    static let panelPadding: CGFloat = 16
}

extension View {
    /// Shared look for every grouped-form pane: native grouped rows on the window background and switches.
    /// The accent comes from the `.tint` at the Settings root.
    func settingsPaneForm() -> some View {
        self
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .scrollContentBackground(.hidden)
    }

    /// Section title for the first section after a row-less hero section (provider header, About). The grouped
    /// form would otherwise draw that title smaller and secondary, tight under the hero.
    func settingsHeroFollowingHeader() -> some View {
        self
            .font(OpenBarTheme.Fonts.cardTitle)
            .foregroundStyle(.primary)
            .padding(.top, OpenBarSpacing.group)
    }

    /// Flat card for Settings panels (Usage & Spend, inspectors): one fill, no material, no shadow. A hairline is
    /// added only with Increase Contrast.
    func settingsPanelCard(padding: CGFloat = OpenBarSettingsMetrics.panelPadding) -> some View {
        self
            .padding(padding)
            .background {
                SettingsPanelCardBackground()
            }
    }
}

private struct SettingsPanelCardBackground: View {
    var body: some View {
        SettingsFillBackground(shape: OpenBarTheme.cardShape())
    }
}

/// Card-fill background in any shape (search field, history capsule, tiles, chips, panels). With Increase Contrast it
/// adds the card hairline, so the shape stays visible against its surroundings (docs/design §10).
struct SettingsFillBackground<S: InsettableShape>: View {
    let shape: S
    var fill: Color = OpenBarTheme.Colors.cardFill
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        self.shape
            .fill(self.fill)
            .overlay {
                if self.contrast == .increased {
                    self.shape.strokeBorder(OpenBarTheme.Colors.cardStroke, lineWidth: 1)
                }
            }
    }
}

/// The opaque sidebar used with Reduce Transparency: the window background with the card tint, so the sidebar stays
/// distinct from the detail column without any translucency.
struct SettingsOpaqueSidebarBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(OpenBarTheme.Colors.cardFill)
    }
}

extension EnvironmentValues {
    /// A fixed "now" for Settings previews in the render gallery. Nil, the default, means the current time.
    @Entry var settingsPreviewNow: Date?
}

/// Link-style button in the accent color (docs/design §2.1: links use the accent). The system link style always
/// draws in the system link blue, which ignores the Settings tint.
struct SettingsLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .foregroundStyle(OpenBarTheme.Colors.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
        if #available(macOS 15.0, *) {
            label.pointerStyle(.link)
        } else {
            label
        }
    }
}

extension ButtonStyle where Self == SettingsLinkButtonStyle {
    static var settingsLink: SettingsLinkButtonStyle {
        SettingsLinkButtonStyle()
    }
}
