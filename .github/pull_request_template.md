## Summary

<!-- What changes, and why. Link the issue: "Fixes #123". -->

## How I tested it

<!-- Commands you ran (for example `make test-fast FILTER='SuiteName'` and `make check`) and what you checked by hand. -->

## Screenshots

<!-- For UI changes: before and after, light and dark. Use synthetic data and redact account details. -->

## Checklist

- [ ] Focused tests cover the change, or I explained why none are needed.
- [ ] `make check` passes.
- [ ] Nothing I ran can show a macOS Keychain prompt, and no real credentials appear in code, tests, logs, or screenshots.
- [ ] User-visible changes have a `CHANGELOG.md` entry, and new or changed behavior is documented in `docs/`.
- [ ] Provider data stays siloed: no identity or plan fields from one provider appear in another provider's UI.
