import OpenBarCore

/// Menu bar glyph tokens added during the redesign (docs/design/README.md §9.1, design council revision).
/// The lead folds these into `OpenBarGlyphMetrics` in `OpenBarDesignTokens.swift`.
extension OpenBarGlyphMetrics {
    /// Rail opacity for stale data. Replaces `staleAlpha` (0.5), which nearly vanished on a light menu bar.
    /// The stale ring mark carries the state; the rails only step back.
    static let staleRailAlpha: Double = 0.7
    /// A lane that exists but has no value, such as a plan without a weekly quota.
    static let missingLaneAlpha: Double = 0.45
    /// Track opacity with Reduce Transparency. An opaque menu bar loses the contrast that vibrancy adds
    /// to template images, so the track steps up slightly. Increase Contrast still wins.
    static let trackAlphaReducedTransparency: Double = 0.34
    /// Smallest fill for a nonzero value, so a nearly empty lane still shows a sliver.
    static let minimumFill: Double = 1.5
}
