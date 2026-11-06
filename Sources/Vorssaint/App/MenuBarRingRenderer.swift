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

    /// How the arc shows its value.
    /// - track: a faint full-length track with the level drawn over it.
    /// - swoosh: one stroke from the bottom, faint there and strengthening to
    ///   solid at the level, where it ends; the width never changes.
    /// - swooshTrack: the swoosh with a faint track above the level.
    enum GaugeStyle: String { case track, swoosh, swooshTrack }

    /// `defaults write <bundle id> menuBarGaugeStyle swoosh` switches it at
    /// the next launch.
    static var gaugeStyle: GaugeStyle = GaugeStyle(
        rawValue: UserDefaults.standard.string(forKey: "menuBarGaugeStyle") ?? "") ?? .swoosh

    /// Usage gauges move in 2% steps, so a jittery reading reuses images.
    static func cachedRingImage(label: String, fraction: Double?, style: MenuBarBlockStyle) -> NSImage {
        let step = fraction.map { Int((MenuBarUsageBarSupport.clampedFraction($0) * 50).rounded()) }
        let key = "ring|\(MenuBarMetricGlyphs.set.rawValue)|\(gaugeStyle.rawValue)|\(label)|\(step.map(String.init) ?? "-")|\(style)" as NSString
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
        // The handler runs at draw time; the set and style are fixed now so
        // the image matches the key it was cached under.
        let set = MenuBarMetricGlyphs.set
        let gauge = gaugeStyle

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawGauge(center: center, fraction: fraction, style: gauge)
            if let glyph = MenuBarMetricGlyphs.image(for: label, set: set) {
                tinted(glyph, size: glyphRect.size).draw(in: glyphRect)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = fraction.map { "\(label) \(Int(($0 * 100).rounded()))%" } ?? label
        return image
    }

    /// The gauge filling from the bottom up in the current `gaugeStyle`;
    /// orange from 85%, red from 95%. A missing reading draws the empty track.
    private static func drawGauge(center: NSPoint, fraction: Double?, style gaugeStyle: GaugeStyle) {
        let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let trackAlpha: CGFloat = isDark ? 0.30 : 0.22
        let value = fraction.map { CGFloat(MenuBarUsageBarSupport.clampedFraction($0)) }
        // Where the level ends, as a fraction of the arc; never below the dot.
        let level = value.map { max(gaugeMinimumDegrees / (2 * gaugeSweep), $0) }
        let levelColor: NSColor = {
            guard let value else { return .labelColor }
            return value >= 0.95 ? .systemRed : value >= 0.85 ? .systemOrange : .labelColor
        }()
        func angle(_ t: CGFloat) -> CGFloat { -gaugeSweep + 2 * gaugeSweep * t }

        if gaugeStyle == .track {
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: gaugeRadius, startAngle: angle(0), endAngle: angle(1))
            track.lineWidth = gaugeWidth
            track.lineCapStyle = .round
            NSColor.labelColor.withAlphaComponent(trackAlpha).setStroke()
            track.stroke()
            guard let level else { return }
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: gaugeRadius, startAngle: angle(0), endAngle: angle(level))
            arc.lineWidth = gaugeWidth
            arc.lineCapStyle = .round
            levelColor.setStroke()
            arc.stroke()
            return
        }

        // One stroke drawn as short butt-capped pieces at a constant width,
        // each at its own opacity: faint at the bottom, solid at the level.
        // A missing reading is all faint.
        let pieces = 48
        func shade(at t: CGFloat) -> (alpha: CGFloat, color: NSColor)? {
            guard let level else { return (trackAlpha, .labelColor) }
            if t <= level { return (trackAlpha + (1 - trackAlpha) * t / level, levelColor) }
            return gaugeStyle == .swooshTrack ? (trackAlpha * 0.8, .labelColor) : nil
        }
        var end: CGFloat = 0
        for i in 0..<pieces {
            let t0 = CGFloat(i) / CGFloat(pieces), t1 = CGFloat(i + 1) / CGFloat(pieces)
            guard let s = shade(at: (t0 + t1) / 2) else { break }
            let piece = NSBezierPath()
            // A hair of overlap hides seams between pieces.
            piece.appendArc(withCenter: center, radius: gaugeRadius, startAngle: angle(t0) - 0.15, endAngle: angle(t1) + 0.15)
            piece.lineWidth = gaugeWidth
            piece.lineCapStyle = .butt
            s.color.withAlphaComponent(s.alpha).setStroke()
            piece.stroke()
            end = t1
        }
        // Round caps: both ends of what was drawn, and the head at the level.
        func cap(at t: CGFloat, _ shade: (alpha: CGFloat, color: NSColor)) {
            let radians = angle(t) * .pi / 180
            let point = NSPoint(x: center.x + gaugeRadius * cos(radians), y: center.y + gaugeRadius * sin(radians))
            shade.color.withAlphaComponent(shade.alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - gaugeWidth / 2, y: point.y - gaugeWidth / 2,
                                        width: gaugeWidth, height: gaugeWidth)).fill()
        }
        if let start = shade(at: 0) { cap(at: 0, start) }
        if let level { cap(at: level, (1, levelColor)) }
        if end > (level ?? 0), let tail = shade(at: end) { cap(at: end, tail) }
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
