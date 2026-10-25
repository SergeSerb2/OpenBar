# Contributing to OpenBar

Thanks for helping. OpenBar is a small, native macOS menu bar app with a large provider catalog, so the most useful
contributions are focused: one bug fix, one provider, or one documentation fix per pull request.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) first. Report security problems privately as described in
[SECURITY.md](SECURITY.md), not in a public issue.

## What gets merged

[VISION.md](VISION.md) is the scope document. In short:

- **Usually merged:** bug fixes with a clear cause, performance improvements that do not add much complexity, new
  providers that follow the existing descriptor and strategy patterns, small UI fixes, and documentation fixes.
- **Discuss first:** new features, new dependencies or tooling, broad refactors, and anything that changes provider
  authentication, data storage, releases, or user privacy. Open an issue before you write the code.

## Development setup

You need macOS 14 or later and Xcode with Swift 6.2 or later. CI builds with Xcode 27; older toolchains are best
effort. The project is a SwiftPM package; use the scripts in `Scripts/` and do not add dependencies or tools without
asking first.

```bash
git clone https://github.com/SergeSerb2/OpenBar.git
cd OpenBar
./Scripts/compile_and_run.sh          # build, package, relaunch OpenBar.app, and check that it stays running
./Scripts/compile_and_run.sh --test   # also run the sharded test suite first
swift build                           # debug build only
```

After a rebuild, restart the bundle you just built so you do not test a stale binary:

```bash
pkill -x OpenBar || pkill -f OpenBar.app || true; open -n ./OpenBar.app
```

Development builds are ad-hoc signed unless a Developer ID Application identity is installed, so macOS can ask for
Keychain access again after each rebuild. See [Development setup](docs/DEVELOPMENT_SETUP.md) for stable signing and
[the development guide](docs/DEVELOPMENT.md) for logging, project layout, and troubleshooting.

## Tests and checks

- Add or extend tests for new logic under `Tests/OpenBarTests/`, and under `TestsLinux/` for CLI or core behavior
  that must run on Linux. XCTest suites are named `FeatureNameTests` with `test_caseDescription` methods; Swift
  Testing uses backticked sentence names.
- While you iterate, run only the suites you touched:

  ```bash
  make test-fast FILTER='SuiteName'
  ```

- Before you open a pull request, run the formatters and the full lint and docs check once:

  ```bash
  swiftformat Sources Tests
  make check     # SwiftFormat, SwiftLint --strict, JS/TS lint, docs links, site locales, repo size, and more
  ```

- The full test suite takes a long time. Pull request CI runs it, so you do not need to wait for it locally. For a
  local full run, use `./Scripts/test.sh --direct-workers 8`.

### Keychain and credential safety

- Never run tests or checks that can show a macOS Keychain prompt. Live provider probes, browser-cookie imports,
  `openbar usage` against real accounts, and real Keychain reads must be explicitly requested. Use parser tests,
  stubs, test stores, or `KeychainNoUIQuery` instead.
- The test runners remove secret-looking environment variables and give tests a temporary home directory. Use
  synthetic credentials in fixtures; never depend on your real ones.
- Never paste tokens, cookies, API keys, or account emails into issues, pull requests, logs, or screenshots.

## Code style

- SwiftFormat and SwiftLint enforce the style: 4-space indent, 120-character lines. Explicit `self` is intentional;
  do not remove it.
- Prefer small, typed structs and enums, and keep the existing `MARK` organization.
- Use `@Observable` models with `@State` and `@Bindable`; avoid `ObservableObject`, `@ObservedObject`, and
  `@StateObject`.
- Keep provider data siloed: a provider's menu or card never shows identity or plan fields from another provider.
- In tests and docs, use released model names or clearly fictitious ones.
- UI changes follow the [Calm native design spec](docs/design/README.md). Use the design tokens instead of literal
  colors and sizes.

## Commits and pull requests

- Write commit subjects as short imperative clauses, for example `Fix icon dimming` or `Improve usage probe`. Keep
  each commit scoped to one change.
- In the pull request, include a summary, the commands you ran, screenshots for UI changes (light and dark), and a
  link to the issue it fixes.
- Update `CHANGELOG.md` under the top section when the change is visible to users.

## Providers and provider docs

Start with the [provider authoring guide](docs/provider.md). It lists every registration point and the
non-negotiable guardrails (identity silo, on-device parsing, bounded timeouts, careful numeric parsing).

- Each provider has its own page, `docs/<provider>.md`. Describe the data sources, the order OpenBar tries them,
  the settings, and what the user must do to sign in. Link the provider's own documentation for any endpoint or
  limit you rely on.
- Every page in `docs/` starts with front matter that has a `summary:` line and a `read_when:` list.
  `make docs-list` prints them.
- Do not edit generated files by hand. After you add a provider, run:

  ```bash
  Scripts/regenerate-provider-manifests.sh   # manifests and docs/provider-ids.md
  node Scripts/regenerate-provider-docs.mjs  # README, docs/providers.md, site provider cards, logos
  node Scripts/generate-llms.mjs             # docs/llms.txt
  ```

- Add the provider to `docs/providers.md` with its authentication and data-source summary.
- Use synthetic data in screenshots. Redact names, emails, and organization IDs.

## Reporting bugs and requesting providers

Use the [issue forms](https://github.com/SergeSerb2/OpenBar/issues/new/choose). A good bug report names the macOS
version, the OpenBar version, the provider, and its source mode, and includes logs with secrets removed.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
