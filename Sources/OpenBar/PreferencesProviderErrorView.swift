import OpenBarCore
import SwiftUI

struct ProviderErrorDisplay {
    let preview: String
    let full: String
}

@MainActor
struct ProviderErrorView: View {
    let title: String
    let display: ProviderErrorDisplay
    @Binding var isExpanded: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                // Critical tone: octagon symbol + color, words in the label color (docs/design §2.2, §9.2).
                Label {
                    Text(self.title)
                        .font(OpenBarTheme.Fonts.meta.weight(.semibold))
                } icon: {
                    Image(systemName: OpenBarQuotaTone.critical.symbolName ?? "exclamationmark.octagon.fill")
                        .foregroundStyle(OpenBarTheme.Colors.critical)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button {
                    self.onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Copy error"))
            }

            Text(self.display.preview)
                .font(OpenBarTheme.Fonts.meta)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if self.display.preview != self.display.full {
                Button(self.isExpanded ? L("Hide details") : L("Show details")) { self.isExpanded.toggle() }
                    .buttonStyle(.settingsLink)
                    .font(OpenBarTheme.Fonts.meta)
            }

            if self.isExpanded {
                Text(self.display.full)
                    .font(OpenBarTheme.Fonts.meta)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 2)
    }
}
