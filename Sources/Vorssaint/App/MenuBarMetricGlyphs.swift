// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Menu bar glyphs for the "Icons" appearance and the hidden-apps tray, one
/// family so the tray, CPU, GPU, RAM and disk read alike: Lucide
/// (https://lucide.dev, ISC License, Copyright (c) Lucide Contributors 2022;
/// portions Copyright (c) Cole Bemis 2013-2022 as part of Feather, MIT).
/// Redrawn on Lucide's shapes in the Vorssaint mark's manner, a solid mass
/// with thin lines around it: outlines at a heavy weight, the core part (die,
/// chips, fan hubs, top layer) filled, fine detail at a hairline weight.
/// Drawn as template images.
///
/// Lucide over Phosphor: Phosphor's graphics card and memory are both a board
/// with two shapes on it and could not be told apart at 15 pt; Lucide's card
/// has fans and a bracket, its memory stick vertical chips.
enum MenuBarMetricGlyphs {
    private static let cache = NSCache<NSString, NSImage>()

    /// Every glyph is drawn in a square of this side; the battery body matches
    /// its height and the stroke matches the glyphs' at this size.
    static let side: CGFloat = 15
    /// The two weights every glyph uses, in points at `side`.
    static let stroke: CGFloat = 2.6 / 24 * 15
    static let hairline: CGFloat = 1.3 / 24 * 15

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
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="3.2" stroke-width="2.6"/><rect x="8.6" y="8.6" width="6.8" height="6.8" rx="1.3" fill="#000" stroke="none"/><path stroke-width="1.3" d="M9 1.6v2.4M12 1.6v2.4M15 1.6v2.4M9 20v2.4M12 20v2.4M15 20v2.4M1.6 9h2.4M1.6 12h2.4M1.6 15h2.4M20 9h2.4M20 12h2.4M20 15h2.4"/></svg>
    """

    private static let gpu = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round"><path stroke-width="2.6" d="M4.6 17H20a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2H4.6z"/><path stroke-width="1.3" d="M2 3.2v17.6M2 5h2.6M7.4 17v3a1 1 0 0 0 1 1h4.6a1 1 0 0 0 1-1v-3"/><circle cx="9.4" cy="11" r="2.6" stroke-width="1.3"/><circle cx="16.6" cy="11" r="2.6" stroke-width="1.3"/><circle cx="9.4" cy="11" r="1.15" fill="#000" stroke="none"/><circle cx="16.6" cy="11" r="1.15" fill="#000" stroke="none"/></svg>
    """

    private static let memory = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="6" width="20" height="10" rx="2.2" stroke-width="2.6"/><g fill="#000" stroke="none"><rect x="5" y="8.6" width="2.6" height="4.8" rx="0.6"/><rect x="9.1" y="8.6" width="2.6" height="4.8" rx="0.6"/><rect x="13.2" y="8.6" width="2.6" height="4.8" rx="0.6"/><rect x="17.3" y="8.6" width="1.8" height="4.8" rx="0.6"/></g><path stroke-width="1.3" d="M5 17.3v2.4M8 17.3v2.4M11 17.3v2.4M14 17.3v2.4M17 17.3v2.4M20 17.3v2.4"/></svg>
    """

    private static let hardDrive = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round"><path stroke-width="2.6" d="M2.2 11.6a2 2 0 0 0-.2.9V18a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-5.5a2 2 0 0 0-.2-.9L18.55 5.1A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.1z"/><path stroke-width="1.3" d="M2.6 12h18.8"/><circle cx="6.4" cy="16" r="1.2" fill="#000" stroke="none"/><circle cx="10.2" cy="16" r="1.2" fill="#000" stroke="none"/></svg>
    """

    private static let stack = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round"><path fill="#000" stroke="#000" stroke-width="1" d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path stroke-width="1.3" d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path stroke-width="1.3" d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/></svg>
    """

    private static let warning = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2" d="m21.73 18l-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3M12 9v4m0 4h.01"/></svg>
    """
}
