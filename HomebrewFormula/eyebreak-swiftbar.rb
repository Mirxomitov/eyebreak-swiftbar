# Homebrew formula for eyebreak-swiftbar.
#
# This repo doubles as its own tap, so once a release exists users can run:
#
#     brew tap mirxomitov/eyebreak-swiftbar https://github.com/Mirxomitov/eyebreak-swiftbar
#     brew install eyebreak-swiftbar
#
# ...or install the tip of main right now with:
#
#     brew install --HEAD mirxomitov/eyebreak-swiftbar/eyebreak-swiftbar
#
# Homebrew must not write outside its prefix during `install`, so this formula
# only stages the files and compiles the blocker into libexec. The actual copy
# into ~/.eyebreak and the SwiftBar plugin folder happens when the user runs the
# `eyebreak-swiftbar` command it installs — see the caveats.
class EyebreakSwiftbar < Formula
  desc "Menu-bar 20-20-20 eye-break timer with a full-screen break blocker"
  homepage "https://github.com/Mirxomitov/eyebreak-swiftbar"
  license "MIT"
  url "https://github.com/Mirxomitov/eyebreak-swiftbar/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "dae81bbb3543cecef919fa8a27e9fc0251afd98669f6073f35afb84cdabfbbb7"
  version "1.2.0"
  head "https://github.com/Mirxomitov/eyebreak-swiftbar.git", branch: "main"

  # SwiftBar is the menu-bar host this plugin runs inside, but a formula can't
  # depend on a cask (Homebrew rejects `depends_on cask:`), so it's a caveat
  # instead of an automatic dependency.
  depends_on :macos

  def install
    # Compile the full-screen blocker from source. `xcrun swiftc` resolves the
    # active toolchain whether the user has full Xcode or just the CLT.
    system "xcrun", "swiftc", "-O", "blocker/blocker.swift", "-o", "eyebreak-blocker"

    # Stage everything the runtime needs under libexec; the setup command below
    # copies it into place. Ship install.sh too so setup can reuse it verbatim.
    libexec.install "lib", "plugin", "assets", "install.sh", "eyebreak-blocker"

    # A thin launcher: `eyebreak-swiftbar` runs the repo's own installer against
    # the staged copy, and passes the prebuilt blocker so it isn't recompiled.
    (bin/"eyebreak-swiftbar").write <<~SH
      #!/bin/bash
      # Deploy the eyebreak-swiftbar plugin, helpers, and blocker into your home
      # directory and SwiftBar plugin folder. Safe to re-run (upgrades in place).
      set -euo pipefail
      LIBEXEC="#{libexec}"
      DATA_DIR="$HOME/.eyebreak"
      mkdir -p "$DATA_DIR"
      # Reuse the compiled blocker from the Cellar instead of rebuilding it.
      install -m 0755 "$LIBEXEC/eyebreak-blocker" "$DATA_DIR/eyebreak-blocker"
      # Run the repo installer for the scripts, quotes, config, and plugin link.
      # It recompiles only if swiftc is present; the line above already placed a
      # working binary, so a missing compiler is harmless here.
      exec "$LIBEXEC/install.sh" "$@"
    SH
  end

  def caveats
    <<~EOS
      This plugin needs SwiftBar. If you don't have it yet:

        brew install --cask swiftbar

      Then launch SwiftBar once (so it creates ~/SwiftBar/Plugins) and deploy the
      plugin into your home dir and that folder:

        eyebreak-swiftbar

      Finally, open SwiftBar (or "Refresh All") and grant notification permission.

      If your SwiftBar plugin folder isn't ~/SwiftBar/Plugins:

        SWIFTBAR_PLUGIN_DIR="$HOME/path/to/plugins" eyebreak-swiftbar
    EOS
  end

  test do
    assert_predicate libexec/"eyebreak-blocker", :executable?
    assert_path_exists libexec/"plugin/eyebreak.1s.sh"
  end
end
