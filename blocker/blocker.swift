// eyebreak-blocker — a full-screen break blocker for the eyebreak-swiftbar timer.
//
// The bash timer stays the brain; this is just the "screen" it puts up during a
// break. It blacks out every display, shows a live countdown and a quote on the
// primary one, and dismisses on its own when the break ends — or immediately when
// the user presses ⌥⇧⎋ (Option+Shift+Escape). On an early skip it can tell the
// bash timer to end the break too, so the menu-bar clock doesn't keep counting.
//
// Built as a single file with `swiftc blocker.swift -o eyebreak-blocker`; it runs
// as an accessory (no Dock icon) so it can be launched from SwiftBar's plugin.
//
// Usage: eyebreak-blocker --seconds 120 --quote "Look 20 feet away." \
//                         [--skip-exec /path/to/eyebreak-ctl.sh]

import Cocoa

// MARK: - Argument parsing

// Defaults keep the blocker useful even if launched with no arguments.
var seconds = 120
var quote = "Look at something at least 20 feet away."
var skipExec: String? = nil
let maxSeconds = 3600 // clamp so a fat-fingered value can't block the screen forever

do {
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--seconds":
            if i + 1 < args.count, let n = Int(args[i + 1]), n > 0 { seconds = min(n, maxSeconds) }
            i += 2
        case "--quote":
            if i + 1 < args.count { quote = args[i + 1] }
            i += 2
        case "--skip-exec":
            if i + 1 < args.count { skipExec = args[i + 1] }
            i += 2
        default:
            i += 1
        }
    }
}

// MARK: - A borderless window that can still take key input

// A plain borderless NSWindow returns canBecomeKey == false, so it never becomes
// the key window and the local key monitor never sees ⌥⇧⎋. Overriding these two
// makes the shield window focusable, which is what lets the skip chord work.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Blocker controller

final class Blocker: NSObject {
    private var windows: [NSWindow] = []
    private var remaining: Int
    private var timer: Timer?
    private var keyMonitor: Any?
    private var countdownLabel = NSTextField(labelWithString: "")
    private let quoteText: String
    private let skipExec: String?

    init(seconds: Int, quote: String, skipExec: String?) {
        self.remaining = seconds
        self.quoteText = quote
        self.skipExec = skipExec
        super.init()
    }

    func start() {
        buildWindows()
        tick() // paint the initial countdown before the first timer fire

        // Schedule in .common modes so the countdown (and the auto-dismiss it
        // drives) keep firing even while the run loop is in a tracking mode.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.onSecond() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // The shield window is key while it's up, so a local monitor is enough to
        // catch the skip chord — no Accessibility permission needed. keyCode 53 is
        // Escape; we require exactly Option+Shift so it can't be hit by accident.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 && mods == [.option, .shift] {
                self?.dismiss(skipped: true)
                return nil // swallow the event
            }
            return event
        }

        // Re-cover the desktop if displays change mid-break (monitor plugged in,
        // resolution change, wake) — otherwise a new display would be uncovered.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screensChanged() {
        buildWindows()
        tick()
    }

    private func buildWindows() {
        // Tear down any existing shields first so a rebuild doesn't leak windows.
        for w in windows { w.orderOut(nil) }
        windows.removeAll()

        // CGShieldingWindowLevel() sits above the menu bar and Dock, so the cover
        // is total. NSScreen.main is the focused screen and can be nil, so fall
        // back to the first screen; match it by screen number, not object identity.
        let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        let primary = NSScreen.main ?? NSScreen.screens.first
        var uiAttached = false

        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = shieldLevel
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: true)

            // Only the primary display carries the UI; the rest stay solid black
            // so a second monitor can't be used to keep working through the break.
            if !uiAttached && sameScreen(screen, primary) {
                window.contentView = buildContentView(size: screen.frame.size)
                window.makeKeyAndOrderFront(nil)
                uiAttached = true
            } else {
                window.orderFront(nil)
            }
            windows.append(window)
        }

        // If the primary couldn't be matched (nil / identity gap), the countdown
        // and skip hint would be invisible — attach the UI to the first shield so
        // the user is never left with an all-black screen and no guidance.
        if !uiAttached, let first = windows.first {
            first.contentView = buildContentView(size: first.frame.size)
            first.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func sameScreen(_ a: NSScreen, _ b: NSScreen?) -> Bool {
        guard let b = b else { return false }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let an = a.deviceDescription[key] as? NSNumber
        let bn = b.deviceDescription[key] as? NSNumber
        return an != nil && an == bn
    }

    private func buildContentView(size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let title = NSTextField(labelWithString: "Eye break")
        title.font = .systemFont(ofSize: 34, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.85)
        title.alignment = .center

        // Fresh label each build so a rebuilt view hierarchy doesn't reuse a view
        // that's still parented in the old one.
        let countdown = NSTextField(labelWithString: "")
        countdown.font = .monospacedDigitSystemFont(ofSize: 120, weight: .thin)
        countdown.textColor = .white
        countdown.alignment = .center
        countdownLabel = countdown

        let quoteLabel = NSTextField(wrappingLabelWithString: quoteText)
        quoteLabel.font = .systemFont(ofSize: 24, weight: .regular)
        quoteLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        quoteLabel.alignment = .center
        quoteLabel.maximumNumberOfLines = 4
        quoteLabel.preferredMaxLayoutWidth = min(size.width * 0.6, 900)

        let hint = NSTextField(labelWithString: "Look at something ~20 feet away  ·  ⌥⇧⎋ to skip")
        hint.font = .systemFont(ofSize: 15, weight: .regular)
        hint.textColor = NSColor.white.withAlphaComponent(0.4)
        hint.alignment = .center

        let stack = NSStackView(views: [title, countdown, quoteLabel, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            quoteLabel.widthAnchor.constraint(lessThanOrEqualToConstant: min(size.width * 0.6, 900)),
        ])

        return container
    }

    private func onSecond() {
        remaining -= 1
        tick() // paint the new value (including the final 00:00) before deciding
        if remaining <= 0 {
            dismiss(skipped: false)
        }
    }

    private func tick() {
        let shown = max(remaining, 0)
        let m = shown / 60
        let s = shown % 60
        countdownLabel.stringValue = String(format: "%02d:%02d", m, s)
    }

    private func dismiss(skipped: Bool) {
        timer?.invalidate()
        timer = nil
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        for w in windows { w.orderOut(nil) }
        windows.removeAll()

        // On an early skip, tell the bash timer to end the break now so its clock
        // and stats stay in sync with what the user just did. Natural completion
        // (remaining hit 0) is left to the plugin's own tick, which handles it.
        if skipped, let exec = skipExec, !exec.isEmpty {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exec)
            p.arguments = ["work"]
            try? p.run() // fire-and-forget; the child outlives us
        }

        NSApp.terminate(nil)
    }
}

// MARK: - App bootstrap

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, launchable from a background parent

let blocker = Blocker(seconds: seconds, quote: quote, skipExec: skipExec)

// Defer start until the run loop is up so windows and the key monitor attach cleanly.
DispatchQueue.main.async {
    blocker.start()
}

app.run()
