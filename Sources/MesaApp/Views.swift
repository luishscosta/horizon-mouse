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
            Toggle(L("Ativo"), isOn: model.mouseEnabled)
                .toggleStyle(.switch)
            Text(L("Perfil global"))
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
                Text(L("O Mac Mouse Desk ainda não tem Acessibilidade")).fontWeight(.semibold)
                Text(L("Sem ela, a troca de mesas, a rolagem e os botões do mouse ficam desligados. Cada nova versão instalada precisa ser autorizada de novo."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Autorizar…")) { model.authorize() }.buttonStyle(.borderedProminent)
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
                Button(L("Restaurar gestos padrão")) { model.resetMappings() }
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
                    Picker(L("Botão"), selection: $model.selectedSlot) {
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
                        Label(model.mouse.isIdentifying ? L("Aguardando botão…") : L("Identificar botão"), systemImage: "record.circle")
                    }
                    Text(model.identifyMessage.isEmpty ? L("Pressione um botão do mouse para selecioná-lo. Se ele não for reconhecido, fica ligado ao controle escolhido no desenho.") : model.identifyMessage)
                        .font(.caption).foregroundStyle(.secondary)
                }
                GestureEditor(model: model, gesture: model.selectedGesture)
                Text(L("Clique simples pode aguardar o duplo clique quando ambos estão configurados. Esquerdo e direito seguem o padrão."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.selectedSlot == .top && model.profile.topButtonNumber == nil {
                    Text(L("Use Identificar botão e pressione o botão acima da roda. Se nada acontecer, o mouse trata esse botão no próprio firmware (ex.: DPI) e o macOS não o recebe."))
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
                Button(model.recordingGesture == gesture ? L("Pressione o atalho… (Esc cancela)") :
                        (model.mapping.shortcut(gesture)?.display ?? L("Gravar atalho"))) {
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
            Label(L("TESTE AO VIVO"), systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.mouse.isEnabled
                 ? L("Use o mouse: cada botão, gesto e giro que o Mac Mouse Desk reconhece aparece aqui, com a ação executada. Apertar um botão também o seleciona no desenho.")
                 : L("Ligue o Mac Mouse Desk para testar os gestos."))
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                if model.mouse.recentEvents.isEmpty {
                    Text(L("Nenhum evento ainda")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
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
                Text(model.mouse.fullSwitchPerRoll ? L("Rodinha lateral · uma mesa por giro") : L("Rodinha lateral · %ld passos por mesa", Int(model.mouse.stepsPerSpace))).font(.caption)
                Spacer()
                Button(L("Ajustar em Rolagem →")) { model.tab = .scroll }.buttonStyle(.link).font(.caption)
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
            SettingsSection(title: L("Roda principal"), detail: L("Movimento vertical")) {
                SliderRow(title: L("Velocidade vertical"), value: model.verticalSpeed, range: 10...100,
                          label: "\(Int(model.verticalSpeed.wrappedValue))%", low: L("Mais precisa"), high: L("Mais rápida"))
                Toggle(isOn: model.natural) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Rolagem natural")).fontWeight(.medium)
                        Text(L("O conteúdo acompanha o movimento dos dedos, como no trackpad. Vale só para o mouse."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsSection(title: L("Rodinha lateral"), detail: L("Trocar Mesas")) {
                Toggle(isOn: model.fullSwitch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Uma mesa por giro")).fontWeight(.medium)
                        Text(L("Cada giro da rodinha completa a troca de mesa, como deslizar no trackpad. Pause um instante para trocar de novo."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.fullSwitch.wrappedValue {
                    SliderRow(title: L("Passos por mesa"), value: model.steps, range: 2...500,
                              label: L("%ld passos", Int(model.steps.wrappedValue)), low: L("2 passos"), high: L("500 passos"))
                    Text(L("Quantos passos da rodinha lateral levam à mesa seguinte. Um valor maior revela a próxima mesa mais devagar."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("Inverter direção"), isOn: model.inverted)
                // Key and speed sit together: the key switches the wheel to sideways scrolling at this speed.
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L("Segurar para rolar na horizontal"), selection: model.horizontalKey) {
                        ForEach(HorizontalScrollKey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    SliderRow(title: L("Velocidade horizontal"), value: model.horizontalSpeed, range: 10...100,
                              label: "\(Int(model.horizontalSpeed.wrappedValue))%", low: L("Mais precisa"), high: L("Mais rápida"))
                    Text(L("Com a tecla pressionada, a rodinha lateral rola o conteúdo para os lados nesta velocidade, sem trocar de mesa."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
            }
            Text(L("Se o app do fabricante do mouse permitir, deixe a rodinha lateral como rolagem horizontal, sem atalhos. O Mac Mouse Desk não depende desse app."))
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
            SettingsSection(title: L("Execução"), detail: L("Barra de menus e segundo plano")) {
                toggle(model.runInBackground, L("Rodar em segundo plano"), L("Ao fechar a janela, o Mac Mouse Desk continua aplicando os ajustes do mouse."))
                toggle(model.showInDock, L("Mostrar no Dock"), L("Mostra o Mac Mouse Desk no Dock e no Command-Tab enquanto ele estiver aberto."))
                toggle(model.showMenuBarIcon, L("Mostrar ícone na barra de menus"), L("Acesso rápido para abrir os ajustes, pausar o mouse e sair."))
                toggle(model.openAtLogin, L("Abrir ao iniciar sessão"), L("Inicia o Mac Mouse Desk em segundo plano quando você entra no Mac."))
                if model.loginNeedsApproval {
                    note(L("Autorize o Mac Mouse Desk em Ajustes do Sistema → Geral → Itens de Início de Sessão."))
                }
                if model.runInBackground.wrappedValue && !model.showMenuBarIcon.wrappedValue {
                    note(L("Sem o ícone, abra o Mac Mouse Desk de novo pela pasta Aplicativos para ver esta janela."))
                }
            }
            SettingsSection(title: L("Idioma"), detail: L("Interface do app")) {
                Picker(L("Idioma do app"), selection: model.language) {
                    Text(L("Padrão do sistema (%@)", model.systemLanguageName)).tag("system")
                    ForEach(AppModel.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Text(L("Por padrão, o Mac Mouse Desk usa o idioma definido em Ajustes do Sistema › Geral › Idioma e Região."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.languageChanged {
                    HStack {
                        note(L("O novo idioma vale depois de reabrir o Mac Mouse Desk."))
                        Button(L("Reabrir agora")) { model.relaunch() }
                    }
                }
            }
            SettingsSection(title: L("Permissões"), detail: L("Privacidade e Segurança")) {
                HStack {
                    Button(L("Abrir Acessibilidade")) { model.openPermission("Privacy_Accessibility") }
                    Button(L("Monitoração de Entrada (opcional)")) { model.openPermission("Privacy_ListenEvent") }
                }
                Text(L("A captura do mouse precisa de Acessibilidade. Ao sair, o Mac Mouse Desk libera o mouse."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Mac Mouse Desk " + L("Versão %@", appVersion)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
