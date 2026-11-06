// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Folds every other app's menu bar icon behind one item of ours and lists the
/// hidden ones in a drop-down menu.
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
final class MenuBarHiderController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""
    /// Non-nil while other apps' icons are hidden.
    private var assertion: NativeMenuBarVisibility.Assertion?
    /// Waits for the click that ends a revealed app's menu, then hides again.
    private var rehideMonitor: Any?
    /// Bumped on every state change so a late activation cannot win.
    private var generation = 0

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = "VorssaintMenuBarHider"
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        collapse()
    }

    /// Drops the restriction so the whole bar shows again.
    func tearDown() {
        stopRehideMonitor()
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
        let symbol: String
        let tip: String
        if !NativeMenuBarVisibility.isAvailable {
            symbol = "exclamationmark.triangle"
            tip = "이 macOS에서는 아이콘 숨기기를 쓸 수 없습니다"
        } else if isCollapsed {
            symbol = "chevron.compact.left"
            tip = "숨긴 메뉴 막대 아이콘"
        } else {
            symbol = "chevron.compact.right"
            tip = "메뉴 막대 아이콘 숨기기"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        statusItem.button?.toolTip = tip
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard NativeMenuBarVisibility.isAvailable else {
            menu.addItem(disabled("이 macOS에서는 아이콘 숨기기를 쓸 수 없습니다"))
            return
        }
        if isCollapsed {
            addHiddenIconItems(to: menu)
            menu.addItem(.separator())
            menu.addItem(action("아이콘 모두 보이기", #selector(showAll)))
        } else {
            menu.addItem(action("다른 앱 아이콘 숨기기", #selector(hideOthers)))
        }
    }

    private func addHiddenIconItems(to menu: NSMenu) {
        guard AXIsProcessTrusted() else {
            menu.addItem(action("숨긴 아이콘을 보려면 손쓰기 권한 허용…", #selector(requestAccessibility)))
            return
        }
        let extras = MenuBarExtra.hiddenCandidates(excludingBundleID: ownBundleID)
        guard !extras.isEmpty else {
            menu.addItem(disabled("숨긴 아이콘 없음"))
            return
        }
        for extra in extras {
            let item = action(extra.label, #selector(openExtra(_:)))
            item.image = extra.appIcon
            item.representedObject = extra
            menu.addItem(item)
        }
    }

    @objc private func showAll() { expand() }
    @objc private func hideOthers() { collapse() }
    @objc private func requestAccessibility() { Permissions.shared.requestAccessibility() }

    /// Brings the picked app's icons back for a moment, opens the one that was
    /// picked, and hides them again after the next click anywhere.
    @objc private func openExtra(_ sender: NSMenuItem) {
        guard let extra = sender.representedObject as? MenuBarExtra else { return }
        guard let bundleID = extra.bundleID else {
            // macOS cannot allow-list an app without a bundle id, so it stays
            // hidden; pressing it is all that is left to try.
            extra.press()
            return
        }
        collapse(revealing: bundleID) { [weak self] in
            // The bar needs a moment to place the revealed icon before it can
            // anchor the app's menu.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MenuBarExtra.refreshed(extra)?.press()
                self?.startRehideMonitor()
            }
        }
    }

    private func startRehideMonitor() {
        stopRehideMonitor()
        rehideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.stopRehideMonitor()
            // Late enough that a click choosing a menu entry still lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.isCollapsed else { return }
                self.collapse()
            }
        }
    }

    private func stopRehideMonitor() {
        if let rehideMonitor { NSEvent.removeMonitor(rehideMonitor) }
        rehideMonitor = nil
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

// MARK: - Other apps' menu bar icons, read through Accessibility

final class MenuBarExtra: NSObject {
    let pid: pid_t
    let bundleID: String?
    let index: Int
    let label: String
    let appIcon: NSImage?
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
        appIcon = app.icon.map { icon in
            let copy = icon.copy() as! NSImage
            copy.size = NSSize(width: 16, height: 16)
            return copy
        }
    }

    func press() {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
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
    /// System item ids to keep. Unknown ids are ignored, so the range covers
    /// items a given Mac does not have.
    private static let systemItemsToKeep = (0..<64).map { NSNumber(value: $0) }

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
