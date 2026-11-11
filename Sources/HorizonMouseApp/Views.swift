import MouseKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.mouse.hasAccessibility { permissionBanner }
            Divider()
            ScrollView {
                Group {
                    switch model.tab {
                    case .buttons: ButtonsView(model: model)
                    case .scroll: ScrollSettingsView(model: model)
                    case .settings: AppSettingsView(model: model)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            Divider()
            footer
        }
        .frame(minWidth: 940, minHeight: 640)
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert?.message ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.tab.heading.0).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(model.tab.heading.1).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.85)
            }
            // Fixed width and height: the tab picker must not move when the subtitle changes.
            .frame(width: 250, height: 60, alignment: .topLeading)
            Picker("", selection: $model.tab) {
                ForEach(AppTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 340)
            Spacer()
            Toggle(L("Active"), isOn: model.mouseEnabled)
                .toggleStyle(.switch)
            Text(L("Global profile"))
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Horizon Mouse doesn't have Accessibility yet")).fontWeight(.semibold)
                Text(L("Without it, desktop switching, scrolling and mouse buttons stay off."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Authorize…")) { model.authorize() }.buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Color.orange.opacity(0.12))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.mouse.isEnabled ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Text(model.mouse.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if model.tab == .buttons {
                Button(L("Restore default gestures")) { model.resetMappings() }
                    .buttonStyle(.link).font(.caption)
            }
            if let button = koFiButton {
                Link(destination: koFiURL) { Image(nsImage: button).resizable().scaledToFit().frame(height: 26) }
                    .buttonStyle(.plain)
                    .help(L("Donate"))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }
}

// MARK: - Buttons (Órbita)

struct ButtonsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker(L("Button"), selection: $model.selectedSlot) {
                        ForEach(MouseButtonSlot.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .frame(maxWidth: 280)
                    Spacer()
                    Text(model.buttonCode(model.selectedSlot))
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                }
                orbit
                HStack(spacing: 10) {
                    Button {
                        model.startIdentify()
                    } label: {
                        Label(model.mouse.isIdentifying ? L("Waiting for button…") : L("Identify button"), systemImage: "record.circle")
                    }
                    Text(model.identifyMessage.isEmpty ? L("Press a mouse button to select it. If it is not recognized, it is linked to the control selected in the drawing.") : model.identifyMessage)
                        .font(.caption).foregroundStyle(.secondary)
                }
                GestureEditor(model: model, gesture: model.selectedGesture)
                Text(L("A single click may wait for a double click when both are set. Left and right buttons keep the default."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.selectedSlot == .top && model.profile.topButtonNumber == nil {
                    Text(L("Use Identify button and press the button above the wheel. If nothing happens, the mouse handles it in firmware (e.g. DPI) and macOS never receives it."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            LivePanel(model: model)
                .frame(width: 280)
        }
    }

    private var orbit: some View {
        ZStack {
            Ellipse()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 40).padding(.vertical, 30)
            MouseDrawing(selected: $model.selectedSlot)
                .frame(width: 190, height: 285)
            VStack {
                HStack { card(.click); Spacer(); card(.doubleClick) }
                Spacer()
                HStack { card(.hold); Spacer(); card(.drag) }
            }
            .padding(20)
        }
        .frame(height: 330)
        .background(RoundedRectangle(cornerRadius: 120).fill(Color.primary.opacity(0.04)))
    }

    private func card(_ gesture: MouseGesture) -> some View {
        let selected = model.selectedGesture == gesture
        return Button {
            model.selectedGesture = gesture
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(gesture)).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture.title).fontWeight(.semibold)
                    Text(actionLabel(gesture)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 160)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gesture.title): \(actionLabel(gesture))")
    }

    private func actionLabel(_ gesture: MouseGesture) -> String {
        let mapping = model.mapping
        if mapping.action(gesture) == .shortcut, let shortcut = mapping.shortcut(gesture) { return shortcut.display }
        return mapping.action(gesture).title
    }

    private func icon(_ gesture: MouseGesture) -> String {
        switch gesture {
        case .click: "cursorarrow.click"
        case .doubleClick: "cursorarrow.click.2"
        case .hold: "hand.tap"
        case .drag: "arrow.left.and.right"
        }
    }
}

/// One place to set a shortcut: record it, or pick modifiers and a key. Recording and picking never overlap.
/// State lives in the model: the Command Line Tools toolchain has no SwiftUI macro plugin, so no @State.
struct ShortcutEditor: View {
    @ObservedObject var model: AppModel
    let gesture: MouseGesture

    private var shortcut: KeyShortcut? { model.mapping.shortcut(gesture) }
    private var key: UInt16 { shortcut?.keyCode ?? 49 }
    private var flags: CGEventFlags { shortcut.map { CGEventFlags(rawValue: $0.modifiers) } ?? .maskCommand }
    private var isRecording: Bool { model.recordingGesture == gesture }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(shortcut?.display ?? L("Not set"))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            Button(isRecording ? L("Press the shortcut… (Esc cancels)") : L("Record shortcut")) {
                if isRecording { model.stopRecording() } else { model.recordShortcut(gesture) }
            }
            .frame(maxWidth: .infinity)
            if !model.mouse.isEnabled {
                Text(L("Turn Horizon Mouse on to record system shortcuts such as ⌃→. Until then, pick them from the lists."))
                    .font(.caption).foregroundStyle(.orange).frame(width: 260, alignment: .leading)
            }
            Divider()
            Text(L("or choose")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(KeyShortcut.modifierSymbols, id: \.symbol) { item in
                    Toggle(item.symbol, isOn: Binding(get: { flags.contains(item.flag) }, set: {
                        var next = flags
                        if $0 { next.insert(item.flag) } else { next.remove(item.flag) }
                        save(key: key, flags: next)
                    }))
                    .toggleStyle(.button)
                }
                Picker(L("Key"), selection: Binding(get: { key }, set: { save(key: $0, flags: flags) })) {
                    ForEach(KeyShortcut.keyLabels, id: \.code) { Text(KeyShortcut.keyLabel($0.code) ?? $0.label).tag($0.code) }
                }
                .labelsHidden()
            }
        }
        .padding(16)
        .frame(width: 292)
        .onDisappear { model.stopRecording() }
    }

    private func save(key: UInt16, flags: CGEventFlags) {
        model.stopRecording()
        model.setShortcut(gesture, KeyShortcut.make(keyCode: key, flags: flags))
    }
}

struct GestureEditor: View {
    @ObservedObject var model: AppModel
    let gesture: MouseGesture

    var body: some View {
        HStack(spacing: 12) {
            Text(gesture.title).fontWeight(.semibold).frame(width: 110, alignment: .leading)
            Picker("", selection: model.action(for: gesture)) {
                ForEach(MouseAction.allCases.filter { $0 != .switchSpaces || gesture == .drag }, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .labelsHidden()
            if model.mapping.action(gesture) == .shortcut {
                Button(model.mapping.shortcut(gesture)?.display ?? L("Not set")) { model.shortcutEditor = gesture }
                    .popover(isPresented: Binding(get: { model.shortcutEditor == gesture }, set: { if !$0 { model.shortcutEditor = nil } })) {
                        ShortcutEditor(model: model, gesture: gesture)
                    }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }
}

struct LivePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("LIVE TEST"), systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.mouse.isEnabled
                 ? L("Use the mouse: every button, gesture and roll Horizon Mouse recognizes shows here, with the action it ran. Pressing a button also selects it in the drawing.")
                 : L("Turn Horizon Mouse on to test gestures."))
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                if model.mouse.recentEvents.isEmpty {
                    Text(L("No events yet")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(model.mouse.recentEvents.enumerated()), id: \.offset) { index, event in
                        Text(event)
                            .font(index == 0 ? .callout.weight(.semibold) : .caption)
                            .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.quaternary))
            Divider()
            HStack {
                Text(model.mouse.fullSwitchPerRoll ? L("Side wheel · one desktop per roll") : L("Side wheel · switch speed %ld%%", Int((model.mouse.switchSpeed * 100).rounded()))).font(.caption)
                Spacer()
                Button(L("Adjust in Scrolling →")) { model.tab = .scroll }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

/// Simplified top view of a mouse with side wheel and buttons; each remappable control is selectable.
struct MouseDrawing: View {
    @Binding var selected: MouseButtonSlot

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 62, bottomTrailingRadius: 62, topTrailingRadius: 70)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 62, bottomTrailingRadius: 62, topTrailingRadius: 70).stroke(.secondary.opacity(0.5)))
                .frame(width: 130, height: 250)
            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 95).offset(y: -78)
            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 130, height: 1).offset(y: -30)
            control(.middle, Capsule(), width: 16, height: 40, x: 0, y: -80)
            control(.top, RoundedRectangle(cornerRadius: 4), width: 14, height: 22, x: 0, y: -45)
            control(.front, Capsule(), width: 9, height: 38, x: -68, y: -10)
            control(.back, Capsule(), width: 9, height: 38, x: -68, y: 38)
        }
    }

    private func control<S: Shape>(_ slot: MouseButtonSlot, _ shape: S, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        shape
            .fill(selected == slot ? Color.accentColor : Color.secondary.opacity(0.3))
            .overlay(shape.stroke(selected == slot ? Color.accentColor : Color.secondary.opacity(0.6)))
            .frame(width: width, height: height)
            .contentShape(Rectangle().inset(by: -6))
            .onTapGesture { selected = slot }
            .offset(x: x, y: y)
            .accessibilityElement()
            .accessibilityLabel(slot.title)
            .accessibilityAddTraits(selected == slot ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selected = slot }
    }
}

// MARK: - Scroll

struct ScrollSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Two rows of two cards: cards in a row always share the same height.
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                mainWheel
                smoothness
            }
            HStack(alignment: .top, spacing: 18) {
                sideWheel
                horizontal
            }
            Text(L("If your mouse maker's app allows it, keep the side wheel as horizontal scrolling, with no shortcuts. Horizon Mouse doesn't depend on that app."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mainWheel: some View {
        SettingsCard(icon: "computermouse", title: L("Main wheel"), detail: L("Vertical movement")) {
            SliderRow(icon: "speedometer", title: L("Vertical speed"), value: model.verticalSpeed, range: 10...100,
                      label: "\(Int(model.verticalSpeed.wrappedValue))%", low: L("More precise"), high: L("Faster"))
            Divider()
            SliderRow(icon: "bolt.fill", title: L("Acceleration"), value: model.scrollAcceleration, range: 0...100,
                      label: model.scrollAcceleration.wrappedValue == 0 ? L("Off") : "\(Int(model.scrollAcceleration.wrappedValue))%",
                      low: L("Off"), high: L("Fast spins go farther"))
            Divider()
            ToggleRow(icon: "arrow.up.arrow.down", title: L("Natural scrolling"),
                      description: L("Content follows your finger movement, like on the trackpad. Applies only to the mouse."),
                      isOn: model.natural)
        }
    }

    private var sideWheel: some View {
        SettingsCard(icon: "square.on.square", title: L("Side wheel"), detail: L("Switch Desktops")) {
            ToggleRow(icon: "hand.point.up.left", title: L("One desktop per roll"),
                      description: L("Each roll of the wheel completes the desktop switch, like a trackpad swipe. Pause briefly to switch again."),
                      isOn: model.fullSwitch)
            if !model.fullSwitch.wrappedValue {
                Divider()
                SliderRow(icon: "speedometer", title: L("Switch speed"), value: model.switchSpeed, range: 0...100,
                          label: "\(Int(model.switchSpeed.wrappedValue))%", low: L("Slower"), high: L("Faster"),
                          description: L("How far you roll to reach the next desktop. Faster needs less."))
            }
            Divider()
            ToggleRow(icon: "arrow.left.arrow.right", title: L("Reverse direction"), description: nil, isOn: model.inverted)
        }
    }

    private var smoothness: some View {
        SettingsCard(icon: "wind", title: L("Smoothness"), detail: L("Vertical and horizontal scrolling")) {
            SliderRow(icon: "waveform.path", title: L("Glide"), value: model.scrollSmoothness, range: 0...100,
                      label: "\(Int(model.scrollSmoothness.wrappedValue))%", low: L("Immediate"), high: L("Longer glide"),
                      description: L("How long scrolling keeps gliding after the wheel stops. Higher feels softer, lower stops with the wheel."))
            Divider()
            ScrollTryOut()
        }
    }

    private var horizontal: some View {
        SettingsCard(icon: "arrow.left.and.right", title: L("Horizontal scrolling"), detail: L("Side wheel while holding a key")) {
            HStack(spacing: 12) {
                RowIcon(name: "keyboard")
                Text(L("Hold to scroll horizontally"))
                Spacer()
                Picker("", selection: model.horizontalKey) {
                    ForEach(HorizontalScrollKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Divider()
            SliderRow(icon: "speedometer", title: L("Horizontal speed"), value: model.horizontalSpeed, range: 10...100,
                      label: "\(Int(model.horizontalSpeed.wrappedValue))%", low: L("More precise"), high: L("Faster"),
                      description: L("While the key is held, the side wheel scrolls content sideways at this speed, without switching desktops."))
        }
    }
}

/// One grid that scrolls both ways, to feel speed, acceleration and glide: main wheel for vertical, side wheel plus
/// the chosen key for horizontal. It grows to fill its card.
struct ScrollTryOut: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Try it: scroll here with the main wheel, or hold the key and roll the side wheel."))
                .font(.caption).foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: 6) {
                    ForEach(0..<40, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(0..<30, id: \.self) { column in
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.accentColor.opacity((row + column) % 2 == 0 ? 0.35 : 0.15))
                                    .frame(width: 64, height: 24)
                                    .overlay(Text("\(row + 1),\(column + 1)").font(.caption2).foregroundStyle(.secondary))
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 90, idealHeight: 90, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A rounded card with an icon badge in its header; rows go inside.
struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor))
                Text(title).font(.headline)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct RowIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .foregroundStyle(.secondary)
            .frame(width: 22)
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    let description: String?
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(name: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                if let description { Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            content
        }
    }
}

struct SliderRow: View {
    var icon: String?
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let label: String
    let low: String
    let high: String
    var description: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon { RowIcon(name: icon).padding(.top, 1) }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(label).font(.system(.callout, design: .monospaced)).foregroundStyle(.tint)
                }
                Slider(value: value, in: range)
                HStack { Text(low); Spacer(); Text(high) }.font(.caption2).foregroundStyle(.secondary)
                if let description { Text(description).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Settings

struct AppSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: L("Running"), detail: L("Menu bar and background")) {
                toggle(model.runInBackground, L("Run in the background"), L("When you close the window, Horizon Mouse keeps applying the mouse settings."))
                toggle(model.showInDock, L("Show in Dock"), L("Shows Horizon Mouse in the Dock and Command-Tab while it's open."))
                toggle(model.showMenuBarIcon, L("Show icon in the menu bar"), L("Quick access to open settings, pause the mouse and quit."))
                toggle(model.openAtLogin, L("Open at login"), L("Starts Horizon Mouse in the background when you log in to your Mac."))
                if model.loginNeedsApproval {
                    note(L("Allow Horizon Mouse in System Settings → General → Login Items."))
                }
                if model.runInBackground.wrappedValue && !model.showMenuBarIcon.wrappedValue {
                    note(L("Without the icon, open Horizon Mouse again from the Applications folder to see this window."))
                }
            }
            SettingsSection(title: L("Language"), detail: L("App interface")) {
                Picker(L("App language"), selection: model.language) {
                    Text(L("System default (%@)", model.systemLanguageName)).tag("system")
                    ForEach(AppModel.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Text(L("By default, Horizon Mouse uses the language set in System Settings › General › Language & Region."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.languageChanged {
                    HStack {
                        note(L("The new language applies after reopening Horizon Mouse."))
                        Button(L("Reopen now")) { model.relaunch() }
                    }
                }
            }
            SettingsSection(title: L("Permissions"), detail: L("Privacy & Security")) {
                HStack {
                    Button(L("Open Accessibility")) { model.openPermission("Privacy_Accessibility") }
                    Button(L("Input Monitoring (optional)")) { model.openPermission("Privacy_ListenEvent") }
                }
                Text(L("Mouse capture needs Accessibility. When you quit, Horizon Mouse releases the mouse."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Horizon Mouse " + L("Version %@", appVersion)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .frame(maxWidth: 680)
    }

    private func toggle(_ binding: Binding<Bool>, _ title: String, _ help: String) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
    }
}

/// "0.1.2 (3)" from the bundle; "dev" when run outside an app bundle.
/// `#checkoutModal` makes Ko-fi open its donate popup straight away.
let koFiURL = URL(string: "https://ko-fi.com/G5E52AG4TG#checkoutModal")!

/// Official Ko-fi cup, shipped in the app bundle (absent when running from `swift run`).
let koFiIcon: NSImage? = Bundle.main.image(forResource: "KofiCup")

/// Ko-fi's official GitHub button (SVG), shown in the footer of every page.
let koFiButton: NSImage? = Bundle.main.url(forResource: "KofiButton", withExtension: "svg").flatMap { NSImage(contentsOf: $0) }

let appVersion: String = {
    let info = Bundle.main.infoDictionary ?? [:]
    guard let short = info["CFBundleShortVersionString"] as? String else { return "dev" }
    return info["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
}()
