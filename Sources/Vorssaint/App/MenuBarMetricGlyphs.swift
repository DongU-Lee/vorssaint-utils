// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Menu bar glyphs for the "Icons" appearance and the hidden-apps tray, one
/// family so the tray, CPU, GPU, RAM and disk read alike: Lucide
/// (https://lucide.dev, ISC License, Copyright (c) Lucide Contributors 2022;
/// portions Copyright (c) Cole Bemis 2013-2022 as part of Feather, MIT).
/// Kept as the original SVG, stroke widened from 2 to 2.2 so the glyphs hold
/// up at menu bar size, and drawn as template images.
///
/// Lucide over Phosphor: Phosphor's graphics card and memory are both a board
/// with two shapes on it and could not be told apart at 15 pt; Lucide's card
/// has fans and a bracket, its memory stick vertical chips.
enum MenuBarMetricGlyphs {
    private static let cache = NSCache<NSString, NSImage>()

    /// Every glyph is drawn in a square of this side; the battery body matches
    /// its height and the stroke matches the glyphs' at this size.
    static let side: CGFloat = 15
    static let stroke: CGFloat = 2.2 / 24 * 15

    /// The template glyph for a usage label (CPU, GPU, RAM, DSK) or for the
    /// tray (TRAY, WARN).
    static func image(for label: String) -> NSImage? {
        if let cached = cache.object(forKey: label as NSString) { return cached }
        guard let image = NSImage(data: Data(svg(for: label).utf8)) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: label as NSString)
        return image
    }

    private static func svg(for label: String) -> String {
        switch label {
        case "CPU": return cpu
        case "GPU": return gpu
        case "RAM": return memory
        case "TRAY": return stack
        case "WARN": return warning
        default: return hardDrive
        }
    }

    private static let cpu = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2"><path d="M12 20v2m0-20v2m5 16v2m0-20v2M2 12h2m-2 5h2M2 7h2m16 5h2m-2 5h2M20 7h2M7 20v2M7 2v2"/><rect width="16" height="16" x="4" y="4" rx="2"/><rect width="8" height="8" x="8" y="8" rx="1"/></g></svg>
    """

    private static let gpu = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2"><path d="M2 17h18a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2H2m0 16V3m5 14v3a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1v-3"/><circle cx="16" cy="11" r="2"/><circle cx="8" cy="11" r="2"/></g></svg>
    """

    private static let memory = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2"><path d="M12 12v-2m0 8v-2m4-4v-2m0 8v-2M2 11h1.5M20 18v-2m.5-5H22M4 18v-2m4-4v-2m0 8v-2"/><rect width="20" height="10" x="2" y="6" rx="2"/></g></svg>
    """

    private static let hardDrive = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2" d="M10 16h.01m-7.798-4.423a2 2 0 0 0-.212.896V18a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5.527a2 2 0 0 0-.212-.896L18.55 5.11A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11zm19.734.436H2.054M6 16h.01"/></svg>
    """

    private static let stack = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2"><path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/></g></svg>
    """

    private static let warning = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2" d="m21.73 18l-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3M12 9v4m0 4h.01"/></svg>
    """
}
