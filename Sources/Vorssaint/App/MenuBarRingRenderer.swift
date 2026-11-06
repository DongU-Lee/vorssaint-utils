// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The "Icons" menu bar appearance: CPU, GPU, RAM and disk usage as a two-tone
/// glyph with a gauge arc hugging its right side, and the battery as a battery
/// outline with its percentage inside.
///
/// Everything draws in the label color, like the system's own items; color
/// only ever marks a warning (high load, low battery), and only on the gauge
/// or the battery number.
extension MenuBarRenderer {
    private static let ringCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    // Gauge geometry, in points.
    private static let gaugeRadius: CGFloat = 7.5        // as tall as the glyph
    private static let gaugeSweep: CGFloat = 70          // degrees either side of three o'clock
    private static let gaugeWidth: CGFloat = 2
    private static let gaugeGap: CGFloat = 1.5           // glyph edge to the arc's inner side
    private static let gaugeMinimumDegrees: CGFloat = 8  // a 0% reading still shows a dot

    /// Usage gauges move in 2% steps, so a jittery reading reuses images.
    static func cachedRingImage(label: String, fraction: Double?, style: MenuBarBlockStyle) -> NSImage {
        let step = fraction.map { Int((MenuBarUsageBarSupport.clampedFraction($0) * 50).rounded()) }
        let key = "ring|\(label)|\(step.map(String.init) ?? "-")|\(style)" as NSString
        if let cached = ringCache.object(forKey: key) { return cached }
        let image = ringImage(label: label, fraction: step.map { Double($0) / 50 }, style: style)
        ringCache.setObject(image, forKey: key)
        return image
    }

    static func cachedRingBatteryImage(percent: Int, isCharging: Bool, isLow: Bool,
                                       style: MenuBarBlockStyle) -> NSImage {
        let percent = max(0, min(100, percent))
        let key = "ringBattery|\(percent)|\(isCharging)|\(isLow)|\(style)" as NSString
        if let cached = ringCache.object(forKey: key) { return cached }
        let image = ringBatteryImage(percent: percent, isCharging: isCharging, isLow: isLow, style: style)
        ringCache.setObject(image, forKey: key)
        return image
    }

    static func ringImage(label: String, fraction: Double?, style: MenuBarBlockStyle) -> NSImage {
        let height: CGFloat = style == .readable ? 22 : 20
        let side = MenuBarMetricGlyphs.side
        let glyphRect = NSRect(x: 0.5, y: (height - side) / 2, width: side, height: side)
        // The arc's ends are its innermost points; place them gaugeGap off the glyph.
        let innerReach = gaugeRadius * cos(gaugeSweep * .pi / 180) - gaugeWidth / 2
        let center = NSPoint(x: glyphRect.maxX + gaugeGap - innerReach, y: height / 2)
        let width = ceil(center.x + gaugeRadius + gaugeWidth / 2 + 0.5)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawGauge(center: center, fraction: fraction)
            if let glyph = MenuBarMetricGlyphs.image(for: label) {
                tinted(glyph, size: glyphRect.size).draw(in: glyphRect)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = fraction.map { "\(label) \(Int(($0 * 100).rounded()))%" } ?? label
        return image
    }

    /// A faint track and the level filling it from the bottom up; orange from
    /// 85%, red from 95%.
    private static func drawGauge(center: NSPoint, fraction: Double?) {
        let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: gaugeRadius, startAngle: -gaugeSweep, endAngle: gaugeSweep)
        track.lineWidth = gaugeWidth
        track.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(isDark ? 0.30 : 0.22).setStroke()
        track.stroke()

        guard let fraction else { return }
        let value = MenuBarUsageBarSupport.clampedFraction(fraction)
        let degrees = max(gaugeMinimumDegrees, 2 * gaugeSweep * CGFloat(value))
        let level = NSBezierPath()
        level.appendArc(withCenter: center, radius: gaugeRadius, startAngle: -gaugeSweep,
                        endAngle: -gaugeSweep + degrees)
        level.lineWidth = gaugeWidth
        level.lineCapStyle = .round
        (value >= 0.95 ? NSColor.systemRed : value >= 0.85 ? NSColor.systemOrange : NSColor.labelColor).setStroke()
        level.stroke()
    }

    /// A battery outline with the percentage inside, the terminal at half
    /// strength. While charging a bolt takes the terminal's place; when low the
    /// number turns red.
    static func ringBatteryImage(percent: Int, isCharging: Bool, isLow: Bool, style: MenuBarBlockStyle) -> NSImage {
        let height: CGFloat = style == .readable ? 22 : 20
        let body = NSRect(x: 0.5, y: (height - 11) / 2, width: 21, height: 11)
        let width = ceil(body.maxX + 1 + 4 + 0.5)
        let low = isLow || (percent <= 20 && !isCharging)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let border: CGFloat = 1.25
            let outline = NSBezierPath(roundedRect: body.insetBy(dx: border / 2, dy: border / 2), xRadius: 3, yRadius: 3)
            outline.lineWidth = border
            NSColor.labelColor.setStroke()
            outline.stroke()

            if isCharging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)) {
                let boltRect = NSRect(x: body.maxX + 0.8, y: body.midY - 3.5, width: 4, height: 7)
                tinted(bolt, size: boltRect.size).draw(in: boltRect)
            } else {
                NSColor.labelColor.withAlphaComponent(0.5).setFill()
                NSBezierPath(roundedRect: NSRect(x: body.maxX + 1, y: body.midY - 2, width: 1.5, height: 4),
                             xRadius: 0.75, yRadius: 0.75).fill()
            }

            var font = NSFont.monospacedDigitSystemFont(ofSize: percent >= 100 ? 7.5 : 8.5, weight: .semibold)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: rounded, size: font.pointSize) ?? font
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: low ? NSColor.systemRed : NSColor.labelColor]
            let text = "\(percent)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                      withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Battery \(percent)%"
        return image
    }

    /// A template image filled with the label color of the current drawing
    /// appearance.
    private static func tinted(_ template: NSImage, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { bounds in
            template.draw(in: bounds)
            NSColor.labelColor.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
    }
}
