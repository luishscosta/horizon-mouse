import AppKit
import MouseKit
import SwiftUI

private let showNotification = Notification.Name("local.macos-config.Mesa.show")

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.mouse.stop()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        if !model.runInBackground.wrappedValue { NSApp.terminate(nil) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseMenu.title = model.mouse.isEnabled ? L("Pausar mouse") : L("Ativar mouse")
    }

    private func buildMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mac Mouse Desk")
        statusItem.button?.toolTip = "Mac Mouse Desk"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let version = NSMenuItem(title: "Mac Mouse Desk " + L("Versão %@", appVersion), action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        menu.addItem(item(L("Abrir ajustes do Mac Mouse Desk…"), #selector(showSettings), key: ","))
        pauseMenu = item(L("Ativar mouse"), #selector(toggleMouse))
        menu.addItem(pauseMenu)
        menu.addItem(.separator())
        menu.addItem(item(L("Sair do Mac Mouse Desk"), #selector(quit), key: "q"))
        statusItem.menu = menu

        // Standard editing menu keeps copy/paste/select-all available in the text fields.
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item(L("Sair do Mac Mouse Desk"), #selector(quit), key: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: L("Editar"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L("Editar"))
        for (title, action, key) in [(L("Recortar"), "cut:", "x"), (L("Copiar"), "copy:", "c"), (L("Colar"), "paste:", "v"), (L("Selecionar Tudo"), "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Mac Mouse Desk"
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
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleMouse() { model.mouse.userSetEnabled(!model.mouse.isEnabled) }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--diagnose") {
    MainActor.assumeIsolated {
        print("Mac Mouse Desk — diagnóstico somente leitura")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let mouse = MouseController()
        mouse.start()
        print(mouse.diagnostics)
        print("Perfil de botões: \(String(data: (try? JSONEncoder().encode(mouse.profile)) ?? Data(), encoding: .utf8) ?? "")")
        mouse.stop()
        print("Nenhum evento de mouse foi aplicado.")
    }
} else {
    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
