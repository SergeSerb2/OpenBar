import AppKit
import KeyboardShortcuts
import OpenBarCore
import SwiftUI

/// Two-line label for grouped-form rows that genuinely need a supporting sentence.
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title)
                .foregroundStyle(self.isEnabled ? .primary : .secondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Section footer for grouped forms. macOS renders bare footer text trailing-aligned
/// at body size, which reads badly for long captions; this pins it leading in the
/// `caption` role. Secondary rather than the spec's tertiary: tertiary measures about
/// 1.9:1 (light) and 2.3:1 (dark) on the window background, too faint for guidance text.
struct SettingsSectionFooter<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        self.content
            .font(OpenBarTheme.Fonts.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsSectionFooter where Content == Text {
    init(_ text: String) {
        self.init { Text(text) }
    }
}

/// Inline warning or error in Settings (docs/design §2.2): the tone's symbol in its color, then the words in the
/// label color, so color is never the only signal and long messages stay readable.
struct SettingsStatusMessage: View {
    let text: String
    let tone: OpenBarQuotaTone

    init(_ text: String, tone: OpenBarQuotaTone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Label {
            Text(self.text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: self.tone.symbolName ?? "info.circle")
                .foregroundStyle(OpenBarTheme.Colors.tone(self.tone) ?? .secondary)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
struct OpenMenuShortcutRecorder: NSViewRepresentable {
    static let preferredWidth: CGFloat = 170

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .openMenu)
        context.coordinator.attach(to: recorder)
        return recorder
    }

    func updateNSView(_ nsView: KeyboardShortcuts.RecorderCocoa, context: Context) {
        nsView.shortcutName = .openMenu
        context.coordinator.attach(to: nsView)
    }

    func sizeThatFits(
        _: ProposedViewSize,
        nsView: KeyboardShortcuts.RecorderCocoa,
        context: Context)
        -> CGSize?
    {
        Self.fittedSize(intrinsicHeight: nsView.intrinsicContentSize.height)
    }

    static func fittedSize(intrinsicHeight: CGFloat) -> CGSize {
        CGSize(width: self.preferredWidth, height: intrinsicHeight)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var recorder: KeyboardShortcuts.RecorderCocoa?
        private var placeholderObservation: NSKeyValueObservation?
        private var localizedPlaceholder = ""

        override init() {
            super.init()
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(self.textDidBeginEditing(_:)),
                name: NSControl.textDidBeginEditingNotification,
                object: nil)
            center.addObserver(
                self,
                selector: #selector(self.textDidEndEditing(_:)),
                name: NSControl.textDidEndEditingNotification,
                object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to recorder: KeyboardShortcuts.RecorderCocoa) {
            if self.recorder !== recorder {
                self.placeholderObservation = nil
                self.recorder = recorder
                self.placeholderObservation = recorder.observe(\.placeholderString) { [weak self] _, _ in
                    // AppKit properties change on the main actor, including deferred recorder cleanup.
                    MainActor.assumeIsolated {
                        self?.restorePlaceholder()
                    }
                }
            }
            self.updatePlaceholder(isRecording: recorder.currentEditor() != nil)
        }

        @objc private func textDidBeginEditing(_ notification: Notification) {
            guard notification.object as? KeyboardShortcuts.RecorderCocoa === self.recorder else { return }
            self.updatePlaceholder(isRecording: true)
        }

        @objc private func textDidEndEditing(_ notification: Notification) {
            guard notification.object as? KeyboardShortcuts.RecorderCocoa === self.recorder else { return }
            self.updatePlaceholder(isRecording: false)
        }

        private func updatePlaceholder(isRecording: Bool) {
            self.localizedPlaceholder = L(isRecording ? "press_shortcut" : "record_shortcut")
            self.restorePlaceholder()
        }

        private func restorePlaceholder() {
            guard let recorder = self.recorder,
                  recorder.placeholderString != self.localizedPlaceholder else { return }
            recorder.placeholderString = self.localizedPlaceholder
        }
    }
}

// MARK: - Legacy building blocks (Debug pane)

@MainActor
struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var binding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5.4) {
            Toggle(isOn: self.$binding) {
                Text(self.title)
                    .font(.body)
            }
            .toggleStyle(.checkbox)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct SettingsSection<Content: View>: View {
    let title: String?
    let caption: String?
    let contentSpacing: CGFloat
    private let content: () -> Content

    init(
        title: String? = nil,
        caption: String? = nil,
        contentSpacing: CGFloat = 14,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.title = title
        self.caption = caption
        self.contentSpacing = contentSpacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(OpenBarTheme.Fonts.laneTitle)
            }
            if let caption {
                Text(caption)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: self.contentSpacing) {
                self.content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
