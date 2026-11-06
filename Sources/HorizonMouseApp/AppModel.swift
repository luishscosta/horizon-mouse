import AppKit
import Carbon.HIToolbox
import MouseKit
import ServiceManagement
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case buttons, scroll, settings
    var id: Self { self }
    var title: String {
        switch self {
        case .buttons: L("Buttons")
        case .scroll: L("Scrolling")
        case .settings: L("Settings")
        }
    }
    var heading: (String, String) {
        switch self {
        case .buttons: (L("Buttons and gestures"), L("Pick the button, set the gestures and try them."))
        case .scroll: (L("Scrolling"), L("Main wheel pace and switching desktops with the side wheel."))
        case .settings: (L("Settings"), L("How Horizon Mouse runs on your Mac and in which language."))
        }
    }
}

/// Bridges the AppKit controllers to SwiftUI. Controllers stay the source of truth.
@MainActor
final class AppModel: ObservableObject {
    let mouse = MouseController()
    var onMenuBarChange: (() -> Void)?
    var onDockChange: (() -> Void)?

    @Published var tab = AppTab.buttons
    @Published var selectedSlot = MouseButtonSlot.front
    @Published var selectedGesture = MouseGesture.drag
    @Published var identifyMessage = ""
    @Published var recordingGesture: MouseGesture?
    @Published var alert: (title: String, message: String)?
    @Published var languageChanged = false

    private var keyMonitor: Any?

    init() {
        mouse.onChange = { [weak self] in self?.objectWillChange.send() }
        mouse.onIdentify = { [weak self] button in self?.identified(button) }
        // Pressing a button jumps the editor to it, so the drawing follows the hand.
        mouse.onButtonPressed = { [weak self] slot in
            guard let self, self.tab == .buttons, self.selectedSlot != slot else { return }
            self.selectedSlot = slot
        }
    }

    func start() {
        mouse.start()
    }

    // MARK: Buttons

    var profile: MappingProfile { mouse.profile }
    var mapping: ButtonMapping { profile.mapping(selectedSlot) }

    func buttonCode(_ slot: MouseButtonSlot) -> String {
        if let number = profile.buttonNumber(slot) {
            return KeyButton.keyCode(number) != nil ? L("Mouse shortcut") : L("Button %ld", number + 1)
        }
        return L("Not identified")
    }

    func action(for gesture: MouseGesture) -> Binding<MouseAction> {
        Binding(get: { self.mapping.action(gesture) }, set: { action in
            var profile = self.profile
            var mapping = profile.mapping(self.selectedSlot)
            mapping.set(action, for: gesture)
            profile.set(mapping, for: self.selectedSlot)
            self.mouse.profile = profile
        })
    }

    func startIdentify() {
        guard mouse.isEnabled else {
            identifyMessage = L("Turn Horizon Mouse on to identify buttons.")
            return
        }
        mouse.isIdentifying.toggle()
        identifyMessage = mouse.isIdentifying ? L("Press a mouse button…") : ""
        if mouse.isIdentifying && !CGPreflightListenEventAccess() {
            // Buttons that send a keyboard shortcut (e.g. a middle button) are only visible with Input Monitoring.
            CGRequestListenEventAccess()
            identifyMessage = L("Press a mouse button… For a button that sends a keyboard shortcut, turn on Horizon Mouse under Input Monitoring.")
        }
        objectWillChange.send()
    }

    private func identified(_ button: Int) {
        var profile = self.profile
        if let slot = profile.slot(forButton: button) {
            selectedSlot = slot
        } else {
            // An unknown button belongs to the selected control (e.g. a middle button that sends a shortcut).
            profile.learn(button, for: selectedSlot)
            mouse.profile = profile
        }
        identifyMessage = KeyButton.keyCode(button) != nil
            ? L("%@ identified (sends a keyboard shortcut).", selectedSlot.title)
            : L("%@ identified (button %ld).", selectedSlot.title, button + 1)
    }

    func recordShortcut(_ gesture: MouseGesture) {
        stopRecording()
        recordingGesture = gesture
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.stopRecording(); return nil }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
                (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            var cgFlags = CGEventFlags()
            if flags.contains(.command) { cgFlags.insert(.maskCommand) }
            if flags.contains(.option) { cgFlags.insert(.maskAlternate) }
            if flags.contains(.control) { cgFlags.insert(.maskControl) }
            if flags.contains(.shift) { cgFlags.insert(.maskShift) }
            var profile = self.profile
            var mapping = profile.mapping(self.selectedSlot)
            mapping.set(KeyShortcut(keyCode: event.keyCode, modifiers: cgFlags.rawValue,
                                    display: symbols + (key == " " ? L("Space") : key)), for: gesture)
            profile.set(mapping, for: self.selectedSlot)
            self.mouse.profile = profile
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingGesture = nil
    }

    func resetMappings() { mouse.profile = .defaults }

    // MARK: Scroll

    var mouseEnabled: Binding<Bool> {
        Binding(get: { self.mouse.isEnabled }, set: { self.mouse.userSetEnabled($0) })
    }
    var verticalSpeed: Binding<Double> {
        Binding(get: { self.mouse.verticalSpeed * 100 }, set: { self.mouse.verticalSpeed = $0.rounded() / 100 })
    }
    var steps: Binding<Double> {
        Binding(get: { self.mouse.stepsPerSpace }, set: { self.mouse.stepsPerSpace = $0.rounded() })
    }
    var horizontalSpeed: Binding<Double> {
        Binding(get: { self.mouse.horizontalSpeed * 100 }, set: { self.mouse.horizontalSpeed = $0.rounded() / 100 })
    }
    /// Asks macOS to list Horizon Mouse under Accessibility (system prompt) and opens the pane.
    func authorize() {
        mouse.requestPermissions()
        openPermission("Privacy_Accessibility")
    }
    var natural: Binding<Bool> { Binding(get: { self.mouse.naturalScroll }, set: { self.mouse.naturalScroll = $0 }) }
    var fullSwitch: Binding<Bool> { Binding(get: { self.mouse.fullSwitchPerRoll }, set: { self.mouse.fullSwitchPerRoll = $0 }) }
    var horizontalKey: Binding<HorizontalScrollKey> {
        Binding(get: { self.mouse.horizontalScrollKey }, set: { self.mouse.horizontalScrollKey = $0 })
    }
    var inverted: Binding<Bool> { Binding(get: { self.mouse.isInverted }, set: { self.mouse.isInverted = $0 }) }

    // MARK: Settings

    var runInBackground: Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: "Mesa.app.background") as? Bool ?? true },
                set: { UserDefaults.standard.set($0, forKey: "Mesa.app.background"); self.objectWillChange.send() })
    }
    var showMenuBarIcon: Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: "Mesa.app.menubar") as? Bool ?? true },
                set: { UserDefaults.standard.set($0, forKey: "Mesa.app.menubar"); self.objectWillChange.send(); self.onMenuBarChange?() })
    }
    var showInDock: Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: "Mesa.app.dock") as? Bool ?? true },
                set: { UserDefaults.standard.set($0, forKey: "Mesa.app.dock"); self.objectWillChange.send(); self.onDockChange?() })
    }
    var openAtLogin: Binding<Bool> {
        Binding(get: { [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) }, set: { on in
            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { self.show(error) }
            self.objectWillChange.send()
        })
    }
    var loginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("pt-BR", "Português (Brasil)"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("it", "Italiano"),
        ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"), ("ru", "Русский"), ("tr", "Türkçe")
    ]
    /// The language macOS would pick for this app with no override.
    var systemLanguageName: String {
        let preferred = Bundle.preferredLocalizations(from: Self.languages.map(\.code), forPreferences: Locale.preferredLanguages).first ?? "en"
        return Self.languages.first { $0.code == preferred }?.name ?? "English"
    }
    var language: Binding<String> {
        Binding(get: { (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first ?? "system" },
                set: { code in
                    if code == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                    else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
                    self.languageChanged = true
                })
    }

    func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open '\(path)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    func openPermission(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        if !NSWorkspace.shared.open(url) {
            alert = (L("Open System Settings"), L("Go to Privacy & Security to authorize Horizon Mouse."))
        }
    }

    func show(_ error: Error) { alert = (L("Couldn't complete"), error.localizedDescription) }
}
