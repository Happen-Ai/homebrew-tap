# Happen AI Homebrew tap

```sh
brew install happen-ai/tap/bridge
# or, equivalently:
brew install happen-ai/tap/happen-bridge
```

Both commands install the [`happen-bridge`](https://github.com/Happen-Ai/happen-ai)
daemon — a tiny local process that runs Happen packs on your machine using your
Claude Max subscription instead of paying the cloud runtime.

## How this tap is maintained

This tap is populated automatically. On every `bridge-v*` tag pushed to
[`Happen-Ai/happen-ai`](https://github.com/Happen-Ai/happen-ai), the
[`bridge-release.yml`](https://github.com/Happen-Ai/happen-ai/blob/main/.github/workflows/bridge-release.yml)
workflow runs PyInstaller to produce signed macOS + Linux binaries, uploads
them to GitHub Releases, then renders this tap's formula + alias and pushes
them here.

- Formula source of truth (template):
  [`packaging/homebrew/Formula/happen-bridge.rb`](https://github.com/Happen-Ai/happen-ai/blob/main/packaging/homebrew/Formula/happen-bridge.rb)
- Release runbook:
  [`backend/bridges/claude-code-daemon/RELEASE.md`](https://github.com/Happen-Ai/happen-ai/blob/main/backend/bridges/claude-code-daemon/RELEASE.md)

**Don't edit `Formula/happen-bridge.rb` or `Aliases/bridge` here by hand** —
your changes will be overwritten on the next release. Edit the template in
the main repo and push a new tag.

## Why an alias?

[Issue #221](https://github.com/Happen-Ai/happen-ai/issues/221) spec'd the
short `bridge` name. Homebrew taps support `Aliases/<alias>` as a relative
symlink to a `Formula/<formula>.rb`. The CI keeps both in sync.

## macOS Gatekeeper

Week-one binaries are unsigned (Apple Developer ID work is in progress). The
formula's `def install` block strips the `com.apple.quarantine` attribute on
install, so `brew install` yields a runnable binary without manual right-click
→ Open. If you somehow still hit a Gatekeeper warning, see
[`docs/MACOS_UNSIGNED_BINARY.md`](https://github.com/Happen-Ai/happen-ai/blob/main/docs/MACOS_UNSIGNED_BINARY.md).
