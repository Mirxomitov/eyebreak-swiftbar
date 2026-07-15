// eyebreak-blocker — a full-screen break blocker for the eyebreak-swiftbar timer.
//
// The bash timer stays the brain; this is just the "screen" it puts up during a
// break. It blacks out every display, shows a live countdown and a quote on the
// primary one, and dismisses on its own when the break ends — or immediately when
// the user presses ⌥⇧⎋ (Option+Shift+Escape).
//
// Built as a single file with `swiftc blocker.swift -o eyebreak-blocker`; it runs
// as an accessory (no Dock icon) so it can be launched from SwiftBar's plugin.
//
// Usage: eyebreak-blocker --seconds 120 --quote "Look 20 feet away."

import Cocoa

// MARK: - Argument parsing

// Defaults keep the blocker useful even if launched with no arguments.
var seconds = 120
var quote = "Look at something at least 20 feet away."

do {
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--seconds":
            if i + 1 < args.count, let n = Int(args[i + 1]), n > 0 { seconds = n }
            i += 2
        case "--quote":
            if i + 1 < args.count { quote = args[i + 1] }
            i += 2
        default:
            i += 1
        }
    }
}

// MARK: - Blocker controller

final class Blocker: NSObject {
    private var windows: [NSWindow] = []
    private var remaining: Int
    private var timer: Timer?
    private var keyMonitor: Any?
    private let countdownLabel = NSTextField(labelWithString: "")
    private let quoteText: String

    init(seconds: Int, quote: String) {
        self.remaining = seconds
        self.quoteText = quote
        super.init()
    }

    func start() {
        // One black window per display. CGShieldingWindowLevel() sits above the
        // menu bar and Dock, so the cover is total — no peeking at work underneath.
        let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        let primary = NSScreen.main

        for screen in NSScreen.screens {
            let window = NSWindow(
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
            if screen == primary {
                window.contentView = buildContentView(size: screen.frame.size)
            }

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        tick() // paint the initial countdown before the first timer fire

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.onSecond()
        }

        // The blocker window is key while it's up, so a local monitor is enough to
        // catch the skip chord — no Accessibility permission needed. keyCode 53 is
        // Escape; we require exactly Option+Shift so it can't be hit by accident.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 && mods == [.option, .shift] {
                self?.dismiss()
                return nil // swallow the event
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContentView(size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let title = NSTextField(labelWithString: "Eye break")
        title.font = .systemFont(ofSize: 34, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.85)
        title.alignment = .center

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 120, weight: .thin)
        countdownLabel.textColor = .white
        countdownLabel.alignment = .center

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

        let stack = NSStackView(views: [title, countdownLabel, quoteLabel, hint])
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
        if remaining <= 0 {
            dismiss()
        } else {
            tick()
        }
    }

    private func tick() {
        let m = remaining / 60
        let s = remaining % 60
        countdownLabel.stringValue = String(format: "%02d:%02d", m, s)
    }

    private func dismiss() {
        timer?.invalidate()
        timer = nil
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        NSApp.terminate(nil)
    }
}

// MARK: - App bootstrap

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, launchable from a background parent

let blocker = Blocker(seconds: seconds, quote: quote)

// Defer start until the run loop is up so windows and the key monitor attach cleanly.
DispatchQueue.main.async {
    blocker.start()
}

app.run()
