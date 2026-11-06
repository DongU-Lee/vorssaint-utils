// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import SwiftUI

/// Folds every other app's menu bar icon behind one item of ours and shows the
/// hidden ones as a grid of app icons in a tray under it.
///
/// macOS 27 ejects a status item that is inflated to push others off screen,
/// the trick older menu bar managers used. This uses the allow-list behind
/// macOS 27's assessment (exam) mode instead: only our own items and the
/// system's (clock, Control Center...) stay; macOS hides the rest and reflows
/// the bar itself. The restriction lasts until invalidated or until this
/// process exits, when macOS restores the bar on its own.
///
/// Hiding is per app, so an app with several icons hides or shows them
/// together. Listing the hidden icons needs Accessibility; hiding does not.
final class MenuBarHiderController: NSObject {
    private let statusItem: NSStatusItem
    private let tray = TrayPanel()
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""
    /// Non-nil while other apps' icons are hidden.
    private var assertion: NativeMenuBarVisibility.Assertion?
    /// Waits for the click that ends a revealed app's menu, then hides again.
    private var rehideMonitor: Any?
    /// Bumped on every state change so a late activation cannot win.
    private var generation = 0
    /// A right click, which opens the app's context menu like every other
    /// Vorssaint item; receives the button so the menu can anchor to it.
    var onRightClick: ((NSStatusBarButton?) -> Void)?
    /// The app the current restriction lets through beside our own, if any.
    private var revealedBundleID: String?
    /// Watches for clicks on the system clock while icons are hidden.
    private var clockMonitor: Any?
    /// The clock under a mouse-down, resolved before any lift so the press
    /// that follows needs no lookup and the bar is unrestricted as briefly
    /// as possible.
    private var clockClick: SystemClock.Item?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = "VorssaintMenuBarHider"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        collapse()
        clockMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleClockEvent(event)
        }
    }

    /// Drops the restriction so the whole bar shows again.
    func tearDown() {
        stopRehideMonitor()
        if let clockMonitor { NSEvent.removeMonitor(clockMonitor) }
        clockMonitor = nil
        assertion?.invalidate()
        assertion = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Hiding

    private var isCollapsed: Bool { assertion != nil }

    /// Hides every app's icons except ours and, when given, one app the
    /// person just picked from the menu.
    private func collapse(revealing bundleID: String? = nil, then done: (() -> Void)? = nil) {
        guard NativeMenuBarVisibility.isAvailable else { return updateIcon() }
        generation += 1
        let generation = self.generation
        revealedBundleID = bundleID
        let allowed = [ownBundleID] + (bundleID.map { [$0] } ?? [])
        NativeMenuBarVisibility.activate(allowing: allowed) { [weak self] newAssertion in
            guard let self, generation == self.generation else {
                newAssertion?.invalidate()
                return
            }
            guard let newAssertion else { return self.updateIcon() }
            // The new restriction is live before the old one goes, so the
            // bar never flashes fully visible in between.
            self.assertion?.invalidate()
            self.assertion = newAssertion
            self.updateIcon()
            done?()
        }
    }

    private func expand() {
        generation += 1
        stopRehideMonitor()
        assertion?.invalidate()
        assertion = nil
        updateIcon()
    }

    private func updateIcon() {
        let glyph: String
        let tip: String
        if !NativeMenuBarVisibility.isAvailable {
            glyph = "WARN"
            tip = "이 macOS에서는 아이콘 숨기기를 쓸 수 없습니다"
        } else if isCollapsed {
            glyph = "TRAY"
            tip = "숨긴 메뉴 막대 아이콘"
        } else {
            glyph = "TRAY"
            tip = "메뉴 막대 아이콘 숨기기"
        }
        // Same family and size as the CPU, GPU and RAM icons beside it.
        let image = MenuBarMetricGlyphs.image(for: glyph)?.copy() as? NSImage
        image?.size = NSSize(width: MenuBarMetricGlyphs.side, height: MenuBarMetricGlyphs.side)
        image?.accessibilityDescription = tip
        statusItem.button?.image = image
        // Dimmed while everything is showing, so the state reads at a glance.
        statusItem.button?.appearsDisabled = NativeMenuBarVisibility.isAvailable && !isCollapsed
        statusItem.button?.toolTip = tip
    }

    // MARK: - The system clock

    /// macOS ignores clicks on its clock while any menu bar restriction is
    /// held (the restriction is exam mode), so a click lands on nothing. A
    /// plain left click on the clock while hidden lifts the restriction,
    /// presses the clock, and puts the identical restriction back;
    /// Notification Center stays open across that. A click while it is open
    /// closes it by itself and is left alone.
    private func handleClockEvent(_ event: NSEvent) {
        guard let location = event.cgEvent?.location else { return }
        switch event.type {
        case .leftMouseDown:
            clockClick = nil
            guard isCollapsed, event.modifierFlags.isDisjoint(with: [.command, .control]),
                  let clock = SystemClock.items().first(where: { $0.frame.contains(location) }),
                  !SystemClock.isNotificationCenterOpen else { return }
            clockClick = clock
        case .leftMouseUp:
            guard let clock = clockClick else { return }
            clockClick = nil
            if clock.frame.contains(location) { openNotificationCenter(pressing: clock) }
        default:
            break
        }
    }

    /// Every hidden icon is back in the bar while no restriction is held,
    /// so the gap is kept to the lift settling (30 ms), the press, and the
    /// re-assert; nothing else happens in between.
    private func openNotificationCenter(pressing clock: SystemClock.Item) {
        guard isCollapsed else { return }
        generation += 1
        assertion?.invalidate()
        assertion = nil
        let revealed = revealedBundleID
        // Pressed off the main thread once macOS has applied the lift, as
        // the accessibility call can block for a moment.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.03) {
            clock.press()
            DispatchQueue.main.async { [weak self] in self?.collapse(revealing: revealed) }
        }
    }

    // MARK: - Tray

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            tray.close()
            onRightClick?(statusItem.button)
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if tray.isVisible { return tray.close() }
        guard let buttonFrame = statusItem.button?.window?.frame else { return }
        let close: () -> Void = { [weak self] in self?.tray.close() }
        tray.show(HiddenAppsTray(
            state: trayState(),
            onOpen: { [weak self] extra in close(); self?.open(extra) },
            onRightClick: { [weak self] extra in close(); self?.open(extra, rightClick: true) },
            onShowAll: { [weak self] in close(); self?.expand() },
            onHideOthers: { [weak self] in close(); self?.collapse() },
            onRequestAccess: { close(); Permissions.shared.requestAccessibility() }),
                  under: buttonFrame)
    }

    private func trayState() -> HiddenAppsTray.State {
        guard NativeMenuBarVisibility.isAvailable else { return .unavailable }
        guard isCollapsed else { return .expanded }
        guard AXIsProcessTrusted() else { return .needsAccess }
        return .collapsed(MenuBarExtra.hiddenCandidates(excludingBundleID: ownBundleID))
    }

    /// Brings the picked app's icons back for a moment, clicks the one that
    /// was picked (with the right button when asked, so the app shows the
    /// same menu it would in the bar), and hides them again after the next
    /// click anywhere.
    private func open(_ extra: MenuBarExtra, rightClick: Bool = false) {
        guard let bundleID = extra.bundleID else {
            // macOS cannot allow-list an app without a bundle id, so it stays
            // hidden; pressing it is all that is left to try.
            extra.click(right: rightClick, placed: false)
            return
        }
        collapse(revealing: bundleID) { [weak self] in
            self?.activateOncePlaced(extra, rightClick: rightClick, attempt: 0)
        }
    }

    /// Clicks the revealed icon once macOS has placed it, with a real mouse
    /// click at its frame, which is what the app answers in the bar (some,
    /// OneDrive among them, ignore the accessibility press). A hidden item
    /// reports a stale frame until it is back in the bar, so this waits (up
    /// to about 1.5 s) for a frame inside the menu bar strip; with none, a
    /// left click falls back to the press.
    private func activateOncePlaced(_ extra: MenuBarExtra, rightClick: Bool, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.35 : 0.12)) { [weak self] in
            guard let self else { return }
            let fresh = MenuBarExtra.refreshed(extra) ?? extra
            let placed = fresh.frame.map(SystemClock.isInMenuBar) ?? false
            if !placed, attempt < 10 {
                return self.activateOncePlaced(extra, rightClick: rightClick, attempt: attempt + 1)
            }
            NSLog("MenuBarHider: \(rightClick ? "right" : "left") click on \(extra.label) at \(fresh.frame.map { "\($0)" } ?? "no frame"), placed \(placed)")
            fresh.click(right: rightClick, placed: placed)
            // Installed after the click we just posted has passed, so the
            // monitor does not mistake our own click for the next one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.startRehideMonitor(sparing: extra.pid) }
        }
    }

    /// Hides again after the next click outside the revealed app. Clicks in
    /// that app's own windows (its menu, its panel, its icon) are part of
    /// using it and are let through.
    private func startRehideMonitor(sparing pid: pid_t? = nil) {
        stopRehideMonitor()
        rehideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            if let pid, let location = event.cgEvent?.location, Self.windowOwner(at: location) == pid { return }
            self.stopRehideMonitor()
            // Late enough that a click choosing a menu entry still lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.isCollapsed else { return }
                self.collapse()
            }
        }
    }

    /// The process owning the frontmost on-screen window under a point (top
    /// left origin), menus and panels included.
    private static func windowOwner(at point: CGPoint) -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for window in windows {   // front to back
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    private func stopRehideMonitor() {
        if let rehideMonitor { NSEvent.removeMonitor(rehideMonitor) }
        rehideMonitor = nil
    }
}

// MARK: - Other apps' menu bar icons, read through Accessibility

final class MenuBarExtra: NSObject {
    let pid: pid_t
    let bundleID: String?
    let index: Int
    let label: String
    let appIcon: NSImage?
    /// How many icons this app has in the bar; the tray numbers them.
    let siblingCount: Int
    /// Where the icon sits on screen (top-left origin), when known.
    let frame: CGRect?
    private let element: AXUIElement

    private init(app: NSRunningApplication, index: Int, count: Int, element: AXUIElement) {
        pid = app.processIdentifier
        bundleID = app.bundleIdentifier
        self.index = index
        self.element = element
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        // Descriptions can run over several lines (OneDrive's does); the
        // first one names the icon.
        let title = (Self.string(element, kAXTitleAttribute) ?? Self.string(element, kAXDescriptionAttribute))?
            .split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let title, !title.isEmpty, title != name {
            label = "\(name) — \(title)"
        } else {
            label = count > 1 ? "\(name) \(index + 1)" : name
        }
        appIcon = app.icon
        siblingCount = count
        frame = Self.frame(of: element)
    }

    func press() {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// A real click at the icon's centre, which the app answers exactly as
    /// it would in the bar. Without a placed frame a right click is still
    /// tried there, and a left click falls back to the accessibility press.
    func click(right: Bool, placed: Bool) {
        guard let frame, placed || right else { return press() }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let types: [CGEventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                    mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: origin, size: size)
    }

    /// Every other app's menu bar icon. macOS's own items are left out: they
    /// are never hidden.
    static func hiddenCandidates(excludingBundleID ownBundleID: String) -> [MenuBarExtra] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier != ownBundleID && !isSystemProcess($0) }
            .sorted { ($0.localizedName ?? "") .localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
            .flatMap(extras(of:))
    }

    /// The same icon read again: the element captured while it was hidden
    /// may not answer once macOS has put it back.
    static func refreshed(_ extra: MenuBarExtra) -> MenuBarExtra? {
        guard let app = NSRunningApplication(processIdentifier: extra.pid) else { return nil }
        let fresh = extras(of: app)
        return fresh.indices.contains(extra.index) ? fresh[extra.index] : extra
    }

    private static func extras(of app: NSRunningApplication) -> [MenuBarExtra] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // A hung app must not freeze the menu while it opens.
        AXUIElementSetMessagingTimeout(axApp, 0.1)
        var bar: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement] else { return [] }
        return elements.enumerated().map {
            MenuBarExtra(app: app, index: $0.offset, count: elements.count, element: $0.element)
        }
    }

    private static func isSystemProcess(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return id.hasPrefix("com.apple.") && app.activationPolicy != .regular
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

// MARK: - The panel the tray opens in

/// A borderless panel that opens flush under the menu bar like a menu, rather
/// than an NSPopover, whose arrow and inset leave the tray hanging low.
/// Closes on Escape, on a click anywhere else, or when the app loses focus.
private final class TrayPanel: NSPanel {
    private var outsideClickMonitor: Any?
    private var localKeyMonitor: Any?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        // Reused for every opening, so closing must not free it.
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    func show<Content: View>(_ content: Content, under buttonFrame: NSRect) {
        let host = NSHostingView(rootView: content
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
        contentView = host
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(buttonFrame.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? buttonFrame
        // Just under the bar, centred on the item, kept on screen.
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(buttonFrame.minY, visible.maxY) - 5 - size.height
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            self?.close()
            return nil
        }
    }

    override func close() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        outsideClickMonitor = nil
        localKeyMonitor = nil
        super.close()
    }

    override func resignKey() {
        super.resignKey()
        close()
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - The tray under the hider item

struct HiddenAppsTray: View {
    enum State {
        case unavailable, needsAccess, expanded
        case collapsed([MenuBarExtra])
    }

    let state: State
    let onOpen: (MenuBarExtra) -> Void
    let onRightClick: (MenuBarExtra) -> Void
    let onShowAll: () -> Void
    let onHideOthers: () -> Void
    let onRequestAccess: () -> Void

    // Compact, close to menu bar scale: 32 pt tiles, six to a row.
    private static let tile: CGFloat = 32
    private static let spacing: CGFloat = 6
    private static let perRow = 6
    private let columns = Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.spacing), count: Self.perRow)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .unavailable:
                message("이 macOS에서는 아이콘 숨기기를 쓸 수 없습니다")
            case .needsAccess:
                message("숨긴 아이콘을 보려면 손쓰기 권한이 필요합니다")
                Button("권한 허용…", action: onRequestAccess)
            case .expanded:
                message("모든 메뉴 막대 아이콘이 보이는 중입니다")
                Button("다른 앱 아이콘 숨기기", action: onHideOthers)
            case .collapsed(let extras):
                if extras.isEmpty {
                    message("숨긴 아이콘 없음")
                } else {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(extras.indices, id: \.self) { index in
                            TrayTile(extra: extras[index],
                                     action: { onOpen(extras[index]) },
                                     rightAction: { onRightClick(extras[index]) })
                        }
                    }
                }
                Divider()
                Button("아이콘 모두 보이기", action: onShowAll)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(10)
        .frame(width: CGFloat(Self.perRow) * Self.tile + CGFloat(Self.perRow - 1) * Self.spacing + 20)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TrayTile: View {
    let extra: MenuBarExtra
    let action: () -> Void
    let rightAction: () -> Void
    @SwiftUI.State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = extra.appIcon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.12 : 0.05)))
            if extra.siblingCount > 1 {
                Text("\(extra.index + 1)")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 11)
                    .background(Circle().fill(Color.secondary))
                    .offset(x: 1.5, y: 1.5)
            }
        }
        // SwiftUI buttons only take the left button; this takes both.
        .overlay(ClickCatcher(onLeft: action, onRight: rightAction))
        .onHover { hovering = $0 }
        .help(extra.label)
        .accessibilityLabel(extra.label)
        .accessibilityAddTraits(.isButton)
    }
}

/// A transparent view that reports left and right clicks separately.
private struct ClickCatcher: NSViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void

    final class CatcherView: NSView {
        var onLeft: () -> Void = {}
        var onRight: () -> Void = {}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onLeft() } }
        override func rightMouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onRight() } }
    }

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onLeft = onLeft
        view.onRight = onRight
    }
}

// MARK: - The system clock, read through Accessibility

enum SystemClock {
    struct Item {
        let element: AXUIElement
        let frame: CGRect
        func press() { AXUIElementPerformAction(element, kAXPressAction as CFString) }
    }

    private static let ownerBundleID = "com.apple.MenuBarAgent"
    private static let clockIdentifier = "com.apple.menuextra.clock"
    private static let notificationCenterBundleID = "com.apple.notificationcenterui"

    /// The clock items in the bar (one per display), with their frames in
    /// screen coordinates (top-left origin).
    static func items() -> [Item] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: ownerBundleID).first
        else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar = value(of: app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var items: [Item] = []
        // swiftlint:disable:next force_cast
        for group in children(of: bar as! AXUIElement) {
            for item in [group] + children(of: group) where value(of: item, kAXIdentifierAttribute) as? String == clockIdentifier {
                if let frame = MenuBarExtra.frame(of: item) { items.append(Item(element: item, frame: frame)) }
            }
        }
        return items
    }

    /// True while Notification Center's panel is on screen: a window of its
    /// process at least half a screen tall.
    static var isNotificationCenterOpen: Bool {
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: notificationCenterBundleID)
            .map(\.processIdentifier))
        guard !owners.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let minimumHeight = (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.height >= minimumHeight
        }
    }

    /// Whether a frame (top-left origin) sits in some display's menu bar.
    static func isInMenuBar(_ frame: CGRect) -> Bool {
        guard frame.width > 0, let primaryTop = NSScreen.screens.first?.frame.maxY else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { screen in
            let top = primaryTop - screen.frame.maxY
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            return point.x >= screen.frame.minX && point.x <= screen.frame.maxX && point.y >= top && point.y <= top + height
        }
    }

    private static func value(of element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}

// MARK: - macOS 27's menu bar allow-list (private MenuBarClientCore)

enum NativeMenuBarVisibility {
    final class Assertion {
        private var raw: AnyObject?
        fileprivate init(raw: AnyObject) { self.raw = raw }

        func invalidate() {
            guard let raw else { return }
            self.raw = nil
            let send = unsafeBitCast(msgSend, to: VoidFn.self)
            send(raw, sel_registerName("invalidate"))
        }

        deinit { invalidate() }
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let initSelector = sel_registerName("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = sel_registerName("activateWithConfiguration:completionHandler:")
    /// The system clock's item id, found on macOS 27.0.1 by leaving out one
    /// id at a time; undocumented, so a later macOS may move it.
    static let systemClockItem = 2

    /// System item ids to keep. Unknown ids are ignored, so the range covers
    /// items a given Mac does not have. The clock is left out unless
    /// `menuBarHideSystemClock -bool NO`: Vorssaint shows its own date and
    /// time, and the system clock is useless while folded anyway, since
    /// macOS ignores clicks on it under any restriction.
    private static var systemItemsToKeep: [NSNumber] {
        let hideClock = UserDefaults.standard.object(forKey: "menuBarHideSystemClock") as? Bool ?? true
        return (0..<64).filter { !(hideClock && $0 == systemClockItem) }.map { NSNumber(value: $0) }
    }

    private typealias AllocFn = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias InitFn = @convention(c) (UnsafeMutableRawPointer, Selector, NSArray, NSArray) -> UnsafeMutableRawPointer?
    private typealias ActivateFn = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void
    private typealias VoidFn = @convention(c) (AnyObject, Selector) -> Void

    private static let msgSend: UnsafeMutableRawPointer? = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")

    private static var configurationClass: AnyClass? { NSClassFromString("MBAssessmentModeConfiguration") }
    private static var assertionClass: AnyClass? { NSClassFromString("MBAssessmentModeAssertion") }

    /// Resolved at runtime, so a macOS that changes or drops the framework
    /// just turns the feature off instead of crashing.
    static let isAvailable: Bool = {
        guard msgSend != nil, dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil,
              let configuration = configurationClass as? NSObject.Type,
              let assertion = assertionClass as? NSObject.Type else { return false }
        return configuration.instancesRespond(to: initSelector)
            && assertion.instancesRespond(to: activateSelector)
            && assertion.instancesRespond(to: sel_registerName("invalidate"))
    }()

    /// Keeps only these apps' icons (plus the system's) visible. Calls back on
    /// the main queue with the live assertion, or nil when macOS refused.
    static func activate(allowing bundleIDs: [String], completion: @escaping (Assertion?) -> Void) {
        let finish: (Assertion?) -> Void = { result in DispatchQueue.main.async { completion(result) } }
        guard isAvailable, let msgSend,
              let configurationClass, let assertionType = assertionClass as? NSObject.Type else { return finish(nil) }
        let alloc = unsafeBitCast(msgSend, to: AllocFn.self)
        let initialize = unsafeBitCast(msgSend, to: InitFn.self)
        // alloc hands back an owned object and init consumes it, so both stay
        // raw pointers until the result is taken over once.
        guard let allocated = alloc(configurationClass, sel_registerName("alloc")),
              let configured = initialize(allocated, initSelector,
                                          systemItemsToKeep as NSArray, bundleIDs as NSArray)
        else { return finish(nil) }
        let configuration = Unmanaged<AnyObject>.fromOpaque(configured).takeRetainedValue()
        let raw = assertionType.init()
        let activate = unsafeBitCast(msgSend, to: ActivateFn.self)
        activate(raw, activateSelector, configuration) { error in
            if let error { NSLog("MenuBarHider: activation failed: \(error)") }
            finish(error == nil ? Assertion(raw: raw) : nil)
        }
    }
}
