# This file is the TEMPLATE.
#
# Production formula lives in github.com/Happen-Ai/homebrew-tap (not yet
# created — see backend/bridges/claude-code-daemon/RELEASE.md). It is kept in
# sync by `.github/workflows/bridge-release.yml`'s `publish-tap` job, which
# copies this file into the tap repo and substitutes:
#
#   0.2.4              — semver from the bridge-v* tag
#   6969b42e13009f8ce7dc8aaafffa145bc8cb2c5036f26b95cfc0ac6d8a3641dc  — sha256 of happen-bridge-<VER>-darwin-arm64.tar.gz
#   e085c5ce57fa184caf8ae84c45cd7fa9c2a0990a96e2e3037b3e8516c0af1f79    — sha256 of happen-bridge-<VER>-darwin-x64.tar.gz
#
# The binaries are hosted on the PUBLIC Happen-Ai/homebrew-tap GitHub Release
# (mirrored from the build by the bridge-release workflow), so the formula's
# `url` is publicly downloadable without access to the private monorepo.
class HappenBridge < Formula
  desc "Local daemon that streams Claude Code CLI to Happen AI over WebSocket"
  homepage "https://happen-ai.com"
  version "0.2.4"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/Happen-Ai/homebrew-tap/releases/download/bridge-v#{version}/happen-bridge-#{version}-darwin-arm64.tar.gz"
      sha256 "6969b42e13009f8ce7dc8aaafffa145bc8cb2c5036f26b95cfc0ac6d8a3641dc"
    end
    on_intel do
      url "https://github.com/Happen-Ai/homebrew-tap/releases/download/bridge-v#{version}/happen-bridge-#{version}-darwin-x64.tar.gz"
      sha256 "e085c5ce57fa184caf8ae84c45cd7fa9c2a0990a96e2e3037b3e8516c0af1f79"
    end
  end

  # Bottle blocks — once ops publishes a bottle to the tap's GitHub Packages
  # registry (`brew bottle`-generated), uncomment and fill in. The `:cellar`
  # value should match what `brew bottle` emits.
  #
  # bottle do
  #   root_url "https://ghcr.io/v2/happen-ai/homebrew-tap"
  #   sha256 cellar: :any_skip_relocation, arm64_sonoma: "<BOTTLE_ARM_SHA>"
  #   sha256 cellar: :any_skip_relocation, sonoma:       "<BOTTLE_X64_SHA>"
  # end

  def install
    bin.install "happen-bridge"
    # Interim until Apple Developer ID signing lands (see RELEASE.md §3):
    # strip the `com.apple.quarantine` xattr Gatekeeper attaches to downloaded
    # archives so the unsigned binary runs without a manual right-click → Open.
    # `system "xattr"` swallows ENOENT (older brews installed via the bottle
    # path may have no xattr to clear), `|| true` keeps `brew install` exit 0.
    on_macos do
      system "/usr/bin/xattr", "-d", "com.apple.quarantine", bin/"happen-bridge", err: :out
    rescue
      nil
    end
  end

  def caveats
    <<~EOS
      happen-bridge is currently shipped unsigned — Apple Developer ID work is
      pending. The formula strips the macOS quarantine attribute on install so
      the binary runs without manual intervention. If you ever see a
      Gatekeeper warning, run:
        sudo xattr -d com.apple.quarantine $(which happen-bridge)
      See https://github.com/Happen-Ai/homebrew-tap/blob/main/MACOS_UNSIGNED_BINARY.md for details.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/happen-bridge version")
  end
end
