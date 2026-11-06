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
        .frame(minWidth: 900, minHeight: 640)
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert?.message ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.tab.heading.0).font(.system(size: 24, weight: .bold))
                Text(model.tab.heading.1).foregroundStyle(.secondary)
            }
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
                Button(model.recordingGesture == gesture ? L("Press the shortcut… (Esc cancels)") :
                        (model.mapping.shortcut(gesture)?.display ?? L("Record shortcut"))) {
                    model.recordShortcut(gesture)
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
                Text(model.mouse.fullSwitchPerRoll ? L("Side wheel · one desktop per roll") : L("Side wheel · %ld steps per desktop", Int(model.mouse.stepsPerSpace))).font(.caption)
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
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: L("Main wheel"), detail: L("Vertical movement")) {
                SliderRow(title: L("Vertical speed"), value: model.verticalSpeed, range: 10...100,
                          label: "\(Int(model.verticalSpeed.wrappedValue))%", low: L("More precise"), high: L("Faster"))
                SliderRow(title: L("Acceleration"), value: model.scrollAcceleration, range: 0...100,
                          label: model.scrollAcceleration.wrappedValue == 0 ? L("Off") : "\(Int(model.scrollAcceleration.wrappedValue))%",
                          low: L("Off"), high: L("Fast spins go farther"))
                SliderRow(title: L("Smoothness"), value: model.scrollSmoothness, range: 0...100,
                          label: "\(Int(model.scrollSmoothness.wrappedValue))%", low: L("Immediate"), high: L("Longer glide"))
                Toggle(isOn: model.natural) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Natural scrolling")).fontWeight(.medium)
                        Text(L("Content follows your finger movement, like on the trackpad. Applies only to the mouse."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsSection(title: L("Side wheel"), detail: L("Switch Desktops")) {
                Toggle(isOn: model.fullSwitch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("One desktop per roll")).fontWeight(.medium)
                        Text(L("Each roll of the wheel completes the desktop switch, like a trackpad swipe. Pause briefly to switch again."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.fullSwitch.wrappedValue {
                    SliderRow(title: L("Steps per desktop"), value: model.steps, range: 2...500,
                              label: L("%ld steps", Int(model.steps.wrappedValue)), low: L("2 steps"), high: L("500 steps"))
                    Text(L("How many side-wheel steps reach the next desktop. A higher value reveals the next desktop more slowly."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("Reverse direction"), isOn: model.inverted)
                // Key and speed sit together: the key switches the wheel to sideways scrolling at this speed.
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L("Hold to scroll horizontally"), selection: model.horizontalKey) {
                        ForEach(HorizontalScrollKey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    SliderRow(title: L("Horizontal speed"), value: model.horizontalSpeed, range: 10...100,
                              label: "\(Int(model.horizontalSpeed.wrappedValue))%", low: L("More precise"), high: L("Faster"))
                    Text(L("While the key is held, the side wheel scrolls content sideways at this speed, without switching desktops."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
            }
            Text(L("If your mouse maker's app allows it, keep the side wheel as horizontal scrolling, with no shortcuts. Horizon Mouse doesn't depend on that app."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 680)
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
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let label: String
    let low: String
    let high: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(label).font(.system(.callout, design: .monospaced)).foregroundStyle(.tint)
            }
            Slider(value: value, in: range)
            HStack { Text(low); Spacer(); Text(high) }.font(.caption2).foregroundStyle(.secondary)
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
let appVersion: String = {
    let info = Bundle.main.infoDictionary ?? [:]
    guard let short = info["CFBundleShortVersionString"] as? String else { return "dev" }
    return info["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
}()
