// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Menu bar glyphs for the "Icons" appearance and the hidden-apps tray, one
/// family so the tray, CPU, GPU, RAM and disk read alike: Phosphor Icons 2.1.1, bold weight
/// (https://phosphoricons.com, MIT License, Copyright (c) 2023 Phosphor Icons).
/// Kept as the original SVG and drawn as template images.
enum MenuBarMetricGlyphs {
    private static let cache = NSCache<NSString, NSImage>()

    /// Every glyph is drawn in a square of this side, the battery body matches
    /// its height and the stroke matches Phosphor bold at this size.
    static let side: CGFloat = 15
    static let stroke: CGFloat = 24.0 / 256.0 * 15

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
        case "GPU": return graphicsCard
        case "RAM": return memory
        case "TRAY": return stack
        case "WARN": return warning
        default: return hardDrive
        }
    }

    private static let cpu = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M156,88H100a12,12,0,0,0-12,12v56a12,12,0,0,0,12,12h56a12,12,0,0,0,12-12V100A12,12,0,0,0,156,88Zm-12,56H112V112h32Zm88-4H220V116h12a12,12,0,0,0,0-24H220V56a20,20,0,0,0-20-20H164V24a12,12,0,0,0-24,0V36H116V24a12,12,0,0,0-24,0V36H56A20,20,0,0,0,36,56V92H24a12,12,0,0,0,0,24H36v24H24a12,12,0,0,0,0,24H36v36a20,20,0,0,0,20,20H92v12a12,12,0,0,0,24,0V220h24v12a12,12,0,0,0,24,0V220h36a20,20,0,0,0,20-20V164h12a12,12,0,0,0,0-24Zm-36,56H60V60H196Z"/></svg>
    """

    private static let graphicsCard = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M232,44H16A12,12,0,0,0,4,56V208a12,12,0,0,0,24,0V196H44v12a12,12,0,0,0,24,0V196H84v12a12,12,0,0,0,24,0V196h16v12a12,12,0,0,0,24,0V196h84a20,20,0,0,0,20-20V64A20,20,0,0,0,232,44Zm-4,128H28V68H228Zm-52-12a40,40,0,1,0-40-40A40,40,0,0,0,176,160Zm0-56a16,16,0,1,1-16,16A16,16,0,0,1,176,104ZM80,160a40,40,0,1,0-40-40A40,40,0,0,0,80,160Zm0-56a16,16,0,1,1-16,16A16,16,0,0,1,80,104Z"/></svg>
    """

    private static let memory = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M232,52H24A20,20,0,0,0,4,72V200a12,12,0,0,0,24,0V188H48v12a12,12,0,0,0,24,0V188H92v12a12,12,0,0,0,24,0V188h24v12a12,12,0,0,0,24,0V188h20v12a12,12,0,0,0,24,0V188h20v12a12,12,0,0,0,24,0V72A20,20,0,0,0,232,52ZM28,76H228v88H28Zm92,64V100a12,12,0,0,0-12-12H56a12,12,0,0,0-12,12v40a12,12,0,0,0,12,12h52A12,12,0,0,0,120,140ZM96,128H68V112H96Zm52,24h52a12,12,0,0,0,12-12V100a12,12,0,0,0-12-12H148a12,12,0,0,0-12,12v40A12,12,0,0,0,148,152Zm12-40h28v16H160Z"/></svg>
    """

    private static let hardDrive = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M224,60H32A20,20,0,0,0,12,80v96a20,20,0,0,0,20,20H224a20,20,0,0,0,20-20V80A20,20,0,0,0,224,60Zm-4,112H36V84H220Zm-56-44a16,16,0,1,1,16,16A16,16,0,0,1,164,128Z"/></svg>
    """

    private static let stack = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M234.36,170A12,12,0,0,1,230,186.37l-96,56a12,12,0,0,1-12.1,0l-96-56a12,12,0,0,1,12.09-20.74l90,52.48L218,165.63A12,12,0,0,1,234.36,170ZM218,117.63,128,170.11,38.05,117.63A12,12,0,0,0,26,138.37l96,56a12,12,0,0,0,12.1,0l96-56A12,12,0,0,0,218,117.63ZM20,80a12,12,0,0,1,6-10.37l96-56a12.06,12.06,0,0,1,12.1,0l96,56a12,12,0,0,1,0,20.74l-96,56a12,12,0,0,1-12.1,0l-96-56A12,12,0,0,1,20,80Zm35.82,0L128,122.11,200.18,80,128,37.89Z"/></svg>
    """

    private static let warning = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M240.26,186.1,152.81,34.23h0a28.74,28.74,0,0,0-49.62,0L15.74,186.1a27.45,27.45,0,0,0,0,27.71A28.31,28.31,0,0,0,40.55,228h174.9a28.31,28.31,0,0,0,24.79-14.19A27.45,27.45,0,0,0,240.26,186.1Zm-20.8,15.7a4.46,4.46,0,0,1-4,2.2H40.55a4.46,4.46,0,0,1-4-2.2,3.56,3.56,0,0,1,0-3.73L124,46.2a4.77,4.77,0,0,1,8,0l87.44,151.87A3.56,3.56,0,0,1,219.46,201.8ZM116,136V104a12,12,0,0,1,24,0v32a12,12,0,0,1-24,0Zm28,40a16,16,0,1,1-16-16A16,16,0,0,1,144,176Z"/></svg>
    """

}
