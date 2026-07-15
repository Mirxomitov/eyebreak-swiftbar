// Eyebreak — a native macOS menu-bar 20-20-20 eye-break timer.
//
// This is the standalone (no-SwiftBar) version: one NSStatusItem process that
// owns the timer, the menu, the full-screen break blocker, the stats, and the
// config — the same behaviour the SwiftBar plugin has, but self-contained so it
// installs with a single `brew install` and runs as its own login item.
//
// State lives in ~/.eyebreak (config, quotes.txt, stats.csv) in the SAME formats
// as the SwiftBar version, so history and settings carry over between the two.
//
// Build: assembled into Eyebreak.app by native/build.sh (or the Homebrew formula).

import Cocoa
import UserNotifications

// MARK: - Paths

enum Paths {
    // EYEBREAK_DIR overrides the data directory (used for isolated testing, and
    // handy if someone wants their state somewhere other than ~/.eyebreak).
    static let dir: String = {
        if let d = ProcessInfo.processInfo.environment["EYEBREAK_DIR"], !d.isEmpty {
            return (d as NSString).expandingTildeInPath
        }
        return NSString(string: "~/.eyebreak").expandingTildeInPath
    }()
    static let config = dir + "/config"
    static let quotes = dir + "/quotes.txt"
    static let stats = dir + "/stats.csv"

    static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
}

// MARK: - Config

struct Config {
    var workMinutes = 20
    var breakMinutes = 2
    var showBlocker = true

    // Phase lengths in seconds. EYEBREAK_WORK_SECONDS / EYEBREAK_BREAK_SECONDS
    // override the minute config (used by the test harness to drive a full cycle
    // in seconds); otherwise it's just minutes × 60.
    var workSeconds: Int {
        if let v = ProcessInfo.processInfo.environment["EYEBREAK_WORK_SECONDS"], let n = Int(v), n >= 1 { return n }
        return workMinutes * 60
    }
    var breakSeconds: Int {
        if let v = ProcessInfo.processInfo.environment["EYEBREAK_BREAK_SECONDS"], let n = Int(v), n >= 1 { return n }
        return breakMinutes * 60
    }

    static func load() -> Config {
        var c = Config()
        guard let text = try? String(contentsOfFile: Paths.config, encoding: .utf8) else { return c }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || !line.contains("=") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "WORK_MINUTES":  if let n = Int(parts[1]), n >= 1 { c.workMinutes = n }
            case "BREAK_MINUTES": if let n = Int(parts[1]), n >= 1 { c.breakMinutes = n }
            case "SHOW_BLOCKER":  c.showBlocker = (parts[1] != "0")
            default: break
            }
        }
        return c
    }

    func save() {
        Paths.ensureDir()
        let text = """
        # Minutes of work between breaks, and minutes per break.
        WORK_MINUTES=\(workMinutes)
        BREAK_MINUTES=\(breakMinutes)
        # Put up the full-screen blocker during a break (1), or just notify (0).
        SHOW_BLOCKER=\(showBlocker ? 1 : 0)

        """
        try? text.write(toFile: Paths.config, atomically: true, encoding: .utf8)
    }
}

// MARK: - Quotes

enum Quotes {
    static let defaults = [
        "Look at something at least 20 feet away for a full 20 seconds.",
        "Your eyes have been focused up close — let them relax into the distance.",
        "Blink slowly a few times. Screens make you blink less than half as often.",
        "Roll your shoulders back and unclench your jaw while you look away.",
        "The work will still be there in two minutes. Your eyes need this.",
        "Find the farthest point you can see and rest your gaze there.",
        "Stand up, look out a window, and let your focus drift to the horizon.",
        "Distance focus relaxes the muscles that near-work keeps tense all day.",
        "Close your eyes for a moment, then open them and look far away.",
        "Every break now is eye strain and headaches you don't get later.",
        "Soften your gaze. There's nothing here you need to stare at.",
        "20 feet, 20 seconds — the cheapest health habit you'll ever keep.",
        "Look away, unfocus, and just notice the room around you.",
    ]

    // Seed the file on first run so users can edit the pool, matching the plugin.
    static func seedIfNeeded() {
        guard !FileManager.default.fileExists(atPath: Paths.quotes) else { return }
        Paths.ensureDir()
        let header = "# Quotes shown on the full-screen break blocker. One per line.\n" +
                     "# Blank lines and lines starting with # are ignored. Edit freely.\n"
        try? (header + defaults.joined(separator: "\n") + "\n").write(toFile: Paths.quotes, atomically: true, encoding: .utf8)
    }

    static func random() -> String {
        let fallback = defaults[0]
        guard let text = try? String(contentsOfFile: Paths.quotes, encoding: .utf8) else { return fallback }
        let usable = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return usable.randomElement() ?? fallback
    }
}

// MARK: - Stats

// Append-only usage log in ~/.eyebreak/stats.csv: "iso,epoch,event" where event
// is break_start | break_end | reset. Byte-compatible with the SwiftBar version.
enum Stats {
    static func log(_ event: String, at date: Date = Date()) {
        Paths.ensureDir()
        let epoch = Int(date.timeIntervalSince1970)
        let iso = isoFormatter.string(from: date)
        let row = "\(iso),\(epoch),\(event)\n"
        if !FileManager.default.fileExists(atPath: Paths.stats) {
            try? "iso,epoch,event\n".write(toFile: Paths.stats, atomically: true, encoding: .utf8)
        }
        if let handle = FileHandle(forWritingAtPath: Paths.stats) {
            handle.seekToEndOfFile()
            handle.write(row.data(using: .utf8)!)
            try? handle.close()
        }
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    struct Report {
        var total = 0, today = 0, last7 = 0, last30 = 0
        var activeDays = 0, currentStreak = 0, longestStreak = 0
        var restSeconds = 0
    }

    // Derive the report from the log the same way eyebreak-stats.sh does.
    static func report() -> Report {
        var r = Report()
        guard let text = try? String(contentsOfFile: Paths.stats, encoding: .utf8) else { return r }
        let cal = Calendar.current
        let now = Date()
        var days = Set<String>()
        var pendingStart: Int? = nil
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"; dayFmt.locale = Locale(identifier: "en_US_POSIX")

        for raw in text.split(separator: "\n").dropFirst() { // drop header
            let cols = raw.split(separator: ",")
            guard cols.count >= 3, let epoch = Int(cols[1]) else { continue }
            let event = String(cols[2])
            let date = Date(timeIntervalSince1970: TimeInterval(epoch))
            switch event {
            case "break_start":
                pendingStart = epoch
            case "break_end":
                r.total += 1
                days.insert(dayFmt.string(from: date))
                if let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day {
                    if daysAgo == 0 { r.today += 1 }
                    if daysAgo < 7 { r.last7 += 1 }
                    if daysAgo < 30 { r.last30 += 1 }
                }
                if let s = pendingStart { r.restSeconds += max(0, epoch - s); pendingStart = nil }
            default:
                break
            }
        }
        r.activeDays = days.count
        (r.currentStreak, r.longestStreak) = streaks(days: days, calendar: cal, now: now, dayFmt: dayFmt)
        return r
    }

    private static func streaks(days: Set<String>, calendar cal: Calendar, now: Date, dayFmt: DateFormatter) -> (Int, Int) {
        guard !days.isEmpty else { return (0, 0) }
        let sorted = days.sorted()
        // Longest run of consecutive calendar days.
        var longest = 1, run = 1
        var prev: Date? = nil
        for d in sorted {
            let date = dayFmt.date(from: d)!
            if let p = prev, cal.dateComponents([.day], from: p, to: date).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = date
        }
        // Current streak: count back from today, falling back to yesterday.
        var cur = 0
        var cursor = cal.startOfDay(for: now)
        if !days.contains(dayFmt.string(from: cursor)) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        while days.contains(dayFmt.string(from: cursor)) {
            cur += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return (cur, longest)
    }
}

// MARK: - A borderless window that can still take key input (for the ⌥⇧⎋ skip)

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Full-screen break blocker (in-process)

final class BlockerController {
    private var windows: [NSWindow] = []
    private var countdownLabel = NSTextField(labelWithString: "")
    private var keyMonitor: Any?
    var onSkip: (() -> Void)?

    var isShowing: Bool { !windows.isEmpty }

    func present(quote: String) {
        dismiss() // never stack
        buildWindows(quote: quote)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 && mods == [.option, .shift] { // ⌥⇧⎋
                self?.onSkip?()
                return nil
            }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func rebuild() {
        guard isShowing else { return }
        let quote = (windows.first?.title).flatMap { _ in Quotes.random() } ?? Quotes.random()
        buildWindows(quote: quote)
    }

    private func buildWindows(quote: String) {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        let primary = NSScreen.main ?? NSScreen.screens.first
        var uiAttached = false

        for screen in NSScreen.screens {
            let window = KeyableWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false, screen: screen)
            window.level = shieldLevel
            window.backgroundColor = .black
            window.isOpaque = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: true)
            if !uiAttached && sameScreen(screen, primary) {
                window.contentView = content(size: screen.frame.size, quote: quote)
                window.makeKeyAndOrderFront(nil)
                uiAttached = true
            } else {
                window.orderFront(nil)
            }
            windows.append(window)
        }
        if !uiAttached, let first = windows.first {
            first.contentView = content(size: first.frame.size, quote: quote)
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

    private func content(size: NSSize, quote: String) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let title = NSTextField(labelWithString: "Eye break")
        title.font = .systemFont(ofSize: 34, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.85)
        title.alignment = .center

        let countdown = NSTextField(labelWithString: countdownLabel.stringValue)
        countdown.font = .monospacedDigitSystemFont(ofSize: 120, weight: .thin)
        countdown.textColor = .white
        countdown.alignment = .center
        countdownLabel = countdown

        let quoteLabel = NSTextField(wrappingLabelWithString: quote)
        quoteLabel.font = .systemFont(ofSize: 24, weight: .regular)
        quoteLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        quoteLabel.alignment = .center
        quoteLabel.maximumNumberOfLines = 4

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

    func update(remaining: Int) {
        let shown = max(remaining, 0)
        countdownLabel.stringValue = String(format: "%02d:%02d", shown / 60, shown % 60)
    }

    func dismiss() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NotificationCenter.default.removeObserver(self)
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }
}

// MARK: - App

enum Phase { case work, breaking }

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var config = Config.load()
    private var phase: Phase = .work
    private var remaining = 0
    private var paused = false
    private var breaks = 0
    private var sessionStart = Date()
    private var timer: Timer?
    private var warned = false
    private let blocker = BlockerController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Quotes.seedIfNeeded()
        requestNotificationAuth()
        remaining = config.workSeconds
        blocker.onSkip = { [weak self] in self?.endBreak(early: true) }
        rebuildMenu()
        updateStatus()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Timer

    private func tick() {
        if paused { return }
        remaining -= 1
        if phase == .breaking {
            blocker.update(remaining: max(remaining, 0))
        } else if !warned && remaining == 5 {
            warned = true
            notify("👀 Eye break in 5 seconds", "Look at something at least 20 feet away.")
        }
        if remaining <= 0 { flip() } else { updateStatus() }
    }

    private func flip() {
        if phase == .work { startBreak() } else { endBreak(early: false) }
    }

    private func startBreak() {
        phase = .breaking
        remaining = config.breakSeconds
        warned = false
        Stats.log("break_start")
        if config.showBlocker {
            blocker.update(remaining: remaining)
            blocker.present(quote: Quotes.random())
        }
        updateStatus(); rebuildMenu()
    }

    private func endBreak(early: Bool) {
        if phase == .breaking {
            breaks += 1
            Stats.log("break_end")
        }
        phase = .work
        remaining = config.workSeconds
        paused = false
        warned = false
        blocker.dismiss()
        if !early { notify("✅ Eye break complete", "Back to work!") }
        updateStatus(); rebuildMenu()
    }

    // MARK: Status bar

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        let clock = String(format: "%02d:%02d", max(remaining, 0) / 60, max(remaining, 0) % 60)
        let icon = paused ? "⏸" : (phase == .breaking ? "☕" : "👀")
        button.title = "\(icon) \(clock)"
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        menu.addItem(header(phase == .breaking ? "On a break" : (paused ? "Paused" : "Working")))
        menu.addItem(header("Completed breaks: \(breaks)"))
        menu.addItem(header(String(format: "Session: %02d:%02d", elapsed / 3600, (elapsed % 3600) / 60)))
        menu.addItem(.separator())

        if phase == .breaking {
            menu.addItem(item("End break now", #selector(endBreakNow)))
        } else {
            menu.addItem(item("Take break now", #selector(takeBreakNow)))
        }
        menu.addItem(item(paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(item("Reset timer", #selector(resetTimer)))
        menu.addItem(.separator())
        menu.addItem(item("Statistics…", #selector(showStats)))
        menu.addItem(.separator())

        let blockerItem = item("Full-screen blocker", #selector(toggleBlocker))
        blockerItem.state = config.showBlocker ? .on : .off
        menu.addItem(blockerItem)
        menu.addItem(item("Edit config…", #selector(editConfig)))
        menu.addItem(item("Edit quotes…", #selector(editQuotes)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Eyebreak", #selector(quit)))
        statusItem.menu = menu
    }

    private func header(_ s: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    // MARK: Actions

    @objc private func takeBreakNow() { if phase == .work { startBreak() } }
    @objc private func endBreakNow() { endBreak(early: true) }

    @objc private func togglePause() {
        paused.toggle()
        updateStatus(); rebuildMenu()
    }

    @objc private func resetTimer() {
        phase = .work
        remaining = config.workSeconds
        breaks = 0
        paused = false
        warned = false
        sessionStart = Date()
        blocker.dismiss()
        Stats.log("reset")
        updateStatus(); rebuildMenu()
    }

    @objc private func toggleBlocker() {
        config.showBlocker.toggle()
        config.save()
        rebuildMenu()
    }

    @objc private func editConfig() {
        config.save() // make sure the file exists to open
        openInEditor(Paths.config)
    }

    @objc private func editQuotes() {
        Quotes.seedIfNeeded()
        openInEditor(Paths.quotes)
    }

    private func openInEditor(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", path] // -t opens in the default text editor
        try? p.run()
    }

    @objc private func showStats() {
        let r = Stats.report()
        let restHours = Double(r.restSeconds) / 3600.0
        let alert = NSAlert()
        alert.messageText = "Eyebreak statistics"
        alert.informativeText = """
        Total breaks:     \(r.total)
        Today:            \(r.today)
        Last 7 days:      \(r.last7)
        Last 30 days:     \(r.last30)

        Active days:      \(r.activeDays)
        Current streak:   \(r.currentStreak) day\(r.currentStreak == 1 ? "" : "s")
        Longest streak:   \(r.longestStreak) day\(r.longestStreak == 1 ? "" : "s")

        Estimated eye-rest: \(String(format: "%.1f", restHours)) hours
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        blocker.dismiss()
        NSApp.terminate(nil)
    }

    // MARK: Notifications

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Bootstrap

// Headless stats dump (test/CI hook) — compute the report and exit without
// bringing up the status item.
if CommandLine.arguments.contains("--print-stats") {
    let r = Stats.report()
    print("total=\(r.total) today=\(r.today) last7=\(r.last7) last30=\(r.last30) " +
          "activeDays=\(r.activeDays) current=\(r.currentStreak) longest=\(r.longestStreak) restSeconds=\(r.restSeconds)")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
