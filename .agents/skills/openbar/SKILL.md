---
name: openbar
description: "OpenBar read. Provider usage, limits, credits, config health. JSON. No writes."
---

# OpenBar

Read OpenBar. Never mutate config/auth.

## Run

```bash
skill="${CODEX_HOME:-$HOME/.codex}/skills/openbar"
"$skill/scripts/openbar" doctor
"$skill/scripts/openbar" providers
"$skill/scripts/openbar" usage
"$skill/scripts/openbar" usage --provider codex
"$skill/scripts/openbar" usage --all
```

All stdout: JSON. Upstream OpenBar shape kept. Less drift, fewer tokens.

## Rules

- Start `doctor` when install/config unknown.
- `usage` reads enabled providers. Prefer this.
- `usage --provider ID` reads one provider.
- `usage --all` expensive; use only when needed.
- Identities hidden by default. `--include-identities` only when user explicitly needs them.
- Secrets always hidden.
- Helper read-only: fixed allowlist only. No config writes, auth repair, enable/disable, key storage.
- Timeout means upstream stuck. Narrow provider or raise `OPENBAR_TIMEOUT` (default 120 seconds).

## Binary

Auto-find: `OPENBAR_BIN`, PATH, app bundle, Homebrew cask. If missing: open OpenBar, Preferences > Advanced > Install CLI; or set `OPENBAR_BIN`.

Each stdout/stderr stream capped at 1 MiB while fully drained. Timeout kills process group.
