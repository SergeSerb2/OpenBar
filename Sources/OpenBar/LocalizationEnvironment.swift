import Foundation
import SwiftUI

func openBarLocalizedLayoutDirection() -> LayoutDirection {
    Locale.Language(identifier: openBarLocalizedResourceLocale().identifier).characterDirection == .rightToLeft
        ? .rightToLeft : .leftToRight
}

private struct OpenBarLocalizationEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(
                \.locale,
                openBarLocalizationSignature().isEmpty
                    ? openBarLocalizedLocale() : openBarLocalizedResourceLocale())
            .environment(\.layoutDirection, openBarLocalizedLayoutDirection())
    }
}

extension View {
    /// Keep native formatting and layout in the same language as the selected string resources.
    func openBarLocalized() -> some View {
        self.modifier(OpenBarLocalizationEnvironment())
    }
}
