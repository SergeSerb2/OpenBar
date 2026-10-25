---
summary: "Inventory of every OpenBar visual surface, the files that draw it, and which ones carry CodexBar identity."
read_when:
  - Planning or reviewing redesign work
  - Finding which file draws a surface
---

# Visual surface inventory

Audit of `main` at `34ca27682` (2026-10-24). Paths are repo-relative; `Sources/OpenBar/` is omitted where
the file is in the app target. **Identity** marks a visible CodexBar marker: the chevron-plus-meter icon,
the critter/two-meter glyph vocabulary, CodexBar's teal (`#49A3B0` is also Codex's shipped provider color)
and red meter marker, or an explicit "CodexBar" string. Provider logos are third-party identity and stay
unchanged. The spec for each surface is in [`README.md`](README.md) §9.

Legend: **●** carries CodexBar identity · **◐** carries it conditionally (for example when Codex's teal is
the tint) · **○** no CodexBar identity.

## 1. Menu bar status item

| Surface | Files (key code) | What it draws | Identity |
| --- | --- | --- | --- |
| Style setting | `SettingsStore+MenuPreferences.swift:4` `MenuBarIconStyle` | `critters` (default), `bars` ("Meter bars"), `iconAndPercent` | ● default is critters |
| Display modes | `MenuBarDisplayMode.swift:4` | percent / pace / both / resetTime text beside the logo | ○ |
| Layout presets & tokens | `MenuBarLayout.swift:514` `MenuBarLayoutToken`, `:898` presets, `:943` sizes, `:953` gaps | icon, providerName, percent, pace, usageBar, progressBar, reset countdown/absolute, runsOut, balance, cost, tokensSparkline, separators, conditionals | ○ (meter tokens ◐) |
| Quota meter glyph | `IconRenderer.swift:142` `makeIcon`, `:1138` `renderImage` | 18 × 18 pt template; two outlined capsules (track 28 %, stroke 44 %, 1 pt outline), primary 6 pt / secondary 4 pt, 15 pt wide | ● two-meter vocabulary |
| Critters | `IconRenderer.swift:228` Codex face+hat, `:290` Claude crab, `:371` Gemini stars, `:499` Antigravity, `:511` Factory, `:618` Warp, `:669` Grok; flags in `OpenBarCore/Providers/ProviderUsagePresentation.swift:151` | provider faces on the meters | ● |
| Status overlays | `IconRenderer.swift:1063`, `StatusItemController+Animation.swift:1358`, `:1377` | minor dot 4 × 4, major exclamation 2 × 6 + 2 × 2 | ○ |
| Loading animations | `LoadingPattern.swift:3`; `StatusItemController+Animation.swift:340`, `:1333`; morph `IconRenderer.swift:894`, `:955` | knightRider, cylon, outsideIn, race, pulse, unbraid knot→meters; blink/wiggle/tilt effects (`StatusItemController.swift:339`) | ● critter motion, knot morph |
| Icon & percent / custom layouts | `MenuBarLayoutRenderer.swift:324` `render`, `:422`, `:673`; fonts `:452`, sizes `:1248`, baselines `:307` | provider logo + attributed text; stacked 9–11 pt lines | ○ |
| Progress-bar token | `MenuBarLayoutRenderer.swift:1328`, `:1394` | five segments, 2 pt gaps, 32/36/44 pt | ◐ meter + tint |
| Character usage bar | `MenuBarLayoutRenderer.swift:799` | text meter | ● meter vocabulary |
| Pace text color | `MenuBarLayoutRenderer.swift:731` | `systemGreen` / `systemRed` | ○ (not colorblind-safe) |
| Tokens sparkline | `MenuBarTokensSparkline.swift:25` | template bar strip, baseline 22 % | ○ |
| Merged two-provider item | `MenuBarLayoutRenderer.swift:385`; `StatusItemController+MenuBarLayout.swift:75`, `:125`, `:302`; `MergedIconPresentation.swift:26` | two stacked layout rows | ◐ |
| Quota warning flash | `StatusItemController+Animation.swift:642` | red-tinted non-template image (22 %/28 %) | ○ |
| High-contrast inactive title | `StatusItemController+Animation.swift:714` | label-color title | ○ |
| Formatted values | `MenuBarDisplayText.swift:38`, `:44`, `:113`, `:164`; `IconRemainingResolver.swift` | text only | ○ |
| Countdown scheduling | `StatusItemController+CountdownRefresh.swift` | boundary-scheduled redraws (no per-second tick) | — |

## 2. Status menu

| Surface | Files | What it draws | Identity |
| --- | --- | --- | --- |
| Menu construction | `StatusItemController+Menu.swift:228` `populateMenu`, `:815`, `:857`, `:1297` `addMenuCardSections` | switcher, card sections as separate items, native action rows, separators | ○ |
| Provider card | `MenuCardView.swift:219` `UsageMenuCardView` (+ `MenuCardView+*.swift`) | header, divider, metrics, credits, cost, details; 12 pt stacks | ◐ provider tint |
| Card geometry | `UsageMenuCardLayout.swift:3` | padding 20, gaps 4–12 | ○ |
| Header & error subtitle | `MenuCardView.swift:342`; `MenuCardPlanPresentation.swift:9` | name headline, email subheadline, footnote updated/error/plan, copy button | ○ |
| Section rows | `MenuCardView.swift:586` header, `:615`/`:734` usage, `:764`/`:801` credits, `:849` extra usage; `UsageMenuCardHeaderAndUsageSectionView.swift` | independently hosted sections | ◐ |
| Metric row | `MenuCardMetricRow.swift:12`; `UsageMenuCardHeaderAndUsageSectionView.swift:33` | title + % + reset, bar, pace text | ◐ |
| Progress bar | `UsageProgressBar.swift:70` (CPU CGImage per bar), `:110` draw | 6 pt track/fill, warning punch markers, workday ticks, green/red striped pace tip | ◐ teal fill; ○ red/green pace not CVD-safe |
| Cost section | `MenuCardView+Costs.swift:10`; `StatusItemController+CostMenuCard.swift:5`, `:76`, `:138` | cost lines, native fallback title | ○ |
| Token usage & notes | `MenuCardView.swift:509`, `:568` | footnotes | ○ |
| Reset credits | `MenuCardView+CodexResetCredits.swift:108` | credit rows, symbols | ○ |
| Compact account rows | `MenuCardCompactAccountRow.swift:90`, `:175` | 56 × 4 mini bar, yellow/orange/red at 50 %/10 % | ◐ |
| Overview rows & spend | `StatusItemController+MenuTypes.swift:45`; `StatusItemController+OverviewSpend.swift:99` | compact cards, rounded title2 total | ○ |
| Plugin card | `StatusItemController+UserPlugins.swift:283` | 26 pt tinted plate, white glyph | ○ |
| Fleet account card | `FleetAccountMenuProjection.swift:101` | reused card | ◐ |
| Detail sections | `ProviderDetailSectionsContent.swift:9`, `:87`, `:161` | rows, 58 pt line chart, green/orange/red severity | ◐ |
| Inline dashboard | `InlineUsageDashboardContent.swift:698`, `:779`, `:802`; `MenuUsageBarStrip.swift:88` | KPI grid, mini bars | ◐ |
| Chart picker & throughput | `ProviderMenuChartContent.swift:89`, `:166` (unit palette `:55`); `ProviderThroughputSection.swift:71` | 44 pt strips | ○ |
| Native rows | `StatusItemController+Menu.swift:873`–`:953`; `+MenuTextRows.swift:15`; `+MenuPresentation.swift:49`; `+AgentSessions.swift:6`; `+StorageMenuCard.swift:13` | AppKit titles, subtitles, symbols | ○ |
| Hosted row container & selection | `StatusItemController+MenuPresentation.swift:175` `MenuRowContainerView`, `:477` `NSVisualEffectView(.selection)`, `:848`; `MenuHighlightStyle.swift:11` | selection plate radius 6, accent | ○ |
| Persistent Refresh row | `StatusItemController+PersistentRefreshMenuItem.swift:8`; `+MenuPresentation.swift:550` (own `NSVisualEffectView`); `PersistentRefreshRowMetrics.swift:4` | 24 pt row | ○ |
| Codex / Claude-swap groups | `StatusItemController+CodexStackedMenu.swift:61`, `:108`; `Providers/Claude/StatusItemController+ClaudeSwapMenu.swift:5`, `:135`; `StatusItemController+CompactAccountMenu.swift:101`, `:185` | grouped cards, headings | ○ |
| Menu plumbing (no new design) | `+MenuCardItems.swift:32`, `+MenuCardRecycling.swift`, `+MenuReconcile.swift:41`, `+HostedSubmenus.swift:113`, `+UsageHistoryMenu.swift:5`, `StatusItemMenu.swift:18`, `+MenuAppearance.swift:5` | hosting, recycling, sizing | — |

## 3. Switchers

| Surface | Files | What it draws | Identity |
| --- | --- | --- | --- |
| Provider switcher | `StatusItemController+SwitcherViews.swift:10` (buttons `:123`, style `:702`, quota strips `:649`, hover `:728`) | segments radius 6, accent fill + white, 2 pt provider-color strips | ◐ |
| Toggle buttons | `ProviderSwitcherButtons.swift:3`, `:24`, `:148` | padded, inline, stacked icon+title | ○ |
| Token-account switcher | `StatusItemController+SwitcherViews.swift:1190` | 26 pt rows | ○ |
| Codex account switcher | `CodexAccountSwitcherView.swift:4` | 26 pt rows, radius 6 | ○ |
| Claude-swap switcher | `Providers/Claude/ClaudeSwapAccountSwitcherView.swift:4` | radius 6, accent plate | ○ |
| Rows option | `SettingsStore+MenuPreferences.swift:18` `SwitcherRowsOption` | icons / weekly progress | — |

## 4. Submenu charts

Hosted from `StatusItemController+HostedSubmenus.swift` (usage `:389`, credits `:417`, costs `:444`, storage
`:513`, status `:562`).

| Surface | Files | Notes | Identity |
| --- | --- | --- | --- |
| Cost history | `CostHistoryChartMenuView.swift:130` (metrics `:399`, accent `:641`); `CostHistoryMenuScrollView.swift:6` | 130 pt chart, breakdown rows | ◐ |
| Credits history | `CreditsHistoryChartMenuView.swift:27` | **hardcoded teal** `(73,163,176)` at `:102` | ● |
| Daily bar chart | `DailyBarChart.swift:51`, `:170`, `:195` | batched paths | ○ |
| Plan utilization | `PlanUtilizationHistoryChartMenuView.swift:94` (layout `:6`, color `:291`) | bars, dashed reset rule | ◐ |
| Quota burndown | `QuotaBurndownChartMenuView.swift:55`, `:176` | ideal dash [4,3], 0.5 pt grid | ◐ |
| Usage breakdown | `UsageBreakdownChartMenuView.swift:44` (palette `:270`) | stacked series, legend dots | ○ |
| Storage breakdown | `StorageBreakdownMenuView.swift:121` (palette `:39`) | segmented strip | ○ |
| Status components | `StatusComponentsMenuView.swift:39` (green/yellow/red `:8`) | dots and labels | ○ |
| Shared | `ChartBarPath.swift:5`, `ChartAxisLabelLayout.swift:3` | radius 2; caption2 axes | ○ |

## 5. Usage & Spend dashboard (Settings pane)

| Surface | Files | Identity |
| --- | --- | --- |
| Pane root, status capsule, empty/error | `PreferencesSpendDashboardPane.swift:131`, `:223`, `:270`, `:443` | ○ |
| Currency sections, panels | `PreferencesSpendDashboardPane.swift:690`, `:761`, `:1389` (radius 12, text-background 74 %) | ○ |
| Summary totals | `SpendDashboardSummary.swift:8`, `:107`, `:126` | ○ |
| Provider breakdown | `SpendDashboardProviderBreakdown.swift:105`, `:279` | ○ (brand artwork) |
| Trend panel and chart | `SpendDashboardTrendPanel.swift:12`, `:209`, `:470`, `:486`; palette `SpendTrendChartModel.swift:259` | ◐ |
| Activity heatmap | `SpendActivityHeatmap.swift:366`, `:491`, `:750`; GitHub-green ramp `SpendActivityPalette.swift:7`; `SpendActivityScrollableGrid.swift`; `SpendActivityMonthLabelsLayout.swift` | ○ |
| Projects, ledger, sessions, filters | `PreferencesSpendDashboardPane.swift:841`, `:929`, `:956`, `:1106`, `:1192`; `SpendTimeZoneControls.swift:8` | ○ |
| Session performance & tools | `SpendSessionPerformanceView.swift:8`; `SpendSessionToolActivityView.swift:31` | ○ |

## 6. Settings window

| Surface | Files | Identity |
| --- | --- | --- |
| Window | `SettingsWindowController.swift:87` (880 × 620, min 800 × 540 in `PreferencesView.swift:20`) | ○ |
| Shell | `PreferencesView.swift:98`; macOS 26 `NavigationSplitView` `:132`; legacy HStack `:166`; materials `:523`, `:545`, `:614`; history buttons `:493` | ○ |
| Sidebar | `PreferencesSidebar.swift:16`; pane rows `:181` with colored `SettingsIconChip` (`PreferencesComponents.swift:13`); About row `:196` (app icon); provider rows `:226`; search `:304`; sort `:371`; `SidebarResizeHandle.swift:47`; `SettingsSidebarSizing.swift` | ● About row shows the app icon |
| Components | `PreferencesComponents.swift:39`, `:56`, `:80`, `:176`, `:218`; `PreferencesMenuPicker.swift:22`; `TerminalApp.swift:44` | ○ |
| Panes | `PreferencesGeneralPane.swift:90`, `PreferencesMenuBarPane.swift:26` (●/◐ live glyph previews), `PreferencesMenuPane.swift:9`, `PreferencesNotificationsPane.swift:7`, `PreferencesProvidersPane.swift:55`, `PreferencesAdvancedPane.swift:11`, `PreferencesHooksPane.swift:8`, `PreferencesICloudSyncPane.swift:12`, `PreferencesPluginsPane.swift:16`, `PreferencesDebugPane.swift:30` (● animation previews) | mostly ○ |
| Provider detail | `PreferencesProviderDetailView.swift:135`, header `:334`, icon `:379`, metrics `:473`; rows `PreferencesProviderSettingsRows.swift`; `PreferencesProviderDirectoryList.swift`; `PreferencesProviderErrorView.swift`; `PreferencesProviderModelLimits.swift`; `PreferencesCodexAccountsSection.swift`; `ProviderAccentColorSettingsView.swift:27` (◐ editing Codex's teal); `ProviderMenuBarPercentWindowSettingsView.swift`; `QuotaWarningSettingsViews.swift`; `PreferencesHTTPServerSection.swift`; `PreferencesTransferSection.swift`; `UnifiedIconSource.swift` | ○/◐ |
| Menu bar layout editor | `MenuBarLayoutEditor.swift:381`, chips `:840`, `MenuBarLayoutEditorChip.swift:47`, preview `:941`, options `:1290`; `MenuBarLayoutConditionalEditor.swift:60` | ● previews |

## 7. About, onboarding, consent, alerts

| Surface | Files | Identity |
| --- | --- | --- |
| About hero | `PreferencesAboutPane.swift:133` (icon 92 pt, hover scale 1.05, accent shadow) | ● app icon |
| About links | `PreferencesAboutPane.swift:45`; "Based on CodexBar by Peter Steinberger" at `:53` | ● explicit credit (keep as attribution) |
| Updates | `PreferencesAboutPane.swift:103`, `:195`, `:231` | ○ |
| Acknowledgements | `PreferencesAcknowledgements.swift:60`, `:81`, `:128` | ○ |
| Onboarding | not found (first-run detection only: `SettingsStore+ProviderDetection.swift:16`) | — |
| Consent | `AdaptiveActivityConsentPresenter.swift:17` (`NSAlert`) | ○ |
| Alerts | `NSAlert` in `KeychainPromptCoordinator.swift:188`, `MenuBarVisibilityWatcher.swift:199`, `CursorLoginBrowserRouter.swift:89`, `CursorLoginAccountSelector.swift:116`, `ManagedCodexAccountService.swift:162`, `Providers/VertexAI/VertexAILoginFlow.swift:9`, `Providers/Copilot/CopilotLoginFlow.swift:21`/`:44`/`:90`/`:106`/`:116`, `PreferencesProvidersPane.swift:612`, `StatusItemController+Actions.swift:886`/`:896`; SwiftUI alerts in `PreferencesProvidersPane.swift:132`, `PreferencesPluginsPane.swift:80`/`:98`, `PreferencesTransferSection.swift:26` | ○ (native; show app icon) |

## 8. Notifications, overlays, auxiliary windows

| Surface | Files | Identity |
| --- | --- | --- |
| Notifications | `AppNotifications.swift:73`; copy in `SessionQuotaNotifications.swift`, `LimitResetNotifications.swift`, `UsageStore+CredentialNotifications.swift:83`, `CodexResetCreditExpiryNotifier.swift`, `HomebrewUpdateNotifier.swift:90`, `PredictivePaceWarnings.swift` (no attachments) | ○ |
| Quota warning overlay | `QuotaWarningAlertOverlayController.swift:42`, `:137` (orange symbol, regular material, radius 16) | ○ |
| Confetti | `ScreenConfettiOverlayController.swift:13`, `:145` (CA particles; provider palettes) | ◐ Codex palette |
| Share stats card | `ShareStatsCardView.swift:24` (1200 × 630, brown/cream/copper, three-bar mark `:362`); `ShareStatsRenderer.swift:6`; `ShareStatsWindowController.swift:19` | ○ (own look, to restyle) |
| Overlays (no visuals) | `ClickToCopyOverlay.swift`, `SessionUsageMenuAction.swift` | — |
| Buy credits window | `OpenAICreditsPurchaseWindowController.swift` (remote WebKit) | ○ |
| Codex workspaces inspector | `CodexWorkspacesInspectorView.swift:8`; `CodexWorkspacesNavigation.swift:31` | ○ |
| Account usage overview | `ProviderAccountUsageOverview.swift:44` | ○ |
| Session usage browser | `SessionUsageBrowser.swift:105` | ○ |
| OpenAI live usage | `Providers/OpenAI/OpenAILiveUsageNavigation.swift:24`, `OpenAILiveUsageView.swift:8`, `OpenAILiveUsageChart.swift:47` | ○ |
| Sparkle | `OpenbarApp.swift:191` (standard driver, no custom UI) | ○ |

## 9. Widgets (`Sources/OpenBarWidget`, depends on `OpenBarCore` only)

| Widget kind | Families | Views | Identity |
| --- | --- | --- | --- |
| `OpenBarSwitcherWidget` | S, M, L | `OpenBarWidgetViews.swift:84`, pager `:247` | ◐ |
| `OpenBarUsageWidget` | S, M, L | `OpenBarWidgetViews.swift:19`; `WidgetTiles.swift:72` `UsageTile` | ◐ |
| `OpenBarHistoryWidget` | M, L | `OpenBarWidgetViews.swift:45`, `:553`, chart `:599`; colors `:693` | ◐ |
| `OpenBarCompactWidget` | S | `OpenBarWidgetViews.swift:64`, `:119` | ○ |
| `OpenBarBurnDownWidget` | M | `BurnDownWidgetViews.swift:11`; **SwiftUI `Canvas`** `BurnChartCanvas` `:320`; own theme `:533`, palette `:607` | ○ (memory finding) |
| `OpenBarCombinedBurnDownWidget` | M | `CombinedBurnDownWidgetViews.swift:11`, `:130` (uses the same `Canvas`) | ○ |
| `OpenBarAccountUsageWidget` | S, M, L | `OpenBarAccountUsageWidget.swift:133` | ◐ |
| `OpenBarAccountsWidget` | M, L | `OpenBarAccountUsageWidget.swift:246`, `:256` | ◐ |
| Shared design | `WidgetDesignSystem.swift:80` `WidgetLayout`, `:103` monograms, `:146` contrast, `:176` `ProviderMark`, `:254` `QuotaBar`, `:288` lanes, `:333` hero, `:469` header, `:510` freshness (orange stale), `:556` empty | ◐ teal for Codex |

No accessory families. The extension target is `WidgetExtension/project.yml` (compiles `Sources/OpenBarWidget`,
links `OpenBarCore`).

## 10. Provider logos and colors

| What | Where | Identity |
| --- | --- | --- |
| Logo loader | `ProviderBrandIcon.swift:5` (18 pt; template unless a curated `Brand-*` asset) | ○ |
| Monochrome logos | `Resources/ProviderIcon-*.svg` (105 files) | third-party, unchanged |
| Curated color logos | `Resources/Brand-ProviderIcon-{codex,antigravity,bedrock,claude,mistral,muse,vertexai}.*` | third-party, unchanged |
| Provider colors | `ProviderBranding.color` in each `OpenBarCore/Providers/*/*ProviderDescriptor.swift`; overrides `OpenBarCore/Providers/ProviderAccentColors.swift:11`; app `ProviderAccentPalette.swift`; widget `WidgetDesignSystem.swift:238`, `OpenBarWidgetViews.swift:693` | Codex `#49A3B0` = CodexBar teal ● |
| Website logos | `docs/logos/*`; framing `docs/site.css:937` | third-party |

## 11. App icon

| Artifact | Files | Identity (before this phase) |
| --- | --- | --- |
| Icon Composer source | `Icon.icon/icon.json`, `Icon.icon/Assets/*` | ● chevron + teal/red meter (replaced by Open Ring) |
| Bundle icon | `Icon.icns` (`Scripts/build_icon.sh`; copied by `Scripts/package_app.sh:597`) | ● (replaced) |
| Pre-macOS 26 icon | `Resources/Icon-classic.icns` (selected in `OpenbarApp.swift:611`) | ● (replaced) |
| Web/social icon | `docs/icon.png` | ● (replaced) |
| Other marks | `assets/icon.svg` (amber "O"), `Integrations/Linux/icon.svg` (● chevron + bars) | ● Linux icon |

## 12. Docs site

| Surface | Files | Identity |
| --- | --- | --- |
| Theme | `docs/site.css:1`, `:96` (links/selection `#0099FF`, focus `#38BDF8`) | ○ |
| Header, hero, install | `docs/index.html:72`, `:244`, `:264`; `docs/site.css:589` | ● header icon |
| Hero artwork | HTML/CSS `#mockup-stage` in `docs/index.html` (the former `hero-mockup.svg` laptop artwork was removed in the redesign) | ○ |
| Simulated menu bar | `docs/index.html:168`; `docs/site.css:218`, two-meter mark `:240` | ● |
| Hero Codex popover | `docs/index.html:179`–`:220`; `docs/site.css:355`, teal fill `#4FB6C3` `:446`, red marker `#FF4055` `:460` | ● |
| Feature illustrations | `docs/index.html:427`, `:481`, `:519`; `docs/site.css:1202`–`:1468`; `docs/features/*.webp` | ● teal meters |
| Provider directory | `docs/index.html:292`; `docs/site.css:913`, `:937` | ○ |
| CLI terminal, widgets gallery, footer | `docs/index.html:557`, `:647`, `:802`; `docs/site.css:1960`, `:2134` | ◐ app icon |
| CSS pipeline | `Scripts/build-site-css.sh`, `Scripts/tailwind.site.config.cjs`, `Scripts/site-tailwind.input.css` → `docs/site-utilities.css` | — |
| Locale checks | `docs/site-locales.mjs`; `Scripts/check-site-locales.mjs` | — |

## 13. Social card

| Artifact | Files | Identity |
| --- | --- | --- |
| Source | `docs/social.html` (1200 × 630; orange/purple/teal/pink aurora) | ◐ teal glow, app icon |
| Image + receipt | `docs/social.png`, `docs/social-card.json`; `Scripts/social-card.mjs --update`; checked by `Scripts/check-site-locales.mjs` and `Scripts/test_social_card.mjs` (from `Scripts/lint.sh:135`) | ● icon (re-rendered with the new icon in this phase) |

## 14. README and documentation images

| Item | Where | Identity |
| --- | --- | --- |
| Badges | `README.md:3`–`:5` ("Fork of CodexBar" badge in `#16D3B4`) | ● |
| Main image | `README.md:7` → `docs/social.png` | ● (updated) |
| Old screenshot | `docs/openbar.png` (unreferenced; shows "About CodexBar") | ● |
| Website widget screenshots | `docs/widgets/01`–`11-*.png` (referenced from `docs/index.html:702`–`:781`) | ◐ |
| Other captures | `docs/screenshots/*`, `docs/images/*`, `docs/keychain-allow.png` | archival |

## 15. CLI and embedded web dashboard

| Surface | Files | Identity |
| --- | --- | --- |
| CLI meters and colors | `Sources/OpenBarCLI/CLIRenderer.swift:6`, `:150`, `:183`–`:197` (teal gradient `(40,150,140)→(90,220,200)`) | ● teal |
| CLI cards / brief table / cost | `CLICardsRenderer.swift:250`; `CLICardsBriefRenderer.swift:58`; `CLICostCommand.swift:332`, `:582` | ○ |
| `openbar serve` web UI | `Sources/OpenBarCLI/CLIServeWebUI+HTML.swift:14` (fallback accent `#49A3B0` at `:50`, `:105`, `:239`, `:806`) | ● teal |
| Linux (Qt) and Omarchy | `Integrations/Linux/qml/*.qml`, `Integrations/Omarchy/Panel.qml` | ○ (separate integrations) |

## 16. Localization

App strings: `Sources/OpenBar/Resources/<locale>.lproj/Localizable.strings(.stringsdict)`; widget strings:
`Sources/OpenBarWidget/Resources/<locale>.lproj/Localizable.strings`; site: `docs/site-locales.mjs`. 23 locales
(ar, ca, de, en, es, fa, fr, gl, id, it, ja, ko, nl, pl, pt-BR, ru, sv, th, tr, uk, vi, zh-Hans, zh-Hant).
Enforced by `Scripts/check-app-locales.mjs` (key coverage, strict extras for ar/ca/fa/th, format
signatures), `Scripts/sync-widget-locales.mjs --check`, and `Scripts/check-site-locales.mjs`. "CodexBar" does
not appear in any catalog.

## 17. Rendering technology scan

| API | Finding |
| --- | --- |
| SwiftUI `Canvas` | `Sources/OpenBarWidget/BurnDownWidgetViews.swift:321` only (widget process) |
| `import Charts`, `.drawingGroup`, `.layerEffect`, `.colorEffect`, `.visualEffect`, Metal | none |
| `NSVisualEffectView` | Settings materials (`PreferencesView.swift:523`, `:545`, `:614`); menu selection (`StatusItemController+MenuPresentation.swift:477`, `:555`) |
| CPU raster drawing | `UsageProgressBar.swift:70`; `IconRenderer.swift:1138`; `SpendActivityPalette.swift:31`; `ShareStatsRenderer.swift:6` |

There is no app-wide theme today; visual constants are spread across ~40 files (listed per surface above).
The new tokens are in `Sources/OpenBarCore/Design/OpenBarDesignTokens.swift`.
