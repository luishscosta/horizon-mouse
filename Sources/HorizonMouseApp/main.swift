import AppKit
import MouseKit
import SwiftUI

private let showNotification = Notification.Name("io.github.luishscosta.horizonmouse.show")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var pauseMenu: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            // Opening the app again (e.g. from Applications with the menu bar icon hidden) shows the running copy.
            DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: showNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettings() }
        }
        updateDockIcon()
        buildMenus()
        buildWindow()
        model.onMenuBarChange = { [weak self] in self?.updateStatusItem() }
        model.onDockChange = { [weak self] in self?.updateDockIcon() }
        model.start()
        updateStatusItem()
        showSettings()
    }

    private var reallyQuit = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A plain quit request (Dock > Quit, `tell app to quit`) only closes the window while the app can live in the
        // menu bar. Quits with a reason (log out, restart, shut down) and the menu bar icon's Quit always go through.
        let quitReasonKey: AEKeyword = 0x7768793F // 'why?'
        let hasReason = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: quitReasonKey) != nil
        if !reallyQuit && !hasReason && runsInBackground {
            window.close()
            return .terminateCancel
        }
        model.mouse.stop()
        return .terminateNow
    }

    private var runsInBackground: Bool { model.runInBackground.wrappedValue && model.showMenuBarIcon.wrappedValue }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        if !model.runInBackground.wrappedValue { NSApp.terminate(nil) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseMenu.title = model.mouse.isEnabled ? L("Pause mouse") : L("Enable mouse")
    }

    private func buildMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Horizon Mouse")
        statusItem.button?.toolTip = "Horizon Mouse"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(item(L("Open Horizon Mouse Settings…"), #selector(showSettings), key: ","))
        pauseMenu = item(L("Enable mouse"), #selector(toggleMouse))
        menu.addItem(pauseMenu)
        menu.addItem(.separator())
        let donate = item(L("Donate"), #selector(openKoFi))
        if let icon = koFiIcon {
            let size = NSSize(width: 16 * icon.size.width / icon.size.height, height: 16)
            donate.image = NSImage(size: size, flipped: false) { icon.draw(in: $0); return true }
        }
        menu.addItem(donate)
        menu.addItem(.separator())
        let version = NSMenuItem(title: "Horizon Mouse " + L("Version %@", appVersion), action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(item(L("Quit Horizon Mouse"), #selector(quit), key: "q"))
        statusItem.menu = menu

        // Standard editing menu keeps copy/paste/select-all available in the text fields.
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item(L("Quit Horizon Mouse"), #selector(quitFromAppMenu), key: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L("Edit"))
        for (title, action, key) in [(L("Cut"), "cut:", "x"), (L("Copy"), "copy:", "c"), (L("Paste"), "paste:", "v"), (L("Select All"), "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Horizon Mouse"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.setFrameAutosaveName("MouseDeskMain")
        window.center()
    }

    private func updateDockIcon() {
        NSApp.setActivationPolicy(model.showInDock.wrappedValue ? .regular : .accessory)
        if window != nil { showSettings() }
    }

    private func updateStatusItem() { statusItem.isVisible = model.showMenuBarIcon.wrappedValue }

    @objc private func showSettings() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func openKoFi() { NSWorkspace.shared.open(koFiURL) }
    @objc private func quit() { reallyQuit = true; NSApp.terminate(nil) }
    /// Cmd+Q only closes the window while the app can keep running in the background with its menu bar icon;
    /// the menu bar icon's Quit item always quits.
    @objc private func quitFromAppMenu() {
        if runsInBackground { window.close() } else { NSApp.terminate(nil) }
    }
    @objc private func toggleMouse() { model.mouse.userSetEnabled(!model.mouse.isEnabled) }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

/// Carries settings over from the pre-0.2 bundle id, when the app was called Mac Mouse Desk.
private func migrateOldPreferences() {
    let flag = "Horizon.migratedFromMesa"
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: flag) else { return }
    defaults.set(true, forKey: flag)
    guard let old = defaults.persistentDomain(forName: "local.macos-config.Mesa") else { return }
    for (key, value) in old where key.hasPrefix("Mesa.") && defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
}
migrateOldPreferences()

let app = NSApplication.shared
if CommandLine.arguments.contains("--diagnose") {
    MainActor.assumeIsolated {
        print("Horizon Mouse — read-only diagnostics")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let mouse = MouseController()
        mouse.start()
        print(mouse.diagnostics)
        print("Button profile: \(String(data: (try? JSONEncoder().encode(mouse.profile)) ?? Data(), encoding: .utf8) ?? "")")
        mouse.stop()
        print("No mouse events were applied.")
    }
} else {
    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
