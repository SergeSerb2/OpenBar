# Settings layout heap after close

The roughly 12 MB attributed to the first Settings layout is largely runtime and drawing cache memory.
It is not a 12 MB live `NavigationSplitView` graph. The existing root swap already removes the split
controller and its column hosting views. Removing the window's hosting controller as well does not
release that allocation floor. No production teardown change is included in this investigation.

## Scope and environment

- Source baseline: `9d2f3d227`. Measurements ran on macOS 27.2 (26B5112a), arm64, using the release app.
- The supplied baseline remains the before reference: settled footprint 91/119/100 MB; OS peaks
  150/162/153 MB; dominant Settings allocation branch 12.1 MB at 150 seconds after the last menu close.
- All launches used `OPENBAR_DISABLE_KEYCHAIN_ACCESS=1` and the supplied synthetic provider configuration.
  No interactive provider probe, cookie import, or desktop automation was used.
- Allocation call trees include allocations first made along a call path. Their parent function is not
  an ownership relationship. These trees also include recorded VM allocations. Numbers below retain
  the tool's displayed units and rounding; summed branches are approximate MiB.
- Footprint under stack logging includes `Performance Tool Data`. It is not a product footprint result.

## Owners of the baseline allocations

The supplied settled heap and a new baseline close capture contain one Settings
`NSHostingController<AnyView>` and one KVO-wrapped root hosting view, but no split coordinator, split
controller, or split-column hosting views. `leaks` reports **0 leaked bytes**. This does not alone prove
that every reachable object is useful; the object census and reference chains distinguish the owners.

The host at `0x78fcef7f20` has direct references from both `NSWindowAuxiliary._contentViewController`
and `NSWindowControllerMoreIVars._contentViewController`. The root hosting view at `0x78fd7c7200`
also has a reference from the window's `_initialFirstResponderX` field. Thus, detaching only
`window.contentViewController` is not a complete ownership experiment.

`malloc_history -callTree -showContent` on that baseline capture attributes approximately 12.65 MiB of
allocation contents to the dominant Settings branch:

| Allocation contents | Baseline MiB | Full teardown, sixth close MiB |
| --- | ---: | ---: |
| Swift metadata, generic metadata map entries, witness caches | 5.173 | 5.259 |
| CoreSVG objects and storage | 1.747 | 1.706 |
| Objective-C method/class caches | 0.926 | 0.850 |
| CoreText allocations | 0.556 | 0.518 |
| AttributeGraph allocations | 0.410 | 0.404 |
| VM regions | 0.584 | 0.271 |
| Other objects and storage | 3.250 | 2.932 |

This classification does not label every object in the last rows as a permanent cache.
The following direct address traces establish the important independent owners:

1. `malloc_history` for `0x7902417000` identifies a 20,480-byte Swift metadata pool allocated through
   `swift::MetadataAllocator::Allocate`, with `SettingsWindowController.open(pane:)` in its allocation
   stack. `leaks --trace` finds named global type/witness cache references into it, including the
   `_ContiguousArrayStorage<DockIconWindowDescriptor>` demangling cache and SwiftUI focus/display-list
   type caches. Closing a window does not invalidate those types or their users. A pooled allocation
   can contain metadata used by several parts of the process.
2. `malloc_history` for `0x78fb054c60` identifies a Settings-created `SVGDocument`. Its reference chain
   is CoreUI's global theme registry → `CUIStructuredThemeStore._cache` →
   `_CUIThemeVectorGlyphRendition._svgDocument` → the document. It is not owned by the Settings graph.

The [Swift runtime metadata allocator](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/Metadata.cpp)
also uses shared allocation pools; its deallocation path does not provide a window-scoped purge.
The live process traces above are the evidence for this particular system, rather than a claim that
the current upstream source exactly matches the installed Apple runtime.

## Teardown experiments

All variants retained the original `NSWindow`, selection model, frame autosave setup, Dock handling,
and About routing. Changes existed only in a diagnostic build and have been removed from source.

| Variant and capture | Dominant Settings branch | Sum of all Settings open branches | Remaining Settings hosts |
| --- | ---: | ---: | --- |
| Supplied baseline, settled | 12.1 MiB | 12.31 MiB | One root host; no split columns |
| New baseline, close +10 s | 12.6 MiB | 12.82 MiB | One root host; no split columns |
| Empty-root `layoutSubtreeIfNeeded`, close +10 s | 13.9 MiB | 14.17 MiB | One root host; no split columns |
| Root swap and detach both controller owners, after six closes | 13.1 MiB | 18.17 MiB | No root controller; two split-column hosts |
| Full teardown, after first close | 12.2 MiB | 12.44 MiB | None |
| Full teardown, after sixth close | 11.9 MiB | 13.07 MiB | None |

Full teardown swapped to the empty root, forced its layout, removed the toolbar, cleared initial/current
responders, cleared both controller owners, and set `window.contentView = nil`. Reopen created a fresh
hosting controller in the same window. All host and split-column instances were absent after closes
one and six, yet the 12 MB floor remained. Detach alone was worse: the surviving column host had a
reference through an AppKit `NSView._commonAwake` notification-observer block.

Across the full-teardown six-cycle run, total live malloc bytes decreased from 52,784 KB to 43,220 KB
as other work settled. Settings-attributed branches increased by approximately **0.62 MiB**, not zero.
There was no per-open accumulation of split hosting instances or another 12 MB graph on each reopen.
Both captures report 0 leaked bytes. These observations do not establish a zero-growth byte budget.
The diagnostic scenario exercised Usage & Spend reopen/close. It did not establish visual toolbar,
focus, or every-pane behavior acceptance for a replacement hosting controller. The final commit leaves
the production lifecycle unchanged, so it introduces no such behavior risk.

The first detach-run snapshot was excluded because the probe's `settings-closed+10s` event immediately
starts the next cycle. It caught cycle 2 open. The runner was then edited while active and exited after
its valid cycle-6 capture, so that run has no final `done` capture. The full-teardown run used an unchanged
separate runner, captured the first close before the next reopen, and completed all six cycles.

## Unprofiled footprint

Two full-teardown trials used the supplied `trials.sh` scenario, without stack logging:

| Build/scenario | Settled MB | OS peak MB | Maximum sampled MB |
| --- | ---: | ---: | ---: |
| Supplied baseline, three trials | 91 / 119 / 100 | 150 / 162 / 153 | Supplied baseline files |
| Full teardown, cold trial | 95 | 118 | 114 |
| Full teardown, warm trial | 94 | 157 | 157 |

The probe's `done` values were 94.8 and 94.1 MiB, at 334.1 and 338.5 seconds. Both completed the
150-second settle interval and met the under-100 MB footprint target in this diagnostic build.
Separate CLI helper peaks were 274 and 226 MB; they are not included in the main app's settled value.

A temporary `open` wrapper added only
`--env OPENBAR_SETTINGS_TEARDOWN=render-toolbar-responders-detach-view`; the scenario still explicitly
disabled Keychain access. An environment check on trial 2 confirmed the mode, Keychain suppression,
and absence of `MallocStackLogging`. No threshold was changed.

These two values do not establish a repeatable teardown benefit against the variable baseline, whose
first trial was already 91 MB. The saved categories show baseline `Malloc Large` dirty memory varying
from about 3.6 to 18 MB, versus about 3.6 MB in both diagnostic trials. CoreAnimation was about 0.6 MB
in the baseline and about 1.0 MB after full teardown. There is no matching reduction in live Settings
allocations or graphics categories that establishes ownership of the footprint difference.

Another research worker reported shared access to the golden scanner cache near 06:47, then moved its
replay cache to a private root. Allocation/reference findings do not depend on scanner cache isolation.
The footprint comparison has only the supplied baseline trials and two new runs; it is not a broad
statistical or cross-OS acceptance result.

## Consequences and a separately reviewed layout alternative

None of the tested public AppKit teardown paths releases the 12 MB allocation floor. A full teardown
can remove every Settings hosting instance while the first-layout allocation stacks remain. Freeing
those bytes by treating stack attribution as ownership would invalidate shared runtime/framework data.
Keeping the current long-lived window and hosting controller avoids adding a new lifecycle change for
an unproved memory benefit. Workspaces and OpenAI Live Usage retain their current root-swap behavior.
The diagnostic build's sub-100 MB samples are retained as observations, not production acceptance for
the more invasive teardown. The live-heap goal was not achieved by that teardown.

Avoiding some first-layout allocations requires a separate allocation/design experiment, rather than
more close-time ARC teardown. A replacement for `NavigationSplitView` would need a sidebar list and
detail view in an `HStack`, persisted/resizable sidebar widths, search and keyboard selection, history
buttons and About routes, pane titles, minimum sizes, and the same macOS 26+ titlebar/material/scroll-edge
appearance. The existing pre-26 `legacyLayout` is a reference, not visual acceptance for macOS 26+.
It would also need to preserve accessibility, focus, frame autosave, Stage Manager behavior, and Dock
transitions. It would not by itself remove metadata or drawing caches created by the detail panes.
No visual redesign or private framework-cache purge was implemented.

## Validation and retained evidence

- Release package: `OPENBAR_SIGNING=adhoc ./Scripts/package_app.sh release`, launched detached as requested.
- Existing tests: `PATH=/opt/homebrew/bin:$PATH swift test --filter SettingsWindow` and
  `swift test --skip-build --filter 'PreferencesSelection|DockIcon'`, under the scrubbed test environment
  with both Keychain suppression controls. Results: 29 + 27 tests passed, including the final restored
  production source. Tests were neither added nor modified.
- Targeted SwiftFormat lint and strict SwiftLint: passed, zero violations.
- Repository `make check`: passed, including strict lint of 3,120 Swift files. Its TypeScript check used
  tsrs 0.18.0 through a temporary Node wrapper; the repository scripts and dependencies are unchanged.
  The wrapper left the pinned compiler's version query intact and replaced only its project check.

All raw evidence is retained under `~/Library/Caches/openbar-research/`:

- `profile/settled/int10/`: supplied settled baseline.
- `profile/retainers/settings-baseline/`: heap census, saved memory graph, allocation-content tree,
  direct host/metadata/SVG histories and reference traces, and content-category JSON.
- `profile/settings-teardown/{render,detach6,all6}/`: per-variant snapshots and probe events.
- `profile/trials/settings-all-*`: unprofiled samples and footprints.
- `apps/OpenBar-settings-teardown-probe.app` and `.app.dSYM`: the diagnostic release build.
- `settings-teardown-experiment.patch`: exact temporary source changes; not included in the commit.
- `settings-heap-build.log`, `settings-final-tests.log`, and `settings-check.log`: validation logs.

The diagnostic modes were `render`, `detach`, and `render-toolbar-responders-detach-view` via
`OPENBAR_SETTINGS_TEARDOWN`. The retained `scripts/settings_teardown_run_v2.sh` drives the last mode
with six cycles, and `scripts/settings_heap_summary.py` sums all `SettingsWindowController.open(pane:)`
branches without counting nested allocator frames again. Its totals use rounded call-tree node sizes.
The diagnostic app and dSYM both have UUID `0A6923DC-0685-38ED-AF3C-3B1FCC09D61E` (arm64).
