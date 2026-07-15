# Homebrew formula for Eyebreak — the native (no-SwiftBar) menu-bar app.
#
#   brew install mirxomitov/eyebreak-swiftbar/eyebreak
#   brew services start eyebreak      # run it now and at every login
#
# Building from source means the app is compiled on the user's own machine, so it
# needs no Developer ID signing/notarization to get past Gatekeeper. No SwiftBar,
# no separate deploy step — this is the one-stop native install.
class Eyebreak < Formula
  desc "Native menu-bar 20-20-20 eye-break timer with a full-screen break blocker"
  homepage "https://github.com/Mirxomitov/eyebreak-swiftbar"
  license "MIT"
  head "https://github.com/Mirxomitov/eyebreak-swiftbar.git", branch: "main"

  # For a tagged release, publish v1.2.0 and fill in the sha256:
  #   url "https://github.com/Mirxomitov/eyebreak-swiftbar/archive/refs/tags/v1.2.0.tar.gz"
  #   sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  #   version "1.2.0"

  depends_on :macos

  def install
    # build.sh compiles native/Eyebreak.swift into a proper Eyebreak.app bundle
    # (Info.plist + bundle id, which the app needs for notifications).
    system "native/build.sh", "#{buildpath}/out"
    libexec.install "#{buildpath}/out/Eyebreak.app"

    # `eyebreak` launches the app via LaunchServices (or `eyebreak --quit-others`
    # style flags pass straight through to a fresh instance).
    (bin/"eyebreak").write <<~SH
      #!/bin/bash
      exec /usr/bin/open "#{opt_libexec}/Eyebreak.app" "$@"
    SH
  end

  # `brew services start eyebreak` runs the app now and at login via a
  # Homebrew-managed LaunchAgent — no manual login-item setup.
  service do
    run [opt_libexec/"Eyebreak.app/Contents/MacOS/Eyebreak"]
    keep_alive false
    log_path var/"log/eyebreak.log"
    error_log_path var/"log/eyebreak.log"
  end

  def caveats
    <<~EOS
      Start Eyebreak now and at every login:

        brew services start eyebreak

      Or launch it once (no auto-start):

        eyebreak

      Look for the 👀 icon in your menu bar. State lives in ~/.eyebreak (shared
      with the SwiftBar version, if you ever used it).
    EOS
  end

  test do
    assert_path_exists libexec/"Eyebreak.app/Contents/MacOS/Eyebreak"
    # The headless stats hook must run and print a report line.
    output = shell_output("#{libexec}/Eyebreak.app/Contents/MacOS/Eyebreak --print-stats")
    assert_match "total=", output
  end
end
