// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The "Icons" menu bar appearance: CPU, GPU, RAM and disk usage as one icon
/// each with a colored gauge on its right that fills with the reading, and
/// the battery as a battery shape with its percentage inside.
///
/// The glyphs come from one icon family (MenuBarMetricGlyphs) and draw in the
/// label color so they follow light and dark menu bars; only the gauges and
/// the battery fill carry color.
extension MenuBarRenderer {
    private static let ringCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    /// Usage rings move in 2% steps, so a jittery reading reuses images.
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

    static func ringColor(for label: String) -> NSColor {
        switch label {
        case "CPU": return NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)  // blue
        case "GPU": return NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)  // green
        case "RAM": return NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1)  // purple
        default: return NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1)     // orange (disk)
        }
    }

    /// The glyph on the left, and a gauge arc hugging its right side that
    /// fills from the bottom up with the reading.
    static func ringImage(label: String, fraction: Double?, style: MenuBarBlockStyle) -> NSImage {
        let height: CGFloat = style == .readable ? 22 : 20
        let glyphSide = MenuBarMetricGlyphs.side
        let gaugeWidth: CGFloat = 2.2
        let radius: CGFloat = glyphSide / 2 + 4
        let sweep: CGFloat = 55       // degrees either side of three o'clock
        let center = NSPoint(x: 1 + glyphSide / 2, y: height / 2)
        let width = ceil(center.x + radius + gaugeWidth / 2 + 0.5)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: -sweep, endAngle: sweep)
            track.lineWidth = gaugeWidth
            track.lineCapStyle = .round
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            track.stroke()

            if let fraction, fraction > 0 {
                let level = NSBezierPath()
                level.appendArc(withCenter: center, radius: radius, startAngle: -sweep,
                                endAngle: -sweep + 2 * sweep * CGFloat(min(fraction, 1)))
                level.lineWidth = gaugeWidth
                level.lineCapStyle = .round
                ringColor(for: label).setStroke()
                level.stroke()
            }

            if let glyph = MenuBarMetricGlyphs.image(for: label) {
                let box = NSRect(x: center.x - glyphSide / 2, y: center.y - glyphSide / 2,
                                 width: glyphSide, height: glyphSide)
                // Tinted on its own so the fill does not spill onto the gauge.
                let tinted = NSImage(size: box.size, flipped: false) { bounds in
                    glyph.draw(in: bounds)
                    NSColor.labelColor.set()
                    bounds.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: box)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = fraction.map { "\(label) \(Int(($0 * 100).rounded()))%" } ?? label
        return image
    }

    /// A battery with the percentage inside: green, red when low, and a bolt
    /// in front of the number while charging.
    static func ringBatteryImage(percent: Int, isCharging: Bool, isLow: Bool, style: MenuBarBlockStyle) -> NSImage {
        let height: CGFloat = style == .readable ? 22 : 20
        // The body is as tall as a glyph's square minus its padding, so it
        // lines up with the CPU, GPU and RAM icons beside it.
        let bodySize = NSSize(width: 28, height: MenuBarMetricGlyphs.side - 2)
        let nubWidth: CGFloat = 2
        let size = NSSize(width: bodySize.width + nubWidth + 1.5, height: height)
        let low = isLow || (percent <= 20 && !isCharging)
        let fillColor = low
            ? NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
            : NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)

        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 0.6, y: (height - bodySize.height) / 2, width: bodySize.width, height: bodySize.height)
            let outline = NSBezierPath(roundedRect: body.insetBy(dx: MenuBarMetricGlyphs.stroke / 2,
                                                                 dy: MenuBarMetricGlyphs.stroke / 2),
                                       xRadius: 3, yRadius: 3)
            outline.lineWidth = MenuBarMetricGlyphs.stroke
            NSColor.labelColor.setStroke()
            outline.stroke()

            let nub = NSRect(x: body.maxX + 0.8, y: body.midY - 2.5, width: nubWidth, height: 5)
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: nub, xRadius: 1, yRadius: 1).fill()

            let inner = body.insetBy(dx: MenuBarMetricGlyphs.stroke + 0.9, dy: MenuBarMetricGlyphs.stroke + 0.9)
            let fillWidth = max(2.4, inner.width * CGFloat(percent) / 100)
            fillColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height),
                         xRadius: 1.6, yRadius: 1.6).fill()

            // Drawn twice through complementary clips: white over the fill,
            // the label color over the empty part, so every digit reads in
            // light and dark menu bars whatever the charge.
            let fillRect = NSRect(x: inner.minX, y: body.minY, width: fillWidth, height: body.height)
            let emptyRect = NSRect(x: inner.minX + fillWidth, y: body.minY,
                                   width: body.maxX - inner.minX - fillWidth, height: body.height)
            for (clip, color) in [(fillRect, NSColor.white), (emptyRect, NSColor.labelColor)] {
                NSGraphicsContext.saveGraphicsState()
                clip.clip()
                drawBatteryLabel(percent: percent, isCharging: isCharging, color: color, in: inner)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Battery \(percent)%"
        return image
    }

    /// The number, with a bolt in front while charging, centered in the
    /// battery's inner area and sized to fit it.
    private static func drawBatteryLabel(percent: Int, isCharging: Bool, color: NSColor, in inner: NSRect) {
        let boltWidth: CGFloat = isCharging ? 5 : 0
        let font = NSFont.systemFont(ofSize: percent == 100 && isCharging ? 7 : 8, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let text = "\(percent)%" as NSString
        let textSize = text.size(withAttributes: attributes)
        var x = inner.midX - (textSize.width + boltWidth) / 2
        if isCharging {
            let config = NSImage.SymbolConfiguration(pointSize: 6.5, weight: .heavy)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                bolt.draw(in: NSRect(x: x, y: inner.midY - bolt.size.height / 2,
                                     width: bolt.size.width, height: bolt.size.height))
            }
            x += boltWidth
        }
        text.draw(at: NSPoint(x: x, y: inner.midY - textSize.height / 2), withAttributes: attributes)
    }
}
