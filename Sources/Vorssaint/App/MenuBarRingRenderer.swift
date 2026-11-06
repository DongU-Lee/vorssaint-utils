// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The "Icons" menu bar appearance: CPU, GPU, RAM and disk usage as one icon
/// each with a colored gauge on its right that fills with the reading; the
/// battery the same way, with its percentage inside the battery outline.
///
/// The glyphs come from one icon family (MenuBarMetricGlyphs) and draw in the
/// label color so they follow light and dark menu bars; only the gauges carry
/// color.
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
        let gaugeWidth = gaugeLineWidth
        let radius: CGFloat = glyphSide / 2 + 4
        let center = NSPoint(x: 1 + glyphSide / 2, y: height / 2)
        let width = ceil(center.x + radius + gaugeWidth / 2 + 0.5)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawGauge(center: center, radius: radius, fraction: fraction, color: ringColor(for: label))

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

    /// The battery in the same shape as the other readings: a battery outline
    /// in the glyph's square with the percentage inside, and the gauge on its
    /// right filling with the charge. Green, red when low; while charging a
    /// bolt takes the place of the terminal.
    static func ringBatteryImage(percent: Int, isCharging: Bool, isLow: Bool, style: MenuBarBlockStyle) -> NSImage {
        let height: CGFloat = style == .readable ? 22 : 20
        let side = MenuBarMetricGlyphs.side
        let stroke = MenuBarMetricGlyphs.stroke
        let center = NSPoint(x: 1 + side / 2, y: height / 2)
        let radius = side / 2 + 4
        let width = ceil(center.x + radius + 1.1 + 0.5)
        let low = isLow || (percent <= 20 && !isCharging)
        let green = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
        let red = NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawGauge(center: center, radius: radius, fraction: Double(percent) / 100, color: low ? red : green)

            let body = NSRect(x: center.x - side / 2 + 0.3, y: center.y - 5.6, width: side - 0.8, height: 11.2)
            let outline = NSBezierPath(roundedRect: body.insetBy(dx: stroke / 2, dy: stroke / 2), xRadius: 3, yRadius: 3)
            outline.lineWidth = stroke
            NSColor.labelColor.setStroke()
            outline.stroke()

            if isCharging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 6.5, weight: .black)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [green]))) {
                bolt.draw(in: NSRect(x: body.maxX + 0.2, y: center.y - bolt.size.height / 2,
                                     width: bolt.size.width, height: bolt.size.height))
            } else {
                let nub = NSBezierPath()
                nub.move(to: NSPoint(x: body.maxX + 1.3, y: center.y - 1.6))
                nub.line(to: NSPoint(x: body.maxX + 1.3, y: center.y + 1.6))
                nub.lineWidth = stroke
                nub.lineCapStyle = .round
                nub.stroke()
            }

            var font = NSFont.systemFont(ofSize: percent >= 100 ? 6.5 : 7.5, weight: .heavy)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: rounded, size: font.pointSize) ?? font
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: -0.2,
                                                             .foregroundColor: low ? red : NSColor.labelColor]
            let text = "\(percent)" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: body.midX - textSize.width / 2 + 0.1, y: center.y - textSize.height / 2),
                      withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Battery \(percent)%"
        return image
    }

    private static let gaugeLineWidth: CGFloat = 2.2
    /// Degrees either side of three o'clock.
    private static let gaugeSweep: CGFloat = 55

    /// The faint track and the colored level, filling from the bottom up.
    private static func drawGauge(center: NSPoint, radius: CGFloat, fraction: Double?, color: NSColor) {
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: -gaugeSweep, endAngle: gaugeSweep)
        track.lineWidth = gaugeLineWidth
        track.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        track.stroke()

        guard let fraction, fraction > 0 else { return }
        let level = NSBezierPath()
        level.appendArc(withCenter: center, radius: radius, startAngle: -gaugeSweep,
                        endAngle: -gaugeSweep + 2 * gaugeSweep * CGFloat(min(fraction, 1)))
        level.lineWidth = gaugeLineWidth
        level.lineCapStyle = .round
        color.setStroke()
        level.stroke()
    }
}
