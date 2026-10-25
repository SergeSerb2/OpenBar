import AppKit
import OpenBarCore
import SwiftUI

/// System Settings-style sidebar: fixed app panes on top, one row per provider below.
@MainActor
struct SettingsSidebarView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Binding var selection: SettingsPane
    var onSelectAbout: () -> Void = {}
    var search: Binding<String>?
    @State private var searchText = ""
    @Environment(\.undoManager) private var undoManager

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OpenBarSpacing.compact) {
                SettingsSidebarSearchField(
                    searchText: self.search ?? self.$searchText,
                    isFocused: self.$isSearchFocused)
                SettingsSidebarSortToggle(
                    isOn: self.$settings.providersSortedAlphabetically,
                    enabledOnly: self.$settings.providersEnabledOnly,
                    canRestore: self.settings.canRestoreDefaultProviderOrder,
                    onRestore: self.restoreProviderOrder)
            }
            .padding(.horizontal, OpenBarSpacing.relaxed)
            // The sidebar runs up behind the transparent titlebar; its content starts below the traffic lights.
            .padding(.top, OpenBarSettingsMetrics.titlebarBandHeight)
            .padding(.bottom, OpenBarSpacing.tight)

            self.content
        }
        .background {
            // ⌘F focuses the provider search, as the native sidebar search field did.
            Button(L("Search providers")) { self.isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .focusable(false)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            List(selection: Binding(self.$selection)) {
                self.appPanesSection
                self.providersSection
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if self.settings.canUndoProviderOrderChange {
                HStack(spacing: OpenBarSpacing.tight) {
                    Text(L("Provider order updated"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: OpenBarSpacing.tight)
                    Button(L("Undo")) { self.settings.undoProviderOrderChange() }
                        .buttonStyle(.plain)
                        .foregroundStyle(OpenBarTheme.Colors.accent)
                }
                .font(OpenBarTheme.Fonts.meta)
                .padding(.horizontal, OpenBarSpacing.group)
                .padding(.vertical, OpenBarSpacing.regular)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var appPanesSection: some View {
        Section {
            SettingsSidebarPaneRow(pane: .general, systemImage: "gearshape")
            SettingsSidebarPaneRow(pane: .iCloudSync, systemImage: "icloud")
            SettingsSidebarPaneRow(pane: .usageSpend, systemImage: "chart.bar")
            SettingsSidebarPaneRow(pane: .notifications, systemImage: "bell")
            SettingsSidebarPaneRow(pane: .menuBar, systemImage: "menubar.rectangle")
            SettingsSidebarPaneRow(pane: .menu, systemImage: "filemenu.and.selection")
            SettingsSidebarPaneRow(pane: .advanced, systemImage: "slider.horizontal.3")
            SettingsSidebarPaneRow(pane: .hooks, systemImage: "bolt.horizontal.circle")
            SettingsSidebarPaneRow(pane: .plugins, systemImage: "puzzlepiece.extension")
            SettingsSidebarAboutRow(onSelect: self.onSelectAbout)
            if self.settings.debugMenuEnabled {
                SettingsSidebarPaneRow(pane: .debug, systemImage: "ladybug")
            }
        }
    }

    private var providersSection: some View {
        let visibleProviders = self.filteredProviders
        return Section {
            ForEach(visibleProviders, id: \.self) { provider in
                self.providerRow(provider)
            }
            .onMove { fromOffsets, toOffset in
                guard self.canReorderProviders else { return }
                if self.settings.moveVisibleProviders(
                    visibleProviders.map(\.instanceID), fromOffsets: fromOffsets, toOffset: toOffset)
                {
                    self.settings.registerProviderOrderUndo(in: self.undoManager)
                }
            }

            if visibleProviders.isEmpty {
                Text(L("No matching providers"))
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                Button(L("Clear filters")) {
                    (self.search ?? self.$searchText).wrappedValue = ""
                    self.settings.providersEnabledOnly = false
                }
                .buttonStyle(.plain)
                .font(OpenBarTheme.Fonts.meta)
                .foregroundStyle(OpenBarTheme.Colors.accent)
            }
        } header: {
            HStack(spacing: OpenBarSpacing.tight) {
                Text(L("tab_providers"))
                    .font(OpenBarTheme.Fonts.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: L("providers_on_count"), self.enabledProviderCount))
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .padding(.trailing, OpenBarSpacing.relaxed)
            }
        }
    }

    private func providerRow(_ provider: UsageProvider) -> some View {
        SettingsSidebarProviderRow(
            provider: provider,
            store: self.store,
            isEnabled: self.enabledBinding(for: provider))
            .tag(SettingsPane.provider(provider.instanceID))
            .moveDisabled(!self.canReorderProviders)
    }

    private func restoreProviderOrder() {
        if self.settings.restoreDefaultProviderOrder() { self.settings.registerProviderOrderUndo(in: self.undoManager) }
    }

    private var orderedProviders: [UsageProvider] {
        guard self.settings.providersSortedAlphabetically else {
            return self.settings.orderedProviders().compactMap(\.firstPartyProvider)
        }
        return OpenBarConfig.alphabeticalProviderOrder(enablement: { provider in
            self.settings.isProviderEnabled(provider: provider, metadata: self.store.metadata(for: provider))
        })
    }

    private var filteredProviders: [UsageProvider] {
        let providers = self.orderedProviders.filter { provider in
            !self.settings.providersEnabledOnly
                || self.settings.isProviderEnabled(provider: provider, metadata: self.store.metadata(for: provider))
        }
        return ProvidersPane.filteredProviders(
            providers,
            query: (self.search ?? self.$searchText).wrappedValue,
            displayName: { self.store.metadata(for: $0).displayName })
    }

    private var enabledProviderCount: Int {
        self.orderedProviders.count(where: { provider in
            self.settings.isProviderEnabled(provider: provider, metadata: self.store.metadata(for: provider))
        })
    }

    private var canReorderProviders: Bool {
        !self.settings.providersSortedAlphabetically && !self.settings.providersEnabledOnly
            && (self.search ?? self.$searchText).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func enabledBinding(for provider: UsageProvider) -> Binding<Bool> {
        let meta = self.store.metadata(for: provider)
        return Binding(
            get: { self.settings.isProviderEnabled(provider: provider, metadata: meta) },
            set: { newValue in
                self.settings.setProviderEnabled(provider: provider, metadata: meta, enabled: newValue)
            })
    }
}

/// App pane row: a plain monochrome symbol in a 20-pt frame (no colored plate), then the title.
@MainActor
private struct SettingsSidebarPaneRow: View {
    let pane: SettingsPane
    let systemImage: String

    var body: some View {
        HStack(spacing: OpenBarSpacing.regular) {
            Image(systemName: self.systemImage)
                .font(.system(size: OpenBarSettingsMetrics.sidebarRowSymbolSize))
                .foregroundStyle(.secondary)
                .frame(
                    width: OpenBarSettingsMetrics.sidebarRowSymbolFrame,
                    height: OpenBarSettingsMetrics.sidebarRowSymbolFrame)
                .accessibilityHidden(true)
            Text(self.pane.title)
        }
        .tag(self.pane)
    }
}

@MainActor
private struct SettingsSidebarAboutRow: View {
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: OpenBarSpacing.regular) {
            Group {
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "info.circle")
                        .font(.system(size: OpenBarSettingsMetrics.sidebarRowSymbolSize))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(
                width: OpenBarSettingsMetrics.sidebarRowSymbolFrame,
                height: OpenBarSettingsMetrics.sidebarRowSymbolFrame)
            .accessibilityHidden(true)
            Text(SettingsPane.about.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // List selection ignores clicks on the already-selected row; this also returns a pushed subpage to About.
        .simultaneousGesture(TapGesture().onEnded { self.onSelect() })
        .tag(SettingsPane.about)
    }
}

@MainActor
struct SettingsSidebarProviderRow: View {
    let provider: UsageProvider
    @Bindable var store: UsageStore
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: OpenBarSpacing.regular) {
            Group {
                if let brand = ProviderBrandIcon.image(for: self.provider) {
                    Image(nsImage: brand)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "circle.dotted")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: OpenBarSettingsMetrics.sidebarLogoSize, height: OpenBarSettingsMetrics.sidebarLogoSize)
            .foregroundStyle(self.isEnabled ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.tertiary)
            .accessibilityHidden(true)

            Text(self.store.metadata(for: self.provider).displayName)
                .foregroundStyle(self.isEnabled ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)

            Spacer(minLength: OpenBarSpacing.tight)

            if self.store.refreshingProviders.contains(self.provider.instanceID) {
                ProgressView()
                    .controlSize(.mini)
            }

            if self.isEnabled, self.store.statusChecksEnabled {
                let indicator = self.store.status(for: self.provider)?.indicator
                SettingsSidebarStatusMark(indicator: indicator)
                    .help(Self.statusDescription(for: indicator))
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            Button(self.isEnabled ? L("Disable") : L("Enable")) {
                self.isEnabled.toggle()
            }
        }
        .accessibilityLabel(self.accessibilityLabel)
    }

    private var accessibilityLabel: String {
        Self.accessibilityLabel(
            name: self.store.metadata(for: self.provider).displayName,
            isEnabled: self.isEnabled,
            statusChecksEnabled: self.store.statusChecksEnabled,
            indicator: self.store.status(for: self.provider)?.indicator)
    }

    nonisolated static func accessibilityLabel(
        name: String,
        isEnabled: Bool,
        statusChecksEnabled: Bool,
        indicator: ProviderStatusIndicator?) -> String
    {
        guard isEnabled else { return "\(name) — \(L("Disabled"))" }
        guard statusChecksEnabled else { return name }
        return "\(name) — \(self.statusDescription(for: indicator))"
    }

    nonisolated static func statusDescription(for indicator: ProviderStatusIndicator?) -> String {
        L("Provider service status: %@", (indicator ?? .unknown).label)
    }

    /// Service status mark for a provider's indicator (docs/design §2.2): operational is an `ok` dot, a minor
    /// issue a `warning` triangle, a major or critical outage a `critical` octagon, and maintenance or a missing
    /// status a `stale` ring.
    nonisolated static func statusMark(for indicator: ProviderStatusIndicator?) -> SettingsSidebarStatusMark.Kind {
        switch indicator ?? .unknown {
        case .none: .operational
        case .minor: .minorIssue
        case .major, .critical: .outage
        case .maintenance, .unknown: .unknown
        }
    }

    nonisolated static func statusColor(for indicator: ProviderStatusIndicator?) -> Color {
        switch self.statusMark(for: indicator) {
        case .operational: OpenBarTheme.Colors.ok
        case .minorIssue: OpenBarTheme.Colors.warning
        case .outage: OpenBarTheme.Colors.critical
        case .unknown: OpenBarTheme.Colors.stale
        }
    }
}

/// 7-pt service status mark whose shape repeats its tone, so color is never the only signal: a filled dot
/// (operational), a triangle (minor issue), an octagon (major or critical outage), or a ring (maintenance or
/// unknown). Plain shapes, so no symbol renditions are cached. White on the selected row.
@MainActor
struct SettingsSidebarStatusMark: View {
    enum Kind: Equatable {
        case operational
        case minorIssue
        case outage
        case unknown
    }

    let kind: Kind
    let color: Color
    @Environment(\.backgroundProminence) private var backgroundProminence

    init(indicator: ProviderStatusIndicator?) {
        self.kind = SettingsSidebarProviderRow.statusMark(for: indicator)
        self.color = SettingsSidebarProviderRow.statusColor(for: indicator)
    }

    init(kind: Kind, color: Color) {
        self.kind = kind
        self.color = color
    }

    var body: some View {
        let color = self.backgroundProminence == .increased ? Color.white : self.color
        Group {
            switch self.kind {
            case .operational:
                Circle().fill(color)
            case .minorIssue:
                SettingsStatusTriangle().fill(color)
            case .outage:
                SettingsStatusOctagon().fill(color)
            case .unknown:
                Circle().strokeBorder(color, lineWidth: 1.25)
            }
        }
        .frame(
            width: OpenBarSettingsMetrics.sidebarStatusMarkSize,
            height: OpenBarSettingsMetrics.sidebarStatusMarkSize)
    }
}

private struct SettingsStatusTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SettingsStatusOctagon: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * (1 - 1 / (1 + 2.0.squareRoot()))
        let cut = min(inset, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

/// Provider search: 28 pt tall, radius 7, card fill, no border (docs/design §9.4).
private struct SettingsSidebarSearchField: View {
    @Binding var searchText: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: OpenBarSpacing.compact) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(L("Search providers"), text: self.$searchText)
                .textFieldStyle(.plain)
                .focused(self.isFocused)

            if !self.searchText.isEmpty {
                Button {
                    self.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(L("Clear"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OpenBarSpacing.regular)
        .frame(minHeight: OpenBarSettingsMetrics.searchFieldHeight)
        .background(SettingsFillBackground(shape: RoundedRectangle(
            cornerRadius: OpenBarRadius.control,
            style: .continuous)))
    }
}

private struct SettingsSidebarSortToggle: View {
    @Binding var isOn: Bool
    @Binding var enabledOnly: Bool
    let canRestore: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                self.isOn.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.isOn ? OpenBarTheme.Colors.accent : Color.secondary)
                    .frame(width: 22, height: OpenBarSettingsMetrics.searchFieldHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(self.isOn
                ? L("Sorted alphabetically (enabled first) — click to use your custom order")
                : L("Sort providers alphabetically (enabled first)"))
            .accessibilityLabel(L("Sort providers alphabetically"))
            .accessibilityAddTraits(self.isOn ? .isSelected : [])

            Menu {
                Toggle(L("Only show enabled providers"), isOn: self.$enabledOnly)
                Divider()
                Button(L("Restore default order"), action: self.onRestore)
                    .disabled(!self.canRestore)
                    .help(L("Also restores the provider order in the menu bar. Can be undone."))
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(self.enabledOnly ? OpenBarTheme.Colors.accent : Color.secondary)
                    .frame(width: 14, height: OpenBarSettingsMetrics.searchFieldHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            // The borderless menu style tints its label; keep it secondary unless the filter is on.
            .tint(self.enabledOnly ? OpenBarTheme.Colors.accent : Color.secondary)
            .fixedSize()
            .help(L("Provider sorting"))
            .accessibilityLabel(L("Provider sorting"))
        }
    }
}
