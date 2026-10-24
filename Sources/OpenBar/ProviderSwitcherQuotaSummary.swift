import OpenBarCore

/// Worst quota lane of one provider, as the switcher segment shows it.
struct ProviderSwitcherQuotaSummary: Equatable {
    /// Percent in the user's used/remaining display semantics (already chosen by the caller).
    let displayPercent: Double
    /// Remaining percent of the worst lane. Drives the tone, whatever the display setting.
    let remainingPercent: Double
    /// True when the data is last-known (stale).
    let isStale: Bool

    var tone: OpenBarQuotaTone {
        OpenBarQuotaTone.resolve(remainingPercent: self.remainingPercent, isStale: self.isStale)
    }
}

extension ProviderSwitcherQuotaSummary {
    /// The figure a segment shows, for example "62%". Also the segment's accessibility value.
    var numeralText: String {
        UsageFormatter.percentString(self.displayPercent)
    }

    /// Tone symbol drawn before the figure, so color is never the only cue: the filled triangle or octagon at
    /// warning or critical, and `clock` for last-known (stale) data, whose text stays secondary.
    var toneSymbolName: String? {
        self.tone.symbolName
    }

    /// Warning and critical figures are semibold; the rest are medium.
    var isEmphasized: Bool {
        switch self.tone {
        case .warning, .critical: true
        case .normal, .stale: false
        }
    }
}
