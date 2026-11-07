// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The date and time as a menu bar reading (MenuBarMetric.clock), placed and
/// ordered with the others: two lines, the time large below and a compact
/// date above, formatted for the current locale from the
/// `menuBarClockDateFormat` ("MdEEE": "11/6 (목)") and
/// `menuBarClockTimeFormat` ("Hmm": "15:42", always 24-hour; "jmm" follows
/// the system's hour cycle) templates. An empty date template leaves the time
/// alone on one line. It is shown and ordered from the readings tiles in
/// Settings like any reading; the readings refresh with every monitor tick,
/// which carries the minute over within a couple of seconds.
enum MenuBarClock {
    private static let dateFormatter: DateFormatter = formatter(key: "menuBarClockDateFormat", template: "MdEEE")
    private static let timeFormatter: DateFormatter = formatter(key: "menuBarClockTimeFormat", template: "Hmm")
    private static let cache = NSCache<NSString, NSImage>()

    private static func formatter(key: String, template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(UserDefaults.standard.string(forKey: key) ?? template)
        return formatter
    }

    /// The two lines for a moment; the date is empty when its template is.
    static func strings(at now: Date = Date()) -> (date: String, time: String) {
        (dateFormatter.dateFormat.isEmpty ? "" : dateFormatter.string(from: now), timeFormatter.string(from: now))
    }

    /// The image for this minute; one per minute is drawn, the rest reuse it.
    static func image(at now: Date = Date()) -> NSImage {
        let (date, time) = strings(at: now)
        let key = "\(date)|\(time)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = image(date: date, time: time)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Drawn in the label color at draw time, like the gauges beside it, so
    /// it follows light and dark menu bars. Height matches the readings (22 pt).
    static func image(date: String, time: String) -> NSImage {
        var timeFont = NSFont.monospacedDigitSystemFont(ofSize: date.isEmpty ? 12.5 : 11, weight: .bold)
        if let rounded = timeFont.fontDescriptor.withDesign(.rounded) {
            timeFont = NSFont(descriptor: rounded, size: timeFont.pointSize) ?? timeFont
        }
        let dateFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
        let timeSize = (time as NSString).size(withAttributes: [.font: timeFont, .kern: -0.3])
        let dateSize = (date as NSString).size(withAttributes: [.font: dateFont, .kern: -0.1])
        let width = ceil(max(timeSize.width, dateSize.width)) + 2
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            let timeAttributes: [NSAttributedString.Key: Any] = [.font: timeFont, .kern: -0.3, .foregroundColor: NSColor.labelColor]
            let dateAttributes: [NSAttributedString.Key: Any] = [.font: dateFont, .kern: -0.1,
                                                                 .foregroundColor: NSColor.labelColor.withAlphaComponent(0.75)]
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
        image.isTemplate = false
        image.accessibilityDescription = "\(date) \(time)"
        return image
    }
}
