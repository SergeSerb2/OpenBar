---
summary: "OpenBar's Calm native design spec: tokens, per-surface layouts, accessibility, performance budget, render gallery, and the implementation work split."
read_when:
  - Changing any visual surface (menu bar glyph, menu, Settings, widgets, docs site, social card)
  - Adding colors, fonts, spacing, or icons
  - Splitting or reviewing redesign work
---

# OpenBar design spec — "Calm native"

Version 1 · 2026-10-24 · Phase 1 of 3 (design → bug audit → public 1.0.0).

This spec replaces the look OpenBar inherited from CodexBar. OpenBar must feel like a first-party macOS 26
utility: a monochrome menu bar glyph, one signature accent, soft layered cards, SF typography with a tight
hierarchy, and a quiet surface that is fast to read. The redesign is **visual only**: it does not change
behavior, data, settings semantics, or provider logos. It must also make the app **lighter and faster**;
the [performance budget](#11-performance-budget) is a requirement, not a goal.

Related files:

| What | Where |
| --- | --- |
| Surface inventory (every surface → files, CodexBar identity markers) | [`inventory.md`](inventory.md) |
| Design tokens (raw values, shared by app, widget, CLI) | `Sources/OpenBarCore/Design/OpenBarDesignTokens.swift` |
| App accessors (SwiftUI `Color`/`Font`, dynamic `NSColor`) | `Sources/OpenBar/Design/OpenBarTheme.swift` |
| Widget accessors | `Sources/OpenBarWidget/WidgetTheme.swift` |
| Icon sources (concepts, final, glyph reference) | [`icon/`](icon/) |
| Mockups (open in a browser) | [`mockups/index.html`](mockups/index.html) |
| Render gallery (real views → PNG) | `Scripts/render_gallery.sh`, `Tests/OpenBarTests/RenderGallery/` |
| Memory benches used for decisions | [`bench/`](bench/) |

---

## 1. Principles

1. **Native first.** System fonts, system label colors, system menus, system controls, system window
   chrome. OpenBar adds only an accent, status tones, and flat card fills. If AppKit or SwiftUI draws it
   natively, use that.
2. **Numbers first.** The remaining quota and the reset time are the two facts a user opens the menu for.
   They get the strongest weight; everything else is secondary text.
3. **Color only with meaning.** Neutral by default. The accent marks selection and action. A status tone
   appears only when the data is in that state. Provider colors identify a provider and nothing else.
4. **Never color alone.** Every status has a symbol and words. Every chart series has a label or legend.
5. **Light by construction.** Fewer views, fewer layers, static drawing, no idle work. A design that needs
   a material, a blur, a shadow, an animation, or a timer must justify it against the budget.
6. **Calm, not empty.** No decoration, but no ambiguity: aligned baselines, consistent spacing, one
   hierarchy per surface.

---

## 2. Color

All values are sRGB hex. Tokens live in `OpenBarPalette` (core) and are read through `OpenBarTheme.Colors`
(SwiftUI), `OpenBarTheme.NSColors` (AppKit, dynamic), or `WidgetTheme.Colors`. Each token has light, dark,
and Increase Contrast variants; the dynamic `NSColor` resolves at draw time for the drawing appearance.

Text and SF Symbols use **system label colors** (`labelColor`, `secondaryLabelColor`,
`tertiaryLabelColor`) everywhere. Do not introduce custom text grays.

### 2.1 Signature accent: Iris

| Token | Light | Dark | Light · Increase Contrast | Dark · Increase Contrast | Use |
| --- | --- | --- | --- | --- | --- |
| `accent` | `#5246E0` | `#A39EFF` | `#3A2FC4` | `#BDB9FF` | Accent text, links, glyph tints, focus, toggles via `.tint` |
| `accentFill` | `#5246E0` | `#6159F0` | `#3A2FC4` | `#5B52EE` | Filled shapes behind white labels: selected switcher segment, menu highlight, primary buttons |

Contrast (WCAG 2.x, `docs/design/bench/palette_check.py`): `accent` on white 6.34:1, on `#F2F2F5`
5.68:1; dark `accent` on `#1E1E1E` 7.06:1, on `#2C2C2E` 5.90:1. White on `accentFill`: light 6.34:1, dark
5.01:1, dark HC 5.40:1. The dark `accentFill` is only 2.78:1 against a dark card, so a selected segment is
never identified by its fill alone: its label also turns white while unselected labels stay secondary.
Iris is a blue-violet (hue ≈ 245°): not CodexBar's teal/red, not system blue. Its smallest distance to a
status tone is ΔE76 19.0 in light mode (tritanopia) and 13.1 in dark mode (deuteranopia); in dark Increase
Contrast under deuteranopia Iris and `ok` come close (6.9). They never encode competing meaning, and `ok`
always carries its checkmark.

**System accent rule.** With the macOS default accent (Multicolor) OpenBar shows Iris, as first-party apps
show their own accent. If the user picked an explicit accent in System Settings → Appearance, OpenBar
follows it (`OpenBarTheme.usesSystemAccent`, which reads the global `AppleAccentColor` default). Apply the
accent with `.tint(OpenBarTheme.Colors.accent)` at each SwiftUI root (menu card container, Settings root,
sheets) and with `OpenBarTheme.NSColors.accentFill` in AppKit drawing. Widgets always use Iris; WidgetKit
applies the user's tint in accented mode.

Where the accent appears: the selected switcher segment, highlighted menu card and row plates, Settings
sidebar selection and switches, links, primary buttons, the focus ring (system), the docs site, the social
card, and the app icon. Nowhere else.

### 2.2 Status tones

| Tone | Light | Dark | Light HC | Dark HC | Symbol (SF Symbols) | When |
| --- | --- | --- | --- | --- | --- | --- |
| `ok` | `#07729A` | `#2EC0EA` | `#05648A` | `#6FD6F5` | `checkmark.circle.fill` | Provider operational; pace lasts to reset |
| `warning` | `#946200` | `#FFC533` | `#7A4F00` | `#FFD56B` | `exclamationmark.triangle.fill` | Remaining ≤ 25 %; pace runs out before reset; minor outage |
| `critical` | `#B4123F` | `#FF6378` | `#940B33` | `#FF8A9A` | `exclamationmark.octagon.fill` | Remaining ≤ 10 % or exhausted; refresh failed; major outage |
| `stale` | `#8A8A8E` | `#98989D` | `#6E6E73` | `#AEAEB2` | `clock` | Last-known data, unknown status. Graphics only; stale **text** uses `secondaryLabelColor` |

Rules:

- `OpenBarQuotaTone.resolve(remainingPercent:isStale:)` is the only place thresholds live
  (warning ≤ 25 %, critical ≤ 10 %). It always uses *remaining*, whatever the used/remaining display setting.
- A tone is always shown as **symbol + color + words** ("18 % left", "Runs out in 38m"). Never tint a whole
  card or a whole row. Never change a provider-tinted meter fill to a tone color.
- Status tones are reserved: never use them as chart series, decoration, or brand color.
- Text contrast: `ok`, `warning`, `critical` are ≥ 4.5:1 on white and on `#F2F2F5` in light mode, and
  ≥ 4.85:1 on `#2C2C2E` in dark mode. `stale` is ≥ 3:1 (non-text) only.
- Colorblind separation (Machado 2009 simulation, CIELAB ΔE76, worst ok/warning/critical pair): light
  normal 58.8, protanopia 35.3, deuteranopia 26.5, tritanopia 41.8; dark normal 78.5, protan 39.8, deutan
  50.1, tritan 48.3; Increase Contrast variants ≥ 23.5. Shape (circle / triangle / octagon / clock) carries
  the tone for every reader.
- Replace hardcoded `.green` / `.red` / `.orange` / `systemRed` used for status (pace stripes, status
  dots, compact rows, provider detail severity, status components) with these tones.

### 2.3 Surfaces

| Token | Light | Dark | HC light | HC dark | Use |
| --- | --- | --- | --- | --- | --- |
| `cardFill` | black 4.5 % | white 6 % | black 8 % | white 12 % | Soft card behind a menu section, switcher rail, Settings tiles |
| `cardStroke` | black 8 % | white 10 % | black 35 % | white 40 % | Card hairline, **only** with Increase Contrast or on opaque surfaces |
| `meterTrack` | black 10 % | white 14 % | black 28 % | white 32 % | Unfilled part of a meter |

Cards are flat fills that sit on whatever material the system provides (menu glass, window background).
They have no shadow, no blur, no gradient, and no border by default. "Layered" comes from the stacked
fills and the gaps between cards, not from elevation.

### 2.4 Provider colors

Provider brand colors (`ProviderBranding.color` plus the per-provider override in Settings) keep their
current meaning: *"Sets the color of this provider's usage bars, charts, and switcher tab."* They fill a
provider's meters, its switcher strip, and its chart series, and nothing else. They never tint text,
cards, or chrome. Provider logos are trademarks: keep the shipped SVG/PNG artwork unchanged; only size,
template tint, and framing change.

### 2.5 Chart palette (non-provider series)

For series that are not providers (models, storage kinds, token types). Fixed order, never cycled; a
seventh series folds into "Other". Validated with the data-viz palette validator (all checks pass:
lightness band, chroma floor, adjacent CVD ΔE ≥ 8, normal-vision ΔE ≥ 15).

| Slot | 1 | 2 | 3 | 4 | 5 | 6 |
| --- | --- | --- | --- | --- | --- | --- |
| Light | `#5246E0` | `#EB6834` | `#1BAF7A` | `#EDA100` | `#E87BA4` | `#2A78D6` |
| Dark | `#7F78F0` | `#D95926` | `#199E70` | `#C98500` | `#D55181` | `#3987E5` |

Light slots 3–5 are below 3:1 on white, so charts that use them always show a legend and direct labels or
the hover detail (see §8).

---

## 3. Typography

SF Pro through system fonts only. Use the role, not a size. `OpenBarTheme.Fonts.font(_:)` maps each role
to a SwiftUI text style so the system's text-size handling applies where macOS supports it.

| Role | Size / weight | Text style | Digits | Use |
| --- | --- | --- | --- | --- |
| `title` | 17 semibold | `.title2` | — | Settings pane and dashboard titles |
| `cardTitle` | 13 semibold | `.headline` | — | Provider name in a card header |
| `laneTitle` | 12 medium | `.callout` | — | "Session", "Weekly", section names in cards |
| `laneValue` | 13 semibold | `.body` | tabular | "62% left", cost values |
| `meta` | 11 regular | `.subheadline` | tabular | Reset time, updated time, plan, pace, subtitles |
| `caption` | 10 regular | `.caption` | — | Chart axes, footers, legal |
| `hero` | 28 semibold (widgets: small 24, medium 34, large 42) | fixed | tabular | Widget headline figure, dashboard totals |
| `code` | 11 regular SF Mono | fixed | — | Paths, commands, hex values |

Rules: one weight step per hierarchy level; no uppercase labels, no letter-spacing, no italic; figures
always tabular; truncate names with `.tail`, emails with `.middle`; menu bar text stays the system menu
bar font (13 pt, `monospacedDigitSystemFont`).

---

## 4. Spacing and grid

2-pt grid. Use `OpenBarSpacing` names only: `hairline` 2, `tight` 4, `compact` 6, `regular` 8, `relaxed`
10, `section` 12, `group` 16, `pane` 20, `page` 24.

Menu metrics (`OpenBarMenuMetrics`): menu width 310 (existing `menuCardBaseWidth`), card inset 8 from the
menu content edge, card gap 6, card padding 12 × 10, lane spacing 10, lane inner spacing 5, meter height 6,
meter split gap 1.5, logo 16, switcher segment height 30.

---

## 5. Shape, materials, separators

- **Radii** (`OpenBarRadius`, always `.continuous`): card 10, switcher rail 9, control/segment/selection
  plate 7, chip/tile 5, chart bar data end 2. Meters are capsules. Window and menu corners are the system's.
- **Materials:** only the ones the system already provides (menu glass, window background) plus **one**
  `NSVisualEffectView(.sidebar)` behind the Settings sidebar. No material inside a menu row, card, chart,
  tooltip, or widget. No SwiftUI `.background(.regularMaterial)` in menus. Tooltips use `cardFill` on the
  system background.
- **Separators:** between cards use the 6-pt gap, not a separator item. Inside a card, a hairline
  (`Divider()`, inset to the card padding) separates groups only when two groups would otherwise touch.
  Native separator items remain between native action groups.
- **Elevation:** none. No shadows on cards, icons, chips, or charts. (The About icon loses its accent
  shadow and hover scale.)

---

## 6. Iconography

- SF Symbols, monochrome rendering, `secondaryLabelColor` by default, filled variants only for status.
  Menu action rows: 14 pt; card affordances (chevron, copy): 9–10 pt; Settings sidebar: 14 pt in a 20-pt
  frame.
- **Vocabulary** (keep the set small; every distinct symbol costs a cached CoreSVG rendition):
  `arrow.clockwise` (refresh), `person.badge.plus` (add account), `chart.bar.xaxis` (usage dashboard),
  `waveform.path.ecg` (status page), `gearshape` (settings), `chevron.right` (submenu), `doc.on.doc`
  (copy), plus the four tone symbols. A menu shows at most 10 distinct symbols.
- Settings sidebar: replace the colored `SettingsIconChip` plates with plain monochrome symbols (General
  `gearshape`, iCloud Sync `icloud`, Usage & Spend `chart.bar`, Notifications `bell`, Menu Bar
  `menubar.rectangle`, Menu `filemenu.and.selection`, Advanced `slider.horizontal.3`, Hooks
  `bolt.horizontal.circle`, Plugins `puzzlepiece.extension`, Debug `ladybug`). About keeps the app icon.
- Provider logos: template images in `labelColor` (selected switcher segment: white). Curated
  `Brand-ProviderIcon-*` artwork keeps its colors only where it already does (Spend dashboard rows).
  Widgets keep monogram plates.

---

## 7. Motion

Default is **no motion**. Allowed:

- Menu bar loading patterns that already exist (`LoadingPattern`): only while a refresh is in flight;
  static under Reduce Motion. The critter blink/wiggle/tilt effects belong to the legacy Critters style
  only.
- Menu selection fade (existing 60 ms) — keep; nothing else animates inside a menu.
- Confetti celebration (existing Core Animation particles): disabled under Reduce Motion.
- Settings: system transitions only.

No `withAnimation`, `.animation`, `.transition`, `TimelineView`, `Timer`, or repeating `Task` in menu,
card, chart, or widget views. Countdown text is computed when a menu opens or a card rebuilds; it never
ticks while the menu is closed. The status item's own countdown refresh stays boundary-scheduled
(`scheduleMenuBarCountdownRefreshIfNeeded`), at the formatter's visible precision.

---

## 8. Charts

Applies to every chart: submenu charts, inline dashboards, Spend dashboard, OpenAI live usage, widget
history.

- **Technology:** plain SwiftUI `Path`/`Shape` with one batched path per series (existing
  `ChartBarPath`, `DailyBarChart.segmentPaths` pattern). Never SwiftUI `Canvas`, Swift Charts,
  `.drawingGroup`, `.compositingGroup`, blend modes, or Metal.
- **Marks:** bars with a 2-pt rounded data end and a square baseline end; 2-pt surface gap between adjacent
  bars and between stacked segments; lines 2 pt; points ≥ 6 pt only on hover. Single-series charts use
  the provider color; multi-series non-provider charts use §2.5 in order.
- **Axes and grid:** recessive. Baseline 1 pt `tertiaryLabelColor`; at most 3 horizontal grid lines at
  0.5 pt `tertiaryLabelColor` 50 %; axis labels `caption` in `tertiaryLabelColor`; no vertical grid; no
  axis titles when the chart title names the unit. Reset/ideal rules: 1 pt dashed `[3, 3]` in
  `secondaryLabelColor`.
- **Labels:** values and legends in text colors, never in the series color. ≥ 2 series → legend always;
  ≤ 4 series → also direct-label the latest value. Never a number on every bar.
- **Hover:** existing hover detail rows stay; the hovered bar keeps full opacity, others 55 %. No tooltips
  with materials.
- **Empty and partial states:** a single `meta` line ("No usage yet", existing strings) centered in the
  chart frame; missing days draw as track-colored stubs, not gaps.
- Sizes: menu charts 130 pt tall (existing), inline charts 44–58 pt, dashboard 210 pt.
- The burndown widget's `BurnChartCanvas` (`Canvas`) is replaced with `Path` shapes.

---

## 9. Surfaces

### 9.1 Menu bar glyph

All glyphs are **monochrome template images** (`isTemplate = true`), drawn on the 2× pixel grid with Core
Graphics, cached per state, and redrawn only when their inputs change. No color in the menu bar except the
existing quota-warning flash (now `critical`) and the existing high-contrast inactive-display treatment.

**Meter bars** (`MenuBarIconStyle.bars`, label unchanged): the OpenBar glyph. 18 × 18 pt canvas
(`OpenBarGlyphMetrics`):

```
x: 1 ─────────────────────────────── 17
   ███████████████ ▕ ░░░░░░░░░░░       primary (session)  y 3.5, h 5
   ██████████ ▕ ░░░░░░░░░░░░░░░░       secondary (weekly) y 11,  h 3.5
                 ↑ 1-pt split gap: fill and track are separate capsules
```

- Fill capsule from the leading edge, width = remaining × 16 pt; minimum width = rail height when
  remaining > 0; no fill at 0. Then a 1-pt gap, then the track capsule at 28 % (45 % with Increase
  Contrast) to the end; omit the track if it would be < 1 pt. No outline stroke. This split gap is
  OpenBar's "open" motif (it echoes the gap in the app icon).
- "Show used" fills the used fraction instead (existing `UsageBarsFillOption`).
- **States:** stale → whole glyph 50 %; missing secondary → secondary rail as track only at 45 %; one
  meaningful quota → single rail 6 pt tall centered (existing `QuotaLayoutPolicy`); credits only → single
  rail at primary height; minor issue / maintenance → 4-pt dot at the top-right corner (x 14–18, y 0–4)
  with a 1-pt cleared halo; major / critical / unknown → exclamation (2 × 6 pt bar + 2 × 2 pt dot) at the
  top-right with a cleared halo.
- **Loading:** the existing `LoadingPattern` animations animate the two rails' fill; the `unbraid` morph
  ends in the split-rail geometry.
- **Critters** (`MenuBarIconStyle.critters`): legacy, opt-in. Keep the existing drawing code unchanged so
  the setting keeps its meaning. See open question 1 about the default.

**Icon & percent** (`MenuBarIconStyle.iconAndPercent`) and custom layouts (`MenuBarLayoutRenderer`):

- `icon` token: the provider logo, 16 pt template (unchanged artwork).
- Text: system menu bar font, 13 pt regular, tabular digits, `labelColor`. Display modes:
  Percent `62%` · Pace `+11%` · Both `62% · +11%` · Reset time `↻ 3:56 PM` / `↻ 2h 14m`. The separator dot
  and the `↻` mark at 55 % opacity. **Pace is not colored** (replace the `systemGreen`/`systemRed` pace
  text with the sign alone).
- `progressBar(window:)` token: one split rail (same geometry as the primary rail; widths 32 / 36 / 44 by
  layout size), replacing the five-segment style. `usageBar` (character meter) unchanged.
- `tokensSparkline`: unchanged technique; bar ends 1 pt rounded; baseline alpha 22 %.
- Stacked two-provider layout (`compactStacked`, merged `stacked`): existing 9-pt lines; logos 9 pt.
- Small / regular / large sizes and gaps: existing values.

**Performance:** keep `IconRenderer`'s quantized cache (≤ 64 entries, ~5 KB each). Redraw only when the
quantized inputs, appearance, or status change. No per-frame drawing outside an active loading pattern.

### 9.2 Menu

The menu is a native `NSMenu`. Custom rows are hosted SwiftUI cards; actions stay native `NSMenuItem`s.

```
┌──────────────────────────── 310 ────────────────────────────┐
│  ╭ rail (cardFill, r9) ───────────────────────────────────╮  │  switcher, 8-pt inset
│  │ [◉ Codex] [■ Claude ] [◉ Cursor] [◉ Gemini] [◉ Copilot]│  │  selected = accentFill
│  │   ▔▔▔▔       ▔▔▔▔▔       ▔▔▔        ▔▔▔▔       ▔▔▔▔    │  │  2-pt weekly strips
│  ╰────────────────────────────────────────────────────────╯  │
│  ╭ card (cardFill, r10, padding 12×10) ───────────────────╮  │
│  │ ◉ Claude                                       Max  ›  │  │  cardTitle · meta
│  │ alex@example.com · Updated 1 min ago                   │  │  meta, secondary
│  │                                                        │  │  12
│  │ Session                                     62% left   │  │  laneTitle · laneValue
│  │ ██████████████████████████ ▕ ░░░░░░░░░░░░░░░░          │  │  meter 6, split gap 1.5
│  │ Resets in 2h 14m                        ✓ On pace      │  │  meta
│  │                                                        │  │  10
│  │ Weekly                                      41% left   │  │
│  │ ████████████████ ▕ ░░░░░░░░░░░░░░░░░░░░░░░░░░          │  │
│  │ Resets Thu 9:00 AM                  ✓ Lasts to reset   │  │
│  ╰────────────────────────────────────────────────────────╯  │
│  ╭ card ──────────────────────────────────────────────────╮  │  6-pt gap
│  │ Cost                                                ›  │  │
│  │ Today                              $4.12 · 1.2M tokens │  │
│  │ Last 30 days                      $88.40 · 31M tokens  │  │
│  ╰────────────────────────────────────────────────────────╯  │
│   ↻  Refresh                                         ⌘R      │  native rows
│   ⊕  Add Account…                                            │
│   ▦  Usage Dashboard                                         │
│   ∿  Status Page                                             │
│  ─────────────────────────────────────────────────────────   │
│      Settings…                                       ⌘,      │
│      About OpenBar                                           │
│      Quit OpenBar                                    ⌘Q      │
└──────────────────────────────────────────────────────────────┘
```

**Switcher** (`ProviderSwitcherView`, AppKit layers — keep AppKit): rail = one layer with `cardFill`,
radius 9, inset 8. Segments radius 7: selected `accentFill` with white logo and title; unselected
`secondaryLabelColor`; hover `labelColor` 6 %. Inline icon + title when segments fit, stacked icon over a
10-pt title otherwise (existing logic; five providers at 310 pt already need the stacked form, so the rail
is 40 pt tall then). Weekly strip (when "Weekly progress" rows are on): 2 pt, inset 8 pt at the segment
bottom, provider color on `meterTrack`; on the selected segment the track is white 30 % so it stays
visible on `accentFill`. Account switchers (Codex, Claude swap, token
accounts) use the same rail and segment styles.

**Provider card** (`UsageMenuCardView` family):

- Header: logo 16 pt (template, primary) · 6 · provider name (`cardTitle`) · spacer · plan (`meta`,
  secondary; semibold when `PlanEmphasis` is emphasized) · submenu chevron (9 pt, tertiary) when the card
  owns a submenu.
- Subline (`meta`, secondary): account (middle-truncated) · "Updated …". Error: `critical` octagon + up
  to 3 lines of `meta` in `labelColor`, copy button on the right (existing behavior). Last-known notice:
  `clock` symbol + secondary text (existing reserved row).
- Lanes (`MetricRow`): title row (`laneTitle` primary, `laneValue` right); meter; detail row (`meta`
  secondary: reset text left, pace right with its tone symbol). Warning/critical: the value takes the tone
  color with its symbol before it; the meter fill stays the provider color.
- **Meter** (`UsageProgressBar`): 6-pt capsule fill (provider color) + 1.5-pt gap + capsule track
  (`meterTrack`). Quota-warning markers and workday ticks become **1-pt gaps** cut into the fill/track
  geometry (computed segments, no blend modes). Pace marker: 2 × 10 pt rounded tick in `labelColor` at
  the expected position (replaces the green/red striped tip). Highlighted card: fill and tick white,
  track white 22 % (existing `MenuHighlightStyle` mapping).
- Group headers (Doubao Coding/Agent Plan): `laneTitle` in secondary, sentence case (drop `.uppercase`).
- Credits, Extra usage, Cloud credits, Limit-reset credits, Cost: each is a card. A section that owns a
  submenu stays its own menu item (and hosting view); sections without a submenu merge into the previous
  card's hosting view (see §11).
- Highlight (rows with a submenu or click action): the whole card fill becomes `accentFill`, text and
  symbols `selectedMenuItemTextColor`. Draw it as the card shape in SwiftUI (or a plain layer); remove the
  per-row `NSVisualEffectView(.selection)`.

**Overview** (merged menu, several providers): compact rows inside one card per group: logo 16 · name
(`laneTitle`) · spacer · mini meter 56 × 4 (same split motif) · value (`laneValue`) — existing
`MenuCardCompactAccountRowView` geometry. Healthy-account fold row: `meta` secondary + chevron. Colors use
§2.2 tones (replace yellow/orange/red literals and their 50 %/10 % thresholds with `OpenBarQuotaTone`).

**Native rows:** keep `NSMenuItem`s with SF Symbols from §6 and native key equivalents.
`PersistentRefreshMenuView` keeps its metrics; its selection plate uses `accentFill` radius 7 instead of an
`NSVisualEffectView`.

**Empty / placeholder:** a single `meta` secondary line inside the card ("No usage yet", existing strings).

### 9.3 Submenus and hosted windows

Submenus host one chart view each (existing lazy hydration). Apply §8. Width 310, padding 16 × 10
(existing). Credits history drops its hardcoded Codex teal and uses the provider color. Status components
use §2.2 tones for their dots. Storage breakdown uses §2.5 in order. The Codex workspaces inspector, the
session usage browser, and the OpenAI live usage window use the Settings shell rules (§9.4) and §8.

### 9.4 Settings

**Shell — decision: plain HStack, no `NavigationSplitView`.** One `NSHostingController` root:
`HStack(spacing: 0) { sidebar · Divider · detail }`, on every macOS version (today's `legacyLayout`
becomes the only layout). Measured in [`bench/settings-shell-bench.swift`](bench/settings-shell-bench.swift)
with identical synthetic content (11 panes, 109 provider rows using the real provider SVGs, grouped Form),
offscreen, 6 runs each (3 with a fresh window per cycle, 3 reusing one window), mean phys_footprint MiB:

| Shell | Open Δ | After 5 pane switches Δ | After 6 open/close cycles Δ |
| --- | ---: | ---: | ---: |
| `NavigationSplitView` (today, macOS 26) | +42.4 | +57.1 | +185.8 |
| **HStack sidebar + detail** | **+31.5** | **+41.5** | **+126.6** |
| `NSSplitViewController` (AppKit sidebar item) | +34.1 | +44.1 | +140.9 |
| `NSTabViewController` (toolbar tabs) | +32.0 | +70.3 | +292.6 |

(Δ = footprint minus the same process at launch. The bench pumps an offscreen window without the app's
root-swap teardown, so the cycle column exaggerates growth for every shell; compare rows, not absolutes. The app's real lifecycle is
measured by the perf agent with `trials.sh`.) HStack is lightest at every phase: about 11 MB less than
`NavigationSplitView` when it opens and about 16 MB less after navigation. Toolbar tabs cost the most once
several tabs are visited (each tab keeps its own hosting graph) and would change navigation, so they are
rejected. `NSSplitViewController` is the fallback if the owner wants the floating macOS 26 sidebar (open
question 5).

The HStack shell must keep everything `NavigationSplitView` gave: resizable, persisted sidebar width
(200–380, existing `SidebarResizeHandle` and `settingsSidebarWidth`), sidebar search with keyboard focus
(existing `SettingsSidebarSearchField`), back/forward history buttons and About routes in the toolbar,
pane titles in the window title, minimum sizes, frame autosave, Stage Manager and Dock behavior, full
keyboard navigation, and VoiceOver order sidebar → detail.

**Window:** 880 × 620 (min 800 × 540, existing), titled, full-size content, transparent titlebar, unified
toolbar (back/forward at `.navigation`), window title = pane title.

**Sidebar** (260 pt, `NSVisualEffectView(.sidebar)` behind, full height under the titlebar, hairline on
the trailing edge):

- Search field at the top: 28 pt, radius 7, `cardFill`, magnifying glass, placeholder "Search providers"
  (existing string).
- App panes: rows 28 pt, monochrome symbol 14 pt (§6) in a 20-pt frame, title 13 pt. Selection: system
  sidebar selection (accent via `.tint`).
- "Providers" section header (`meta` semibold, secondary) with "N on" count (tertiary, tabular).
- Provider rows: template logo 16 · name · spacer · 6-pt status mark in a §2.2 tone whose shape also
  carries the state: filled dot (`ok`, operational), triangle (`warning`, minor), octagon (`critical`,
  major), ring (`stale`, unknown). On the selected row the mark is white. Disabled providers: secondary
  text, no mark.
- Undo toast ("Provider order updated · Undo"): `meta` with an accent text button.

**Detail:** grouped `Form` (`.formStyle(.grouped)`), content max width 600 centered (existing 780 max is
too wide for forms; keep 780 for the Spend dashboard). Native controls, `.toggleStyle(.switch)`,
`.tint(accent)`. Section headers system; footers `caption` in the **secondary** label color
(`SettingsSectionFooter`). Owner decision 2026-10-24: tertiary measured 1.88:1 (light) and 2.26:1 (dark) on the
window background, too faint for guidance text; secondary measures 3.95:1 and 5.89:1.

- **Provider detail header** (`ProviderDetailHeaderRow`): 40-pt tile (`cardFill`, radius 9) holding the
  24-pt logo · name (`title`) · subline (`meta` secondary: account · source) · enable switch right.
  Inline usage preview uses the menu lane anatomy (§9.2) at the form width.
- **Accent color row** (`ProviderAccentColorSettingsView`): hex field (`code`, 92 pt) · color well ·
  Reset (small) — unchanged behavior.
- **Menu bar pane / layout editor:** live previews render the real glyph (§9.1). Token chips: radius 7,
  `cardFill`, `caption` text; drop targets 1-pt dashed `tertiaryLabelColor`.
- **Usage & Spend:** title (`title`), panels = cards (`cardFill`, radius 10, padding 16) instead of
  text-background panels with separator strokes; totals in `hero` (28 pt); charts per §8; activity heatmap
  uses a single-hue sequential ramp of the accent (light `#E4E2FB → #2F27A8`, dark `#2A2850 → #BDB9FF`, 5
  steps; existing increased-contrast handling) instead of GitHub green.
- **About:** app icon 96 pt (no shadow, no hover scale) · "OpenBar" (`title`) · version (`meta`) · tagline;
  updates section; links section (GitHub, website, acknowledgements). Keep the attribution link "Based on
  CodexBar by Peter Steinberger" as a plain link row (MIT courtesy; see open question 6).
- Alerts and sheets stay native (`NSAlert`, SwiftUI `.alert`, `.sheet`); sheets get `.tint(accent)`.

### 9.5 Widgets

WidgetKit tiles keep their sizes (small 155 × 155, medium 329 × 155, large 329 × 345), content margins,
and `.containerBackground(.fill.tertiary, for: .widget)`. Read `WidgetTheme` instead of literals.

- **Header** (`TileHeader`): provider mark (monogram plate, radius 5, provider color, existing contrast
  logic) · name (`cardTitle`) · freshness (`meta` secondary; stale = `clock` symbol + secondary, not
  orange).
- **Small:** header · hero (24 pt, primary lane remaining) with "left · Session" (`meta`) · 7-pt meter
  (split motif) · reset line (`meta`).
- **Medium:** left column as small (hero 34 pt); right column ≥ 140 pt after a 1-pt hairline (12 %):
  secondary lanes (title, value, 7-pt meter, reset), then one cost or credits line (`meta`).
- **Large:** header · hero row · up to 3 lanes · cost/credits rows · 7-day history bars (§8, 44 pt).
- **Tones:** low lanes use §2.2 symbols + tone color on the value (replaces red-only at ≤ 10 %).
- **Accented / vibrant modes:** no provider color; shapes and text carry everything (fills at 100 % /
  track at 25 % of the tint).
- **Burndown and combined burndown:** keep layout; replace `Canvas` with `Path`; status colors map to
  §2.2; the bespoke `BurnTheme` gradient becomes the system container background.
- **Entries:** keep timeline entries small: at most the lanes a family can show (≤ 3), ≤ 14 daily points,
  no images or attributed strings, values formatted at render time.

### 9.6 Overlays, notifications, alerts, share card

- **Quota warning overlay** (`QuotaWarningAlertOverlayController`): keep the panel; content = `warning`
  triangle 22 pt · headline · `meta` line; background `cardFill` on the system HUD window background
  (drop `.regularMaterial`); radius 16 → 12.
- **Confetti:** existing particles; default palette = provider colors (existing); add Reduce Motion skip
  if missing.
- **Notifications:** system banners; no attachments (unchanged). Copy unchanged.
- **NSAlert:** native; nothing to restyle.
- **Share stats card** (`ShareStatsCardView`, 1200 × 630 export): rebuild on the Calm native palette — dark
  Iris-black background `#0E0D1A` → `#17143A`, the Open Ring mark (white) instead of the three-bar copper
  mark, SF Pro Rounded for the hero figure is replaced by SF Pro semibold tabular, provider rows with
  provider color dots.

### 9.7 App icon

Chosen concept: **A · Open Ring** ([`icon/final-openbar-icon.svg`](icon/final-openbar-icon.svg)). A thick
white ring with a gap at the upper right, and a detached dot sitting in the gap, on an Iris squircle.

Why: its silhouette (a ring with a notch and a dot) survives at 16 px where bars and capsules blur into
generic shapes; the gap reads as "open" and as a quota that refills; it has no chevron and no bar, so it
breaks cleanly from CodexBar; one white foreground works in the macOS 26 Default, Dark, Clear, and Tinted
renditions. Rejected: **B · Split Rails** (two rails; reads as a toggle or generic list at 16 px and keeps
CodexBar's bar motif), **C · Level Capsule** (reads as a battery or thermometer).

Assets: `Icon.icon` (Icon Composer: Iris automatic-gradient fill, `ring.svg` and `dot.svg` layers in one
group, neutral shadow 0.2) → `Scripts/build_icon.sh Icon.icon Icon` → `Icon.icns` (now 0.63 MB, was
1.3 MB) and `Sources/OpenBar/Resources/Icon-classic.icns` (same image for macOS < 26) → `docs/icon.png`
(512 px from the iconset).

### 9.8 Docs site (`docs/index.html`, `docs/site.css`, Tailwind utilities)

- Palette: light `#F7F7F8` / dark `#0B0B10` backgrounds; text `#1D1D1F` / `#F2F2F7`; muted `#6E6E73` /
  `#A1A1AA`; links, focus ring, selection, and the bar accent → Iris (`#5246E0` light, `#A39EFF` dark);
  replace `#0099FF`, `#38BDF8`, `#4FB6C3`, `#FF4055`.
- Type: `-apple-system, "SF Pro Display", Inter, system-ui` headings 600 with −0.02em tracking (web only),
  body 16/1.55.
- Hero: replace the CodexBar-style popover and two-meter glyph with an HTML/CSS (or SVG) rendering of the
  §9.2 menu and the §9.1 glyph. Keep `hero-mockup.svg` laptop artwork if it carries no CodexBar marks;
  otherwise redraw. Hero glow: Iris only (drop orange/teal).
- Feature illustrations: meters use the split motif with provider colors; status illustrations use §2.2.
- Provider directory: logos unchanged; cards `cardFill` style, radius 12.
- Keep every `data-i18n` key; no new strings unless all 23 locales are handled (`check-site-locales`).
- Regenerate `docs/site-utilities.css` with `Scripts/build-site-css.sh`.

### 9.9 Social card (`docs/social.html` → `docs/social.png`, 1200 × 630)

Background `#0B0B10` with one soft Iris glow (no four-color aurora, no teal); Open Ring icon 40 px +
"OpenBar"; headline 60 px semibold in `#F2F2F7` with "in your menu bar." in Iris `#A39EFF`; provider tiles
in `cardFill` style with unchanged logos; provider count from the existing check. Regenerate the PNG at 1×
and run `node Scripts/social-card.mjs --update <png>`, `node Scripts/check-site-locales.mjs`,
`node --test Scripts/test_social_card.mjs` (see `docs/social-card.md`). (This phase already re-rendered the
current card with the new icon so the receipt stays valid.)

### 9.10 CLI, web dashboard, Linux assets

Not app UI, but they carry CodexBar's teal: `Sources/OpenBarCLI/CLIRenderer.swift` (teal meter gradient →
use `OpenBarPalette.ok`/accent values), `Sources/OpenBarCLI/CLIServeWebUI+HTML.swift` (`#49A3B0` fallback
accent → Iris), `Integrations/Linux/icon.svg` (chevron + bars → Open Ring). Output text and behavior stay
the same.

---

## 10. Accessibility

- **VoiceOver:** each menu card is one element group: "Claude, Max. Session, 62 percent left, resets in
  2 hours 14 minutes, on pace. Weekly …". Meters expose `accessibilityValue` (existing
  `UsageProgressBar` value strings) and markers. Tone symbols are labeled with the tone words already in
  the text, so they are `accessibilityHidden`. Switcher segments are buttons with the provider name and
  "selected" trait. Provider rows in the sidebar keep their existing combined accessibility label
  (`SettingsSidebarProviderRow.accessibilityLabel`, which includes the status).
  The status item keeps its accessibility label from `MenuBarLayoutRenderedTitle`.
- **Text size:** menus and Settings use text styles (§3) so system text-size handling applies where macOS
  supports it; widgets follow WidgetKit's sizing. Never clip: lane rows wrap the detail row to two lines
  before truncating the reset text.
- **Increase Contrast:** every token has an HC variant (resolved through
  `accessibilityHighContrast*` appearances); cards add the `cardStroke` hairline; meter tracks rise to
  28–32 %; the glyph track rises to 45 %. Check `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`
  only where the appearance does not already carry it (AppKit layers drawn outside the view tree).
- **Reduce Transparency:** cards stay flat fills (no change needed); the Settings sidebar material
  follows the system; the docs site honors `prefers-reduced-transparency` by dropping backdrop blur.
- **Reduce Motion:** loading patterns become static; confetti is skipped; no other motion exists.
- **Differentiate without color:** tone symbols (§2.2), chart legends and labels (§8), "selected" uses
  fill + white text, not a hue change alone.
- **Keyboard:** menus are native; the switcher keeps its existing arrow-key handling; Settings keeps full
  keyboard navigation and search focus (⌘F).

---

## 11. Performance budget

These are acceptance criteria. Every implementer checks their surface with the render gallery (visual)
and reports the view-level checks below. **Only the lead or the perf agent runs the scripted measurement**
because it launches the app:

```sh
~/Library/Caches/openbar-research/scripts/trials.sh <App.app> <label> <N>
```

### App-wide (measured by lead/perf agent on a release build, synthetic config, Keychain disabled)

| Metric | Budget (today) |
| --- | --- |
| Settled footprint | **< 90 MB** (≈ 94 MB) |
| Peak footprint | **< 150 MB** (≈ 160 MB) |
| Owned graphics memory (IOSurface/IOAccelerator/Metal regions attributed to the app) | **0** |
| New idle timers, display links, or repeating tasks | **0** |

### Per surface (checked by each implementer in code review and the gallery)

| Surface | Budget |
| --- | --- |
| Menu bar glyph | Template `NSImage` only; ≤ 64 cached states (~5 KB each); drawn only when quantized inputs, appearance, or status change; no timer outside an active loading pattern. |
| Menu | One hosting view per section **that owns a submenu or click action**; target ≤ 3 hosting views per provider (usage card, credits/extra card, cost card). Zero `NSVisualEffectView`s inside rows. Meters are plain shapes. No `.animation`/`TimelineView`/timers in rows. ≤ 10 distinct SF Symbols. No shadows, materials, or blend modes. Countdown text is computed at open/rebuild only. |
| Submenus | Lazy hydration (existing); one hosting view per submenu; one batched `Path` per series; no per-bar views. |
| Settings | HStack shell (§9.4); exactly one `NSVisualEffectView` (sidebar); monochrome sidebar symbols (no chip plates); no per-row materials or shadows; `List` stays lazy. |
| Widgets | No `Canvas`; entries ≤ 3 lanes and ≤ 14 daily points; no images in entries; reload timelines only when data changes. |
| Docs site | No new raster hero images; CSS bundle not larger than today (56 KB authored + 10 KB utilities). |

### Measured view costs (offscreen benches in [`bench/`](bench/), phys_footprint, 3 runs)

| Shape (12 provider cards, 4 lanes each) | KiB per card |
| --- | ---: |
| One hosting view, plain-shape meters | ≈ 950 |
| Four hosting views per card (today's sectioning) | ≈ 1 090 |
| One hosting view, CGImage meters (today's `UsageProgressBar` technique) | ≈ 1 165 |
| One hosting view, no meters | ≈ 830 |

So: each hosting view removed saves ≈ 35 KiB; a plain-shape meter costs ≈ 30 KiB, a CGImage meter
≈ 84 KiB at 280 pt wide. Inside SwiftUI, **plain shapes are cheaper than pre-rendered bitmaps**; "static
drawing" means *no animation and no per-frame work*, not "always a bitmap". Bitmaps stay right for the
status item (it requires an `NSImage`) and for AppKit layers. No variant committed graphics memory (no
~97 MB Metal jump), so plain `RoundedRectangle`/`Capsule` fills are safe; keep away from `Canvas`, Swift
Charts, `.drawingGroup`, `.compositingGroup`, blend modes, and gradient masks.

### View-level opportunities found during design (for the implementers and the perf agent)

1. `UsageProgressBar` renders a CGImage per meter per render through a `GeometryReader`; switch to plain
   shapes with gap geometry (≈ −50 KiB per meter, less work per menu open).
2. Credits / Extra usage / Cost sections are separate hosting views even when they own no submenu; merge
   them (≈ −35 KiB each, fewer height measurements).
3. `MenuRowContainerView` creates an `NSVisualEffectView(.selection)` per highlighted row, and
   `PersistentRefreshMenuView` always owns one; replace with a plain layer or SwiftUI fill.
4. `NavigationSplitView` Settings shell → HStack (≈ −11 MB at first open, ≈ −16 MB after navigation in the
   bench).
5. Settings sidebar `SettingsIconChip` colored plates → monochrome symbols (fewer layers and symbol
   renditions; part of the CoreSVG cache noted in `docs/research/settings-layout-heap-2026-10-24.md`).
6. About hero: remove the hover scale animation and accent shadow (removes an offscreen shadow pass).
7. Burndown widget `Canvas` → `Path` (widget process).
8. `Icon.icns` shrank from 1.3 MB to 0.63 MB with the vector layers; `Icon-classic.icns` likewise.
9. Out of view scope, for the perf agent: provider SVGs decode through CoreSVG and stay in its global cache;
   pre-rasterizing the 16/18-pt template logos at build time could cut that cache.

---

## 12. Render gallery

A verification tool for every implementer: it renders **real** OpenBar views with synthetic data to PNGs
and writes an `index.html` contact sheet. It is inert unless asked for, runs in the scrubbed test
environment (Keychain access suppressed, no network, no status items, no OpenBar.app launch), and asserts
nothing — it is not a unit test.

```sh
./Scripts/render_gallery.sh                         # all sections → .build/render-gallery/index.html
./Scripts/render_gallery.sh /tmp/gallery menu,widgets  # subset: tokens, menubar, menu, settings, widgets
```

How it works: `Tests/OpenBarTests/RenderGallery/DesignRenderGallery.swift` is an env-gated suite
(`OPENBAR_RENDER_GALLERY_DIR`, optional `OPENBAR_RENDER_GALLERY_ONLY`). It lives in the test target because
that is the only module that can import both `OpenBar` and `OpenBarWidget`, and because `SettingsStore` /
`UsageStore` are only safe to construct there (test stores, no app-group migration, no provider detection).
It refuses to run unless `OPENBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1`. Views are hosted in an offscreen
window and drawn into an explicit 2× sRGB bitmap, so AppKit-backed controls (Form, Toggle, Picker,
`NSStackView`) render like the app and colors match the tokens. Limits: system materials (menu glass,
sidebar material, emphasized selection plates) cannot be captured offscreen and show as an opaque backdrop,
the window background, or a solid fill; titled windows are occluded offscreen, so Settings is captured
without its titlebar and toolbar;
Increase Contrast is a system appearance an offscreen window cannot adopt, so the tokens section renders
the raw high-contrast values instead. Appearances: light and dark.

| Section file | Renders | Owner |
| --- | --- | --- |
| `DesignRenderGallery.swift` | writer, capture, tokens and type specimen | lead |
| `+Fixtures.swift` | synthetic Claude / Codex / Cursor data (normal, warning, critical+stale) | Menu agent |
| `+MenuBar.swift` | glyph states (Meter bars, Critters) real size and 4×, Icon & percent | Glyph agent |
| `+Menu.swift` | provider cards, switcher, composite | Menu agent |
| `+Settings.swift` | Settings content (sidebar + detail, no titlebar) per pane | Settings agent |
| `+Widgets.swift` | usage tile small/medium/large, accented mode | Widgets agent |

Rules: add a section file for a new surface instead of editing another agent's file; use fixed dates
(`GalleryFixtures.now`) and fictitious data; keep captures deterministic. The menu backdrop is an opaque
stand-in for menu glass, so judge layout and contrast, not translucency. Look at your PNGs before and after
every change and attach the before/after pair to your report.

---

## 13. Work split

Four implementation agents run in parallel after this commit. Each owns its files exclusively. Each uses
`model: opus`. Each runs focused tests for the suites that cover its files (`make test-fast
FILTER='…'`), formats and lints only touched files while iterating, runs `make check` once before handoff,
renders its gallery sections before/after, and does **not** write new unit tests. If an existing test pins
old literal geometry or colors of a file you own, update that test's expectation (do not delete the test)
and say so in the report.

### Agents and file ownership

**1. Glyph & Charts agent** — static drawing.
- Menu bar: `IconRenderer.swift`, `MenuBarLayoutRenderer.swift`, `MenuBarTokensSparkline.swift`,
  `LoadingPattern.swift`, drawing helpers in `StatusItemController+Animation.swift` (status overlays,
  brand overlay, quota warning flash, high-contrast title; not its scheduling).
- Submenu charts: `CostHistoryChartMenuView.swift`, `CostHistoryMenuScrollView.swift`,
  `CreditsHistoryChartMenuView.swift`, `DailyBarChart.swift`, `PlanUtilizationHistoryChartMenuView.swift`,
  `QuotaBurndownChartMenuView.swift`, `UsageBreakdownChartMenuView.swift`, `StorageBreakdownMenuView.swift`,
  `StatusComponentsMenuView.swift`, `ChartBarPath.swift`, `ChartAxisLabelLayout.swift`.
- Dashboard and window charts: `SpendDashboardTrendPanel.swift`, `SpendTrendChartModel.swift` (palette
  only), `SpendActivityHeatmap.swift`, `SpendActivityPalette.swift`, `SpendActivityScrollableGrid.swift`,
  `SpendActivityMonthLabelsLayout.swift`, `Providers/OpenAI/OpenAILiveUsageChart.swift`.
- Overlays: `QuotaWarningAlertOverlayController.swift`, `ScreenConfettiOverlayController.swift`,
  `ShareStatsCardView.swift`, `ShareStatsWindowController.swift`.
- CLI identity: `Sources/OpenBarCLI/CLIRenderer.swift`, `Sources/OpenBarCLI/CLIServeWebUI+HTML.swift`.
- Gallery: `+MenuBar.swift`, new `+Charts.swift`.

**2. Menu agent** — cards, rows, switcher, and the menu's hosting structure.
- `MenuCardView.swift` and every `MenuCardView+*.swift`, `MenuCardMetricRow.swift`,
  `MenuCardCompactAccountRow.swift`, `MenuCardPlanPresentation.swift`, `UsageMenuCardLayout.swift`,
  `UsageMenuCardHeaderAndUsageSectionView.swift`, `UsageProgressBar.swift`, `MenuHighlightStyle.swift`,
  `MenuInlineCodeText.swift`, `ClickToCopyOverlay.swift`.
- In-card content: `InlineUsageDashboardContent.swift`, `MenuUsageBarStrip.swift`,
  `ProviderMenuChartContent.swift`, `ProviderThroughputSection.swift`, `ProviderDetailSectionsContent.swift`.
- Switchers: `ProviderSwitcherButtons.swift`, `StatusItemController+SwitcherViews.swift`,
  `CodexAccountSwitcherView.swift`, `Providers/Claude/ClaudeSwapAccountSwitcherView.swift`.
- Menu structure: `StatusItemController+Menu.swift` (section assembly, separators, merging),
  `StatusItemController+MenuCardItems.swift`, `StatusItemController+MenuPresentation.swift`,
  `StatusItemController+MenuTypes.swift`, `StatusItemController+CostMenuCard.swift`,
  `StatusItemController+StorageMenuCard.swift`, `StatusItemController+MenuTextRows.swift`,
  `StatusItemController+PersistentRefreshMenuItem.swift`, `PersistentRefreshRowMetrics.swift`,
  `StatusItemController+AgentSessions.swift` (row view), `StatusItemController+OverviewSpend.swift`,
  `StatusItemController+UserPlugins.swift` (card view), `StatusItemController+CodexStackedMenu.swift`,
  `Providers/Claude/StatusItemController+ClaudeSwapMenu.swift`, `StatusItemController+CompactAccountMenu.swift`,
  `FleetAccountMenuProjection.swift` (card view).
- Gallery: `+Menu.swift`, `+Fixtures.swift`.
- Must not change menu behavior: item order, submenus, click targets, keyboard handling, recycling,
  height caching, or Overview rules. Merging sections is allowed only where no submenu or action moves.

**3. Settings agent** — window shell, panes, editors, localization owner.
- Shell: `PreferencesView.swift`, `PreferencesSidebar.swift`, `SettingsSidebarSizing.swift`,
  `SidebarResizeHandle.swift`, `SettingsWindowController.swift` (only what the shell change needs),
  `PreferencesSelection.swift` (no behavior change).
- Panes and rows: `PreferencesComponents.swift`, every `Preferences*Pane.swift`,
  `PreferencesProvider*.swift`, `PreferencesCodexAccountsSection.swift`,
  `PreferencesHTTPServerSection.swift`, `PreferencesTransferSection.swift`, `PreferencesAcknowledgements.swift`,
  `PreferencesAboutPane.swift`, `PreferencesMenuPicker.swift`, `ProviderAccentColorSettingsView.swift`,
  `ProviderMenuBarPercentWindowSettingsView.swift`, `QuotaWarningSettingsViews.swift`,
  `MenuBarLayoutEditor*.swift`, `MenuBarLayoutConditionalEditor.swift`, `UnifiedIconSource.swift`.
- Spend dashboard layout (not its charts): `PreferencesSpendDashboardPane.swift`,
  `SpendDashboardSummary.swift`, `SpendDashboardProviderBreakdown.swift`, `SpendSessionPerformanceView.swift`,
  `SpendSessionToolActivityView.swift`, `SpendTimeZoneControls.swift`.
- Other windows: `ProviderAccountUsageOverview.swift`, `CodexWorkspacesInspectorView.swift`,
  `SessionUsageBrowser.swift`, `Providers/OpenAI/OpenAILiveUsageView.swift`.
- **Owns `Sources/OpenBar/Resources/*.lproj`.** Others avoid new strings; if one is unavoidable, they send
  the key, English text, and context to the Settings agent through the lead.
- Gallery: `+Settings.swift`.

**4. Widgets & Web agent.**
- Widgets: everything in `Sources/OpenBarWidget/` (including replacing `BurnChartCanvas`), and
  `WidgetExtension/` only if needed. Owns `Sources/OpenBarWidget/Resources/*.lproj` and
  `Scripts/widget-localization-keys.json` under the same no-new-strings rule.
- Web: `docs/index.html`, `docs/site.css`, `docs/site.js` (theme only), `docs/site-utilities.css` (via
  `Scripts/build-site-css.sh`), `docs/hero-mockup.svg`, `docs/images/menubar/*`, `docs/features/*`,
  `docs/social.html`, `docs/social.png`, `docs/social-card.json`, `README.md` (badges, images), the
  website widget screenshots `docs/widgets/0*.png` (re-rendered from the gallery), `docs/openbar.png`
  (replace with a gallery composite or remove if unreferenced), `assets/icon.svg`,
  `Integrations/Linux/icon.svg`.
- Gallery: `+Widgets.swift`.

**Lead (not an agent):** `docs/design/**`, design tokens (`OpenBarDesignTokens.swift`, `OpenBarTheme.swift`,
`WidgetTheme.swift`), `DesignRenderGallery.swift`, `Scripts/render_gallery.sh`, the app icon assets, merges,
and `trials.sh` runs. Agents that need a new token add it in their own file as an `extension` (for
example `Sources/OpenBar/Design/OpenBarTheme+Menu.swift`) and flag it; the lead folds it into the token file.

**Off limits to all four** (perf agent or unchanged): `OpenbarApp.swift`, `UsageStore*`, `SettingsStore*`,
refresh/scheduling code (including `StatusItemController+CountdownRefresh.swift` and the scheduling parts of
`+Animation.swift`), `Package.swift`, `OpenBarCore` behavior, provider descriptors and their colors.

### Ordering

1. **Now:** this commit (tokens, gallery, icon, spec, mockups).
2. **Parallel:** all four agents start from it. The Widgets & Web agent does widgets, site, and social card
   first, and leaves screenshots that depend on other agents (README image, `docs/widgets/*.png`,
   `docs/openbar.png`) for its last step.
3. **Merge order:** Glyph & Charts → Menu → Settings → Widgets & Web. After each merge the lead re-runs the
   gallery and focused tests; after the Menu and Settings merges the lead runs `trials.sh` against the
   §11 budget.
4. **Last:** Widgets & Web re-renders gallery-based screenshots and the social card on the merged tree.

### Acceptance per agent

- Before/after gallery PNGs for every owned surface, light and dark (and Increase Contrast for glyphs).
- No `Canvas`, `import Charts`, `.drawingGroup`, `.compositingGroup`, blend modes, new materials, shadows,
  timers, or `.animation` in owned views (`rg` output in the report).
- No behavior, data, settings, or string changes beyond those listed here (diff summary in the report).
- Focused tests pass; `make check` passes.

---

## 14. Open questions for the owner

1. **Default menu bar style.** The default is still *Critters* (CodexBar's signature). Flip the default to
   *Meter bars* (the new OpenBar glyph) for users who never chose a style? This changes the default of an
   existing setting (`menuBarHidesCritters` default `false` → `true`), not its meaning. Recommended: yes.
2. **Meter colors.** Meters keep the provider color because the existing per-provider accent setting says
   it colors "usage bars, charts, and switcher tab". Iris on every meter would be calmer but would change
   that setting's meaning and its string in 23 locales. Recommended: keep provider colors.
3. **System accent.** Follow the user's explicit macOS accent when they set one (native behavior), Iris
   otherwise? Recommended: yes.
4. **Tone thresholds.** Unify on warning ≤ 25 % / critical ≤ 10 % remaining across menu, compact account
   rows (today amber < 50 %, red < 10 %), and widgets (today red ≤ 10 %)? Recommended: yes.
5. **Settings sidebar look.** The lighter HStack shell has an edge-to-edge sidebar instead of macOS 26's
   floating glass sidebar. Accept it for ≈ 11–16 MB, or use `NSSplitViewController` (floating sidebar,
   ≈ 8–13 MB saved)?
6. **Attribution.** Keep "Based on CodexBar by Peter Steinberger" as a plain About link and the README
   "Fork of CodexBar" badge (restyled), or move the credit to Acknowledgements only? The MIT license only
   requires the notice in `LICENSE`. Recommended: keep a plain About link, drop the colored README badge.
7. **Codex's shipped color.** Codex's provider color `#49A3B0` is CodexBar's teal. It is provider data,
   so this spec keeps it. Change the shipped default to OpenAI's own palette (for example `#10A37F`)?
