// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The date and time as a Vorssaint menu bar item, so it can sit among the
/// readings and be arranged with them. Formatted for the current locale and
/// the system's 12/24-hour choice from the `menuBarClockFormat` template
/// (default "MMMdEEEjmm": "11월 6일 (목) 15:42"); `menuBarClock -bool NO`
/// turns the item off at the next launch.
final class MenuBarClockController {
    private let statusItem: NSStatusItem
    private let formatter = DateFormatter()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// A right click opens the app's context menu like every other item.
    var onRightClick: ((NSStatusBarButton?) -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "VorssaintMenuBarClock"
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(
            UserDefaults.standard.string(forKey: "menuBarClockFormat") ?? "MMMdEEEjmm")
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // The clock, time zone or locale changing, and waking from sleep, all
        // leave the shown time stale until the next minute.
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tick() })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() })
        tick()
    }

    func tearDown() {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Shows the current time and arms a timer for the next minute boundary;
    /// nothing runs in between.
    private func tick() {
        let now = Date()
        statusItem.button?.title = formatter.string(from: now)
        statusItem.button?.toolTip = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .short)
        let nextMinute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0),
                                                   matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        timer?.invalidate()
        let timer = Timer(fire: nextMinute.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { onRightClick?(statusItem.button) }
    }
}
