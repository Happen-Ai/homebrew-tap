#!/bin/sh
# install-bridge.sh — install the happen-bridge daemon from a GitHub Release.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Happen-Ai/homebrew-tap/main/install-bridge.sh | sh
#
# Distribution lives in the PUBLIC Happen-Ai/homebrew-tap repo — this script,
# the GitHub Release binaries, and the macOS doc are mirrored there by the
# bridge-release workflow, so unauthenticated users can install without access
# to the private Happen-Ai/happen-ai monorepo.
#
# Flags (after `sh -s --`):
#   --release-url <url>   Override the GitHub Releases base URL (e.g. for staging).
#   --version <ver>       Pin to a specific version (default: latest).
#   --dry-run             Print what would be downloaded + installed and exit.
#
# POSIX `sh` — does not require bash. Idempotent: re-running upgrades in place.

set -eu

# ── Defaults ─────────────────────────────────────────────────────────────────
RELEASE_BASE="https://github.com/Happen-Ai/homebrew-tap/releases"
VERSION=""
API_URL_OVERRIDE=""
DRY_RUN=0

# ── Parse flags ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --release-url)
      RELEASE_BASE="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --api-url)
      # Override the GitHub Releases JSON endpoint used to resolve the
      # latest `bridge-v*` tag. Accepts http(s):// or file:// URLs — the
      # latter is how the test suite injects a fixture without spinning
      # up a server. When unset, derived from `--release-url`.
      API_URL_OVERRIDE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install-bridge: unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

err() { echo "install-bridge: $*" >&2; exit 1; }
info() { echo "install-bridge: $*"; }

# ── Detect OS + arch ─────────────────────────────────────────────────────────
detect_os() {
  uname_s=$(uname -s 2>/dev/null || echo unknown)
  case "$uname_s" in
    Darwin) echo darwin ;;
    Linux)  echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) err "unsupported OS: $uname_s (run from PowerShell on Windows: see RELEASE.md)" ;;
  esac
}

detect_arch() {
  uname_m=$(uname -m 2>/dev/null || echo unknown)
  case "$uname_m" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64)  echo x64 ;;
    *) err "unsupported arch: $uname_m" ;;
  esac
}

OS=$(detect_os)
ARCH=$(detect_arch)
TARGET="${OS}-${ARCH}"

# happen-bridge currently builds: darwin-arm64, darwin-x64, linux-x64, windows-x64.
case "$TARGET" in
  darwin-arm64|darwin-x64|linux-x64|windows-x64) : ;;
  linux-arm64) err "linux-arm64 not yet built. Install from source: see docs/BRIDGE_ONBOARDING.md." ;;
  *) err "no prebuilt binary for $TARGET. Install from source: see docs/BRIDGE_ONBOARDING.md." ;;
esac

if [ "$OS" = "windows" ]; then
  EXT="zip"
else
  EXT="tar.gz"
fi

# ── Resolve version ──────────────────────────────────────────────────────────
# We can't use `releases/latest` here: this repo ships two tag namespaces
# (`bridge-v*` for the daemon and `desktop-v*` for the Tauri app), and
# GitHub's `latest` redirect picks whichever was published most recently
# regardless of prefix. Without filtering, the installer would resolve a
# desktop tag and 404 on the bridge artifact name.
#
# Instead, walk the recent-releases JSON and pick the first published
# (non-draft) `bridge-v*` tag. POSIX-safe: no jq, no gawk-only features.
if [ -z "$VERSION" ]; then
  # Resolve the API URL. Override wins; otherwise derive from a canonical
  # github.com release base. Any other custom `--release-url` without an
  # explicit `--version` is rejected — we'd rather fail loudly than
  # silently hit the wrong host.
  if [ -n "$API_URL_OVERRIDE" ]; then
    API_URL="$API_URL_OVERRIDE"
  else
    case "$RELEASE_BASE" in
      https://github.com/*/releases)
        OWNER_REPO=$(printf '%s\n' "$RELEASE_BASE" | sed 's@https://github.com/@@; s@/releases$@@')
        API_URL="https://api.github.com/repos/${OWNER_REPO}/releases?per_page=30"
        ;;
      *)
        err "custom --release-url requires an explicit --version (got: $RELEASE_BASE)"
        ;;
    esac
  fi

  # `set -e` is on; allow API fetch failure without killing the script so we
  # can give a friendlier error message than curl's default.
  API_RESP=""
  if command -v curl >/dev/null 2>&1; then
    API_RESP=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API_URL" 2>/dev/null) || API_RESP=""
  elif command -v wget >/dev/null 2>&1; then
    API_RESP=$(wget -q --header="Accept: application/vnd.github+json" -O - "$API_URL" 2>/dev/null) || API_RESP=""
  else
    err "neither curl nor wget found in PATH"
  fi
  if [ -z "$API_RESP" ]; then
    err "couldn't query $API_URL (network/rate-limit). Override with --version."
  fi

  # Pick the first published (non-draft) `bridge-v*` tag from the response.
  # POSIX-only — no gawk match()-array, no jq. The pipeline:
  #   1. tr ',}' to '\n\n'. Each `,` becomes a newline (splitting key/value
  #      pairs onto their own lines) and each `}` *also* becomes a newline.
  #      A release object ends in `},`, so its boundary becomes a double
  #      newline. Pairs *inside* the object are separated by single
  #      newlines.
  #   2. awk in paragraph mode (`RS = ""`) treats each release object as
  #      one record. We then check `draft` and `tag_name` within the same
  #      paragraph — order-independent, so a JSON encoder that puts
  #      `tag_name` before `draft` (like GitHub's API) is handled
  #      identically to one that puts `draft` first.
  # `|| true` so a parse failure doesn't trip `set -e`; the empty-result
  # path falls through to the explicit error below.
  TAG=$(
    printf '%s' "$API_RESP" \
      | tr ',}' '\n\n' \
      | awk '
          BEGIN { RS = ""; FS = "\n" }
          /"tag_name"[[:space:]]*:[[:space:]]*"bridge-v/ {
            if ($0 ~ /"draft"[[:space:]]*:[[:space:]]*true/) next
            for (i = 1; i <= NF; i++) {
              if ($i ~ /"tag_name"[[:space:]]*:[[:space:]]*"bridge-v/) {
                line = $i
                sub(/^.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
                sub(/".*$/, "", line)
                if (line ~ /^bridge-v/) { print line; exit }
              }
            }
          }
        ' || true
  )

  if [ -z "$TAG" ]; then
    err "no published bridge-v* release found at $API_URL. Override with --version."
  fi
  VERSION="${TAG#bridge-v}"
else
  TAG="bridge-v${VERSION}"
fi

ARCHIVE="happen-bridge-${VERSION}-${TARGET}.${EXT}"
ARCHIVE_URL="${RELEASE_BASE}/download/${TAG}/${ARCHIVE}"
CHECKSUM_URL="${ARCHIVE_URL}.sha256"

# ── Pick install dir ─────────────────────────────────────────────────────────
# Prefer /usr/local/bin if writable (or sudoable); fall back to ~/.local/bin
# (which the BridgeSection.tsx reads via HAPPEN_BRIDGE_BIN).
pick_install_dir() {
  if [ -w /usr/local/bin ] 2>/dev/null; then
    echo /usr/local/bin
    return
  fi
  # Note: we don't auto-elevate; if /usr/local/bin isn't writable we drop into
  # ~/.local/bin so curl|sh stays non-interactive.
  if [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    echo "$HOME/.local/bin"
    return
  fi
  err "couldn't find a writable install dir (tried /usr/local/bin and ~/.local/bin)"
}

INSTALL_DIR=$(pick_install_dir)
INSTALL_PATH="${INSTALL_DIR}/happen-bridge"

# ── Dry-run short-circuit ────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN — no files written."
  echo "target:        $TARGET"
  echo "version:       $VERSION"
  echo "archive url:   $ARCHIVE_URL"
  echo "checksum url:  $CHECKSUM_URL"
  echo "install path:  $INSTALL_PATH"
  exit 0
fi

# ── Download + verify ────────────────────────────────────────────────────────
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t happen-bridge)
trap 'rm -rf "$TMP"' EXIT INT TERM

info "downloading $ARCHIVE_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --retry 3 -o "$TMP/$ARCHIVE" "$ARCHIVE_URL"
  curl -fsSL --retry 3 -o "$TMP/$ARCHIVE.sha256" "$CHECKSUM_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q --tries=3 -O "$TMP/$ARCHIVE" "$ARCHIVE_URL"
  wget -q --tries=3 -O "$TMP/$ARCHIVE.sha256" "$CHECKSUM_URL"
fi

info "verifying SHA-256"
EXPECTED=$(awk '{print $1}' "$TMP/$ARCHIVE.sha256")
if command -v shasum >/dev/null 2>&1; then
  ACTUAL=$(shasum -a 256 "$TMP/$ARCHIVE" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL=$(sha256sum "$TMP/$ARCHIVE" | awk '{print $1}')
else
  err "neither shasum nor sha256sum found in PATH"
fi
if [ "$EXPECTED" != "$ACTUAL" ]; then
  err "SHA-256 mismatch! expected=$EXPECTED actual=$ACTUAL — refusing to install."
fi

# ── Unpack + install ─────────────────────────────────────────────────────────
info "unpacking"
if [ "$EXT" = "zip" ]; then
  command -v unzip >/dev/null 2>&1 || err "unzip required for windows archives"
  unzip -q "$TMP/$ARCHIVE" -d "$TMP/unpack"
  BIN_PATH=$(find "$TMP/unpack" -name 'happen-bridge*' -type f | head -1)
else
  mkdir "$TMP/unpack"
  tar -xzf "$TMP/$ARCHIVE" -C "$TMP/unpack"
  BIN_PATH=$(find "$TMP/unpack" -name 'happen-bridge' -type f | head -1)
fi
[ -n "$BIN_PATH" ] || err "happen-bridge binary not found in archive"

info "installing to $INSTALL_PATH"
# Idempotent: overwrite atomically via mv (rename is atomic on the same FS).
mv "$BIN_PATH" "${INSTALL_PATH}.new"
chmod +x "${INSTALL_PATH}.new"
mv "${INSTALL_PATH}.new" "$INSTALL_PATH"

# ── Warn if INSTALL_DIR isn't on PATH ────────────────────────────────────────
case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) info "warning: $INSTALL_DIR is not on PATH. Add it to your shell rc (e.g. ~/.zshrc): export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac

info "done. Run \`happen-bridge --version\` to verify."
