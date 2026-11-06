// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The date and time as a Vorssaint menu bar item, so it can sit among the
/// readings and be arranged with them: two lines, the time large below and
/// a compact date above, formatted for the current locale and the system's
/// 12/24-hour choice from the `menuBarClockDateFormat` ("MdEEE": "11/6
/// (목)") and `menuBarClockTimeFormat` ("jmm": "15:42") templates. An empty
/// date template leaves the time alone on one line. `menuBarClock -bool NO`
/// turns the item off at the next launch.
final class MenuBarClockController {
    private let statusItem: NSStatusItem
    private let dateFormatter = DateFormatter()
    private let timeFormatter = DateFormatter()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// A right click opens the app's context menu like every other item.
    var onRightClick: ((NSStatusBarButton?) -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "VorssaintMenuBarClock"
        for formatter in [dateFormatter, timeFormatter] { formatter.locale = .autoupdatingCurrent }
        dateFormatter.setLocalizedDateFormatFromTemplate(
            UserDefaults.standard.string(forKey: "menuBarClockDateFormat") ?? "MdEEE")
        timeFormatter.setLocalizedDateFormatFromTemplate(
            UserDefaults.standard.string(forKey: "menuBarClockTimeFormat") ?? "jmm")
        if let button = statusItem.button {
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
        let date = dateFormatter.dateFormat.isEmpty ? "" : dateFormatter.string(from: now)
        statusItem.button?.image = Self.image(date: date, time: timeFormatter.string(from: now))
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

    /// The two lines as one template image, so macOS tints it like its own
    /// items and dims it with them. The time is the larger line; the date
    /// sits above it a little lighter. Height matches the readings (22 pt).
    static func image(date: String, time: String) -> NSImage {
        var timeFont = NSFont.monospacedDigitSystemFont(ofSize: date.isEmpty ? 12.5 : 11, weight: .bold)
        if let rounded = timeFont.fontDescriptor.withDesign(.rounded) {
            timeFont = NSFont(descriptor: rounded, size: timeFont.pointSize) ?? timeFont
        }
        let timeAttributes: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.black, .kern: -0.3]
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.75), .kern: -0.1]
        let timeSize = (time as NSString).size(withAttributes: timeAttributes)
        let dateSize = (date as NSString).size(withAttributes: dateAttributes)
        let width = ceil(max(timeSize.width, dateSize.width)) + 2
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            if date.isEmpty {
                (time as NSString).draw(at: NSPoint(x: (width - timeSize.width) / 2, y: (22 - timeSize.height) / 2),
                                        withAttributes: timeAttributes)
            } else {
                (time as NSString).draw(at: NSPoint(x: (width - timeSize.width) / 2, y: 0.5), withAttributes: timeAttributes)
                (date as NSString).draw(at: NSPoint(x: (width - dateSize.width) / 2, y: 21.5 - dateSize.height),
                                        withAttributes: dateAttributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { onRightClick?(statusItem.button) }
    }
}
