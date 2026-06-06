# Why does macOS say happen-bridge is "damaged" or from an "unidentified developer"?

The week-one `happen-bridge` builds on GitHub Releases are **unsigned**. Apple
Developer ID code-signing + notarization is in progress — until that lands,
macOS Gatekeeper attaches a quarantine attribute to anything downloaded from
the internet and refuses to run it on first open. This is expected, the binary
is fine, and you have three ways past it.

> Linux + Windows users don't see this. Windows shows a different SmartScreen
> warning (also unsigned, week-one only); on Linux there's no equivalent.

## Pick the option that matches how you installed

### A. You installed with `brew install Happen-Ai/tap/happen-bridge`

Nothing to do — the formula strips the quarantine attribute on install. If you
somehow still see the warning, run:

```bash
sudo xattr -d com.apple.quarantine "$(which happen-bridge)"
```

### B. You installed with the curl one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/Happen-Ai/homebrew-tap/main/install-bridge.sh | sh
```

The installer **does not** clear quarantine (it can't, without knowing where
the binary will run from). Clear it once:

```bash
sudo xattr -d com.apple.quarantine "$(which happen-bridge)"
```

Or, equivalently:

```bash
sudo xattr -cr /usr/local/bin/happen-bridge   # if /usr/local/bin
sudo xattr -cr ~/.local/bin/happen-bridge     # if ~/.local/bin
```

### C. You downloaded the archive directly from GitHub Releases

You'll see one of two dialogs depending on macOS version:

- **"happen-bridge can't be opened because Apple cannot check it for malicious
  software"** (macOS 14+)
- **"happen-bridge can't be opened because it is from an unidentified
  developer"** (macOS 12–13)

Use the **right-click → Open** workaround:

1. In Finder, navigate to the binary (default: wherever you extracted the
   archive, e.g. `~/Downloads/happen-bridge-0.1.0-darwin-arm64/`).
2. **Right-click** (or Control-click) the `happen-bridge` file.
3. Choose **Open** from the context menu.
4. A new dialog appears with an **Open** button — click it. (Apple shows this
   confirmation only on right-click; double-click never offers it for unsigned
   binaries.)
5. macOS records the approval. From now on, double-click and `happen-bridge`
   from the terminal both work without warnings on this machine.

If you also want to clear quarantine globally (so launching from terminal
doesn't re-prompt), run:

```bash
sudo xattr -d com.apple.quarantine /path/to/happen-bridge
```

## How to verify it worked

```bash
happen-bridge --version
```

should print the version (e.g. `happen-bridge 0.1.0`). If you still see a
Gatekeeper dialog, the quarantine attribute is still set — check with:

```bash
xattr -p com.apple.quarantine /path/to/happen-bridge
```

An empty output means quarantine has been cleared and macOS is now blocking
for a different reason (corrupt download, wrong architecture, etc.). Re-run
the installer or download the matching architecture from
[Releases](https://github.com/Happen-Ai/homebrew-tap/releases).

## When does this go away?

Once Apple Developer ID code-signing + notarization land, every macOS build
will be signed by `Developer ID Application: Happen AI` and notarized by
Apple's service. macOS will treat it like any other commercial app — no
right-click required, no quarantine to strip. The exact rollout is tracked
internally; the operator runbook is at
[`backend/bridges/claude-code-daemon/RELEASE.md`](../backend/bridges/claude-code-daemon/RELEASE.md)
(§3 "Apple Developer ID code-signing certificate").

## Why doesn't the installer just clear quarantine itself?

It could, but doing so silently strips a security check Apple put in place to
prevent untrusted downloads from running. We'd rather show this doc once —
explaining what the attribute is and why it's safe to clear for *this*
binary — than train you to bypass macOS warnings reflexively. The Homebrew
formula clears it on install because Homebrew already implies trust in the
tap.

## Related

- [`docs/BRIDGE_ONBOARDING.md`](BRIDGE_ONBOARDING.md) — full bridge install /
  enrollment / troubleshooting guide.
- [`backend/bridges/claude-code-daemon/RELEASE.md`](../backend/bridges/claude-code-daemon/RELEASE.md)
  — release runbook + signing prerequisites.
- Tracking issues: #220 (interim unsigned binary on GitHub Releases),
  #221 (`brew install` once the tap is live).
