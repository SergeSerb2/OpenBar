# Security policy

## Reporting a vulnerability

Please report security problems privately through GitHub:
**[Report a vulnerability](https://github.com/SergeSerb2/OpenBar/security/advisories/new)**.
Only the repository maintainers can see the report. Do not open a public issue, pull request, or discussion for a
security problem.

Include:

- the OpenBar version (About pane or `openbar --version`) and the macOS version,
- the provider and source mode involved, if any,
- steps to reproduce, and what an attacker gains,
- logs or screenshots with every token, cookie, API key, email address, and account ID removed.

You will get a reply in the advisory thread. OpenBar has one maintainer, so please allow some time. When a fix ships,
the advisory is published and credits you unless you ask otherwise.

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x (latest release) | Yes |
| Builds from source before 1.0.0 | No. Update to the latest release. |
| CodexBar | No. Report CodexBar issues to [steipete/CodexBar](https://github.com/steipete/CodexBar). |

Fixes ship in a new release and reach installed copies through Sparkle updates.

## Threat model in brief

OpenBar reads usage and billing data for AI providers. To do that, it holds credentials that can act on your
accounts. Its main job, from a security point of view, is to keep those credentials on your Mac and out of logs.

**What OpenBar stores and where**

- API keys, manual cookie headers, and token accounts are in the OpenBar config file
  (`~/.config/openbar/config.json`, or `~/.openbar/config.json` on older installs). The file is written atomically
  with `0600` permissions.
- Some imported browser cookies and OAuth credentials are cached in OpenBar-owned macOS Keychain items.
- OpenBar does not store browser or account passwords. Browser sessions are reused only when you turn on cookie
  import for a provider.

**Keychain boundary**

- Background refreshes do not request Keychain interaction. The one exception is Claude's opt-in **Always allow
  prompts** policy. Browser cookie import shows at most one macOS prompt per manual action, and a denial suppresses
  further browser prompts for six hours.
- **Settings → Advanced → Disable Keychain access** blocks OpenBar's own Keychain reads and writes and browser
  cookie decryption. It cannot control provider CLIs that OpenBar launches, such as Claude Code, which own their
  credentials. See [Keychain prompts](docs/keychain-prompts.md).

**Network**

- OpenBar connects to the providers you enable. It also fetches provider status pages (Settings → General → Check
  provider status), the update feed, model prices from `models.dev` for cost estimates, and exchange rates from
  `open.er-api.com` only when you choose a currency other than USD.
- OpenBar has no analytics or telemetry.
- Release builds are signed with a Developer ID and notarized. Sparkle verifies each update with OpenBar's EdDSA key.

**Local interfaces**

- The in-app HTTP server is off by default. `openbar serve` and the in-app server bind to `127.0.0.1` by default.
  On loopback, `/usage` and `/cost` need no token, so any local process can read usage data while the server runs.
  A non-loopback bind requires a bearer token and an explicit plain-HTTP acknowledgment. See [the CLI
  reference](docs/cli.md) and [the dashboard API](docs/dashboard-api.md).
- User-installed plugins run in an embedded QuickJS runtime with a memory cap and a watchdog. OpenBar owns the
  authentication header, and each network origin needs your typed approval. See [Plugins](docs/plugins.md).

**Out of scope**

- Anyone who can run code as your macOS user can read your config file and use your unlocked login keychain.
- Provider CLIs and provider back ends own their own credential handling.
- Usage numbers that a provider reports wrongly. Report those as ordinary bugs.

Good reports for this project include credentials that reach a log, a file with weak permissions, or the wrong
network origin; a Keychain prompt from background work; a plugin that escapes its approved origins or memory cap; a
way past the local server's token check; and anything that weakens update signature checks.
