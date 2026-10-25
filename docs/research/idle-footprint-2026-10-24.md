# Idle footprint, worker waits, and release bundle size

The bundle is 9.9% smaller, and the waiting parent no longer polls its helper. The fresh
scenario median increased from 90 to 104 MB settled and from 140 to 156 MB peak. No overall
scenario-memory improvement is established by this batch. Lower closed-menu observations
and the direct registry-storage saving are reported separately below.

Measurements use the supplied `OpenBar-int12.app` and a release build of this patch on
2026-10-24, macOS 27.2 (26B5112a), arm64. The checkout began at `f8d776710`, which includes
the requested `34ca27682` baseline plus the existing OpenBar Sparkle key correction.
That correction is retained. No SwiftUI view file changed.

## Changes

- Share each immutable `ProviderDescriptor` through a final, `Sendable` class. All 109
  providers remain registered. This avoids copying the large descriptor into manifest
  arrays and app-side provider-spec dictionary buckets. All stored properties remain `let`.
- Wait for cost-worker pipe data, process exit, cancellation, or the existing 15-minute
  continuous-clock deadline. The old parent loop slept for 10 ms between status checks.
  The new wait does not change scans, totals, refresh cadence, response limits, or fallback.
  Deadline sleep has explicit zero tolerance. A bounded debug-only environment variable
  permits short diagnostic deadline runs; release builds retain the fixed 15-minute limit.
- Compile the release app shell with `-Osize`. `OpenBarCore`, including scanners and provider
  fetches, keeps `-O`. Existing linker dead stripping remains enabled.
- Ship only runtime SwiftPM resource bundles in the main app. Keep widget resources in the
  widget and keep the helper's own Core resources. Use relative symlinks for main-bundle
  asset/localization lookups instead of duplicate file contents. Keep every source asset,
  translation, and runtime framework. The duplicate classic app icon also becomes a symlink.
- Explicitly disable Keychain access in the existing packaged-launch smoke environment.

## Measurement method

All app launches used `OPENBAR_DISABLE_KEYCHAIN_ACCESS=1` and the supplied synthetic
configuration. CLI cost checks used a private frozen copy of the golden fixture home.
No interactive provider probe, real account CLI request, cookie import, or desktop automation
was used. The supplied in-app scenario probe exercised menu, Settings, and refresh paths.

Raw evidence lives under `~/Library/Caches/openbar-research` (`$R` below). Apps and matching
dSYMs are under `$R/apps`. Baseline scenario receipts are `perf-before-1`, `perf-before-r2`,
and `perf-before-r3` in `$R/profile/trials`. The interrupted `perf-before-2` receipt is invalid
and is retained without inclusion in the median. Final receipts use the `perf-clock` label.

The host ran other builds during this work. Startup cache hydration also varied between
captures. These are local observations, not a controlled performance lab result. In particular,
the 30-second footprint difference is not all a descriptor saving: the final app's live malloc
data at 30 seconds was 10.3 MiB, before later snapshot hydration, versus 18.7 MiB in the baseline.
Footprint values retain the tools' displayed MB units. Exact bundle
bytes and MiB conversions are reported separately. Stack-logged footprint is excluded from
product footprint comparisons because it includes Performance Tool Data.

The idle-only run keeps menus closed. It samples footprint at 1, 3, 5, 10, and 30 seconds,
then brackets a 600-second wait with process CPU counters. `top` records `IDLEW` at each end.
`IDLEW` counts package-idle exits; zero does not prove zero process wakeups on a busy host.
The controlled helper-wait measurement also samples process interrupt wakeups through
`proc_pid_rusage`, over two seconds while a helper deliberately sleeps.

Startup trials measure the status-ready probe marker from launch. A separate quiescence
predicate requires five consecutive one-second samples with less than 0.01 seconds of new
main-process CPU time and no remaining child process. Trials stop at 90 seconds. This
predicate and the status-ready marker are different metrics; neither is silently substituted
for the other. A main-process CPU-only proxy omits the child-process condition.

## Results

| Metric | Supplied app, fresh measurements | Corrected patch |
| --- | ---: | ---: |
| Closed-menu footprint at 30 s, one run | 68 MB | 29 MB |
| Closed-menu footprint after the 600 s CPU interval | 66 MB | 56 MB |
| Main-process CPU per 600 s, one run | 2.96 s | 1.53 s |
| `top` package-idle wakeup delta over that interval | 0 | 0 |
| Waiting parent interrupt wakeups per 2 s, controlled slow helper | 26 | 0 |
| Status-ready time, median of three | 0.411 s | 0.299 s |
| No-child startup quiescence, median of three | **UNVERIFIED**, all three exceed the 90 s observation limit | 39.044 s |
| Main-process CPU-only quiet proxy, median of three | 8.114 s | **19.042 s** |
| App logical size, files plus symlink text | 111,934,303 B (106.75 MiB) | 100,873,161 B (96.20 MiB) |
| App disk allocation, `du -sk` | 111,428 KiB | 99,924 KiB |
| Stripped main binary | 40,419,200 B (38.55 MiB) | 37,967,792 B (36.21 MiB) |
| Scenario idle at about 90 s, median of three | 60.7 MB | **65.1 MB** |
| Scenario Settings open, median of three | 120.1 MB | **139.7 MB** |
| Scenario settled event, median of three | 90.0 MB | **104.0 MB** |
| Scenario OS lifetime peak, median of three | 140 MB | **156 MB** |

The bundle is 9.9% smaller by logical bytes, and the main binary is 6.1% smaller. The CPU-only
startup proxy worsened; the stronger no-child predicate completed sooner in these runs.
These startup predicates observe different work and must not be collapsed into one claimed
startup speedup. The supplied reference figures (68 MB idle, 94 MB settled, 162 MB peak)
remain historical context; the table compares fresh measurements of both artifacts.

The controlled helper wait uses the real CLI command path with a helper that sleeps before
executing the packaged CLI. The new parent consumed no additional recorded CPU ticks during
the two-second wait. This is a parent waiting result, not a cost-helper peak-memory reduction.

Baseline trials, audited for every required event, absence of `not-found`, and valid samples:

| Receipt | Idle | Settings open | Settled event | OS peak |
| --- | ---: | ---: | ---: | ---: |
| `perf-before-1` | 38.9 | 120.1 | 90.0 | 140 |
| `perf-before-r2` | 60.7 | 123.4 | 120.9 | 141 |
| `perf-before-r3` | 76.6 | 118.5 | 87.0 | 139 |

All values in that trial table are MB. Each has zero invalid footprint samples. The lifetime
peaks were already reached before `done`, so the older harness's extra observation time does
not change them. The baseline settled value is taken from the probe event, matching the new
strict script; the older last-external-sample median was 91 MB.

Final trials use the updated strict `trials.sh` and `measure_app.sh`. All three reached `done`,
contain all required events, found the menus, and have zero invalid samples. Peaks come from
their new `.final` receipts. No `INVALID` run contributes to any result.

| Receipt | Idle | Settings open | Settled event | OS peak | Aggregate helper maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| `perf-clock-1` | 82.8 | 126.3 | 120.2 | 146 | 194.6 |
| `perf-clock-2` | 65.1 | 151.4 | 101.3 | 167 | 288.8 |
| `perf-clock-3` | 60.3 | 139.7 | 104.0 | 156 | 210.0 |

These are MB. The source summary is `$R/profile/trials/perf-clock.summary.csv`. The median
aggregate helper maximum is 210 MB versus 266 MB before, with wide ranges of 195-289 and
128-425 MB. This aggregate cannot establish the isolated 140-180 MB helper-burst goal.
The higher final scenario footprints and slower CPU-only startup proxy remain findings to
investigate with fixed app-cache inputs and less host contention; they are not accepted as
an overall memory win. No view cache or data-retention behavior was changed to force a pass.

## What makes up launch memory

The unlogged baseline idle VM summary reports **18.7 MiB allocated malloc data** and
**35.7 MiB malloc fragmentation/slack** (66%). Malloc small regions account for about 50 MB
of the physical footprint, malloc large regions 7.3 MB, other dirty/data regions about 5 MB,
and image mappings about 1.1 MB. These categories and rounding do not sum to an exact heap
ownership model. Mapped shared framework code is not all privately owned resident memory.

A separate baseline allocation tree at 90 seconds reports 19,248,546 live malloc bytes.
The largest startup paths include about 10.2 MiB under app startup, 6.3 MiB under cached cost
snapshot decoding, and 1.7 MiB under provider registration. Call-tree branches can overlap;
they are allocation paths, not independent ownership totals. Exact quota-slice array storage
is 4,341,760 bytes. Descriptor array storage is 638,976 bytes across two arrays, and the
provider-spec dictionary allocates 573,440 bytes. This is the direct target of the descriptor
change; changes in allocator layout and slack can exceed the change in live object bytes.

The final 600-second capture has 109 descriptor objects using 279,040 bytes and a 16,384-byte
provider-spec dictionary. These structures save roughly 0.9 MiB, before accounting for the
small replacement arrays of references. Total live malloc data is 18,075,378 bytes. Its timed
entry arrays use 4,718,592 bytes, more than the baseline's 4,341,760 bytes, so cost data was not
removed to obtain the descriptor saving. This allocation census is distinct from the unlogged
physical-footprint measurements and from the early 30-second capture.

## Findings left unchanged

- The cached cost snapshot supplies startup spend data. Its quota slices are a large live
  allocation. Dropping them or postponing visible snapshot availability needs a separate
  behavior decision. Large history loaders already use background or demand-driven paths;
  no new main-thread history decode was found to remove in this pass.
- The idle allocation trace contains no live `JS_NewRuntime`, `JS_NewContext`, JavaScriptCore
  VM-creation, or `WKWebView` creation frame. Plugin engines are already created when used.
  WebKit/JavaScriptCore linkage and bundled QuickJS support remain because features use them.
- The ad-hoc release build disables Sparkle through its existing signing guard. This work
  does not measure enabled, signed Sparkle updater overhead or prove a signed update flow.
- The hang watchdog is debug/opt-in in release. Menu animation/display-link work already
  follows animation state. Countdown refreshes follow visible text boundaries, and fetch
  timers define user refresh semantics. Those schedules remain unchanged.
- The roughly 12 MB first-Settings runtime/CoreUI cache floor remains as described in
  [the Settings heap investigation](settings-layout-heap-2026-10-24.md). No view teardown,
  styling change, or unsupported framework-cache purge is included.
- Cost-helper peak allocations are not targeted by the parent wait change. Aggregate helper
  footprint samples can include overlapping workers after forced process shutdowns. No
  isolated cost-helper peak-memory reduction is claimed.

## Validation and rejected experiment

The first event-driven candidate omitted explicit clock tolerance. Its real 900-second
timeout check had not returned at the 950-second harness limit. That candidate was rejected.
The deadline predicate was retained; the timer was corrected to request zero tolerance.
The Swift clock API permits implementation-selected tolerance when none is supplied; see
[the ContinuousClock API](https://developer.apple.com/documentation/swift/continuousclock/sleep(until:tolerance:)).
Short debug CLI runs exercise the same wait/deadline path. The final release also needs the
full 900-second check, child-process cleanup, exact empty-result fallback, oversized-response
fallback, cancellation, and the direct/worker golden comparisons before acceptance.

The corrected release's full deadline check returned in **900.867 s**. It removed the sleeping
helper, logged one fallback, and returned the same empty result as the original CLI. Empty and
64 MiB + 1 byte helper responses fell back to the same Claude golden result. Cancellation
returned `CancellationError` in 0.124 s and left no child. The debug probe environment-variable
name is absent from both release executable files.

The final mandated golden comparisons are **12/12 direct** (`perf-clock-direct-isolated`)
and **12/12 worker** (`perf-clock-worker`), against `baseline-oct24`. No date rollover occurred.
The first corrected-build direct run was **10/12**, and remains in `perf-clock-direct`.
Its two failing warm calls advanced from three to 19 days of history after their cold calls
took 82-137 seconds. The scanner's unchanged cache age is 60 seconds, measured from the
captured scan-start date. Thus those warm calls were additional refreshes.

An original-app control confirms the cause. `OpenBar-int12.app` returned three days cold, then
19 after the same cache aged past 60 seconds. Restoring that exact post-cold cache seed and
running the new CLI produced the same normalized aged-warm output, including costs. The
control is saved in `golden/perf-clock-age-control`. Only after that reproduction was the
mandated direct script run once more without the overlapping test build. Its 12 cases match
the original oracle. No scanner setting, date, baseline, normalization, or pass threshold changed.

Existing focused tests passed: 16 tests in `ProviderRegistryTests`,
`ProviderDescriptorRegistryStorageTests`, `CostUsageScanExecutorTests`, and
`ProcessPipeCaptureTests`. No unit test was added. `make check` passed, including full source
format/lint and script checks; its TypeScript compiler pass used `tsrs`. Final touched-file
SwiftFormat/SwiftLint and shell syntax checks passed. The full Swift test suite was not run.

The packaged-launch smoke passed app, helper, and symlinked-helper resource loading with
checkout access denied, then six seconds of isolated app startup. All 159 source app resources
are byte-identical through their main-bundle paths, and all 23 localization tables match.
Local strict code-signature verification passed. Signed distribution, notarization, active
Sparkle updating, real-account provider access, and other macOS versions remain unverified.

The early candidate's complete scenario receipts and the failed timeout logs remain in `$R`.
They are not relabeled as final corrected-build acceptance. Relevant final logs are
`perf-clock-{build,runtime-validation,tests,make-check,worker-safety,timeout}.log` and
`perf-clock-golden-age-control.log`. Aggregate read-only facts are in `perf-clock-facts.json`.

## Commits and artifact identity

- `cb863d0b3`: Share immutable provider descriptors.
- `be417b22d`: Wait for cost worker events.
- `d24a18c3b`: Reduce release bundle size.

The release was built from the same source patch before these commits, so its embedded
`CodexGitCommit` is `f8d776710`. The supplied baseline's embedded value is `848641d94`.
Both are version 0.80.1 (174). The artifact identity, rather than the embedded pre-commit
revision alone, identifies the measured build:

| Artifact | Main binary UUID | Main binary SHA-256 |
| --- | --- | --- |
| `$R/apps/OpenBar-int12.app` | `53A6F473-BAAD-3369-96CD-A11420B98113` | `febd970c2d9b24558748cf332e89049c9ed8bccf6df9208ec79efb0f6b864802` |
| `$R/apps/OpenBar-perf-clock.app` | `9066D67B-D261-3C4E-93A8-0AB91B2B3798` | `f0bf9e1e2f95d693a68987e3f7795d87479438eca42847959f0902ac5334a5d4` |

Each adjacent `.app.dSYM` has the matching UUID. No artifact was pushed or published.
