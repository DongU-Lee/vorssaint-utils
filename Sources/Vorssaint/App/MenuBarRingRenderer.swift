// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The "Icons" menu bar appearance. Every reading is one shape: a bold glyph
/// in the lower left with a gauge arc wrapped over its upper right, from four
/// o'clock up over the top to eleven, filling with the value. The battery is
/// the same arc with only its percentage where the glyph would be, so it
/// takes no more width than a CPU reading and needs no battery pictogram.
///
/// Glyphs draw in the label color like the system's own items. The arc
/// carries each reading's hue (blue CPU, green GPU, purple RAM, orange disk,
/// green battery) unless `coloredGauges` is off, and turns orange from 85%
/// and red from 95% or when the battery is low.
extension MenuBarRenderer {
    private static let ringCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    // Geometry in points for the 22 pt (readable) item; dense scales it.
    private static let ringRadius: CGFloat = 11.5
    private static let ringWidth: CGFloat = 2.4
    private static let glyphSide: CGFloat = 15
    private static let ringStart: CGFloat = -30      // four o'clock, the faint end
    private static let ringEnd: CGFloat = 120        // eleven o'clock
    private static let minimumLevel: CGFloat = 0.045  // a 0% reading still shows a dot

    /// How the arc shows its value.
    /// - fade: one stroke, faint at four o'clock and solid at the level, where it ends.
    /// - track: a faint full arc with the level drawn solid over it.
    enum GaugeStyle: String { case fade, track }

    /// `defaults write <bundle id> menuBarGaugeStyle track` switches it at the
    /// next launch; `menuBarGaugeColored -bool NO` makes every arc monochrome.
    static var gaugeStyle: GaugeStyle = GaugeStyle(
        rawValue: UserDefaults.standard.string(forKey: "menuBarGaugeStyle") ?? "") ?? .fade
    static var coloredGauges: Bool = UserDefaults.standard.object(forKey: "menuBarGaugeColored") as? Bool ?? true

    private static let hues: [String: NSColor] = [
        "CPU": .systemBlue, "GPU": .systemGreen, "RAM": .systemPurple, "DSK": .systemOrange, "BAT": .systemGreen,
    ]

    private struct Layout {
        let size: NSSize
        let glyph: NSRect
        let ringCenter: NSPoint
        let scale: CGFloat
    }

    private static func layout(style: MenuBarBlockStyle) -> Layout {
        let height: CGFloat = style == .readable ? 22 : 20
        let scale = height / 22
        let glyph = NSRect(x: 0.5 * scale, y: 0.5 * scale, width: glyphSide * scale, height: glyphSide * scale)
        // Centred a point up and right of the glyph, so the arc clears its
        // upper-right corner by about a point.
        let ringCenter = NSPoint(x: glyph.midX + scale, y: glyph.midY + scale)
        let width = ceil(ringCenter.x + (ringRadius + ringWidth / 2) * scale + 0.5)
        return Layout(size: NSSize(width: width, height: height), glyph: glyph, ringCenter: ringCenter, scale: scale)
    }

    /// Usage arcs move in 2% steps, so a jittery reading reuses images.
    static func cachedRingImage(label: String, fraction: Double?, style: MenuBarBlockStyle) -> NSImage {
        let step = fraction.map { Int((MenuBarUsageBarSupport.clampedFraction($0) * 50).rounded()) }
        let key = "ring|\(MenuBarMetricGlyphs.set.rawValue)|\(gaugeStyle.rawValue)|\(coloredGauges)|\(label)|\(step.map(String.init) ?? "-")|\(style)" as NSString
        if let cached = ringCache.object(forKey: key) { return cached }
        let image = ringImage(label: label, fraction: step.map { Double($0) / 50 }, style: style)
        ringCache.setObject(image, forKey: key)
        return image
    }

    static func cachedRingBatteryImage(percent: Int, isCharging: Bool, isLow: Bool,
                                       style: MenuBarBlockStyle) -> NSImage {
        let percent = max(0, min(100, percent))
        let key = "ringBattery|\(gaugeStyle.rawValue)|\(coloredGauges)|\(percent)|\(isCharging)|\(isLow)|\(style)" as NSString
        if let cached = ringCache.object(forKey: key) { return cached }
        let image = ringBatteryImage(percent: percent, isCharging: isCharging, isLow: isLow, style: style)
        ringCache.setObject(image, forKey: key)
        return image
    }

    static func ringImage(label: String, fraction: Double?, style: MenuBarBlockStyle) -> NSImage {
        let layout = layout(style: style)
        // The handler runs at draw time; fix the set and style now so the
        // image matches the key it was cached under.
        let set = MenuBarMetricGlyphs.set
        let gauge = gaugeStyle
        let hue = coloredGauges ? hues[label] : nil
        let value = fraction.map { CGFloat(MenuBarUsageBarSupport.clampedFraction($0)) }
        let warning: NSColor? = value.map { $0 >= 0.95 ? .systemRed : $0 >= 0.85 ? .systemOrange : nil } ?? nil

        let image = NSImage(size: layout.size, flipped: false) { _ in
            drawRing(layout, level: value, color: warning ?? hue ?? .labelColor, style: gauge)
            if let glyph = MenuBarMetricGlyphs.image(for: label, set: set) {
                tinted(glyph, size: layout.glyph.size).draw(in: layout.glyph)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = fraction.map { "\(label) \(Int(($0 * 100).rounded()))%" } ?? label
        return image
    }

    /// The percentage where a glyph would be; a bolt beside it while
    /// charging, red arc and number when low.
    static func ringBatteryImage(percent: Int, isCharging: Bool, isLow: Bool, style: MenuBarBlockStyle) -> NSImage {
        let layout = layout(style: style)
        let gauge = gaugeStyle
        let low = isLow || (percent <= 20 && !isCharging)
        let ringColor: NSColor = low ? .systemRed : (coloredGauges ? hues["BAT"]! : .labelColor)

        let image = NSImage(size: layout.size, flipped: false) { _ in
            drawRing(layout, level: CGFloat(percent) / 100, color: ringColor, style: gauge)
            var font = NSFont.monospacedDigitSystemFont(ofSize: (percent >= 100 ? 8.5 : 10) * layout.scale, weight: .heavy)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: rounded, size: font.pointSize) ?? font
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .kern: -0.3, .foregroundColor: low ? NSColor.systemRed : NSColor.labelColor]
            let text = "\(percent)" as NSString
            let textSize = text.size(withAttributes: attributes)
            let origin = NSPoint(x: layout.glyph.midX - textSize.width / 2, y: layout.glyph.midY - textSize.height / 2)
            text.draw(at: origin, withAttributes: attributes)
            if isCharging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 6 * layout.scale, weight: .black)) {
                let boltRect = NSRect(x: origin.x + textSize.width + 0.4, y: layout.glyph.midY + 2 * layout.scale,
                                      width: bolt.size.width, height: bolt.size.height)
                tinted(bolt, size: boltRect.size).draw(in: boltRect)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Battery \(percent)%"
        return image
    }

    /// The arc from four o'clock up over the top to eleven, filled to
    /// `level` in `color`. A missing level draws the faint empty arc.
    private static func drawRing(_ layout: Layout, level: CGFloat?, color: NSColor, style: GaugeStyle) {
        let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let faint: CGFloat = isDark ? 0.28 : 0.22
        let level = level.map { max(minimumLevel, $0) }
        let center = layout.ringCenter
        let radius = ringRadius * layout.scale
        let width = ringWidth * layout.scale
        func angle(_ t: CGFloat) -> CGFloat { ringStart + (ringEnd - ringStart) * t }
        func arc(_ from: CGFloat, _ to: CGFloat, _ stroke: NSColor, round: Bool) {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: angle(from), endAngle: angle(to))
            path.lineWidth = width
            path.lineCapStyle = round ? .round : .butt
            stroke.setStroke()
            path.stroke()
        }
        func cap(_ t: CGFloat, _ fill: NSColor) {
            let radians = angle(t) * .pi / 180
            let point = NSPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
            fill.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width)).fill()
        }

        guard let level else { return arc(0, 1, NSColor.labelColor.withAlphaComponent(faint), round: true) }
        switch style {
        case .track:
            arc(0, 1, NSColor.labelColor.withAlphaComponent(faint), round: true)
            arc(0, level, color, round: true)
        case .fade:
            // Short butt-capped pieces, each a step more opaque than the last,
            // with a round dot closing each end.
            let pieces = 48
            for i in 0..<pieces {
                let t0 = CGFloat(i) / CGFloat(pieces), t1 = CGFloat(i + 1) / CGFloat(pieces)
                let middle = (t0 + t1) / 2
                if middle > level { break }
                let alpha = faint + (1 - faint) * middle / level
                // A hair of overlap hides seams between pieces.
                arc(t0 - 0.001, t1 + 0.001, color.withAlphaComponent(alpha), round: false)
            }
            cap(0, color.withAlphaComponent(faint))
            cap(level, color)
        }
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
