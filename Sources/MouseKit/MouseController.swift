import AppKit
import ApplicationServices
import MouseBridge
import os

private let log = Logger(subsystem: "local.macos-config.Mesa", category: "mouse")

@MainActor
public final class MouseController {
    public var onChange: (() -> Void)?
    public private(set) var status = L("Pausado")
    public var isEnabled: Bool { capture.isEnabled }
    public private(set) var diagnostics = "Mouse: aguardando observação."
    public var stepsPerSpace: Double {
        get { SwipeState.clampSteps(UserDefaults.standard.object(forKey: "Mesa.mouse.stepsPerSpace") as? Double ?? 12) }
        set { UserDefaults.standard.set(SwipeState.clampSteps(newValue), forKey: "Mesa.mouse.stepsPerSpace"); onChange?() }
    }
    public var verticalSpeed: Double {
        get { VerticalScrollState.clampSpeed(UserDefaults.standard.object(forKey: "Mesa.mouse.verticalSpeed") as? Double ?? 0.1) }
        set { UserDefaults.standard.set(VerticalScrollState.clampSpeed(newValue), forKey: "Mesa.mouse.verticalSpeed"); onChange?() }
    }
    public var horizontalSpeed: Double {
        get { VerticalScrollState.clampSpeed(UserDefaults.standard.object(forKey: "Mesa.mouse.horizontalSpeed") as? Double ?? 0.1) }
        set { UserDefaults.standard.set(VerticalScrollState.clampSpeed(newValue), forKey: "Mesa.mouse.horizontalSpeed"); onChange?() }
    }
    /// The user's on/off choice, kept across launches; capture resumes once permission is present.
    public var wantsEnabled: Bool { UserDefaults.standard.bool(forKey: "Mesa.mouse.enabled") }
    public var hasAccessibility: Bool { AXIsProcessTrusted() }
    public func userSetEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "Mesa.mouse.enabled")
        setEnabled(enabled)
    }
    public var horizontalScrollKey: HorizontalScrollKey {
        get { HorizontalScrollKey(rawValue: UserDefaults.standard.string(forKey: "Mesa.mouse.horizontalKey") ?? "") ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "Mesa.mouse.horizontalKey"); onChange?() }
    }
    /// Each roll of the side wheel switches one whole desktop; off = gradual, by steps per desktop.
    public var fullSwitchPerRoll: Bool {
        get { UserDefaults.standard.object(forKey: "Mesa.mouse.fullSwitch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.mouse.fullSwitch"); onChange?() }
    }
    public var isInverted: Bool {
        get { UserDefaults.standard.bool(forKey: "Mesa.mouse.inverted") }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.mouse.inverted"); onChange?() }
    }
    /// macOS natural scrolling (global, shared with the trackpad).
    public var systemNaturalScroll: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }
    /// Mouse-only natural scrolling (the trackpad keeps the system setting); follows the system setting until changed.
    public var naturalScroll: Bool {
        get { UserDefaults.standard.object(forKey: "Mesa.mouse.natural") as? Bool ?? systemNaturalScroll }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.mouse.natural"); onChange?() }
    }
    public var profile: MappingProfile {
        get {
            guard let data = UserDefaults.standard.data(forKey: "Mesa.mouse.profile"),
                  let profile = try? JSONDecoder().decode(MappingProfile.self, from: data) else { return .defaults }
            return profile
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "Mesa.mouse.profile")
            cancelButtonGestures()
            onChange?()
        }
    }
    /// While true, the next mouse button press is reported through ``onIdentify`` instead of being mapped.
    public var isIdentifying = false
    public var onIdentify: ((Int) -> Void)?
    /// What the app recognized recently (newest first), for the live test panel.
    public private(set) var recentEvents: [String] = []
    /// Called on every press of a remappable button, mapped or not.
    public var onButtonPressed: ((MouseButtonSlot) -> Void)?
    private var lastNote = (text: "", time: -10.0)

    private func note(_ text: String) {
        // Wheel notches arrive in bursts: one line per burst.
        guard text != lastNote.text || now - lastNote.time > 1 else { lastNote.time = now; return }
        lastNote = (text, now)
        recentEvents.insert(text, at: 0)
        if recentEvents.count > 8 { recentEvents.removeLast() }
        onChange?()
    }

    private func buttonName(_ button: Int) -> String { profile.slot(forButton: button)?.title ?? L("Botão %ld", button + 1) }

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var observationTimer: Timer?
    private var frameTimer: Timer?
    private var endTimers: [Timer] = []
    private var capture = MouseCaptureState()
    private var observers: [NSObjectProtocol] = []
    private var swipe = SwipeState()
    private var activeSender: UInt64 = 0
    private var verticalSender: UInt64 = 0
    private var verticalMetadata: VerticalScrollMetadata?
    private var horizontalSender: UInt64 = 0
    private var horizontalMetadata: VerticalScrollMetadata?
    private var lastAutoEnable = -10.0
    private var started = false
    private var sleeping = false
    private var machines: [Int: ButtonGestureMachine] = [:]
    private var gestureTimer: Timer?
    /// Buttons seen physically up on one poll; recovered only if still pending on the next (the real event may be in flight).
    private var releaseSuspects: Set<Int> = []
    private var spacesDragActive = false
    private let marker: Int64 = 0x4d455341
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var permissionsGranted: Bool { AXIsProcessTrusted() }
    private var currentPermissions: MousePermissionState {
        MousePermissionState(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess(),
                             eventPosting: CGPreflightPostEventAccess())
    }

    public init() {}

    deinit {
        observationTimer?.invalidate()
        frameTimer?.invalidate()
        endTimers.forEach { $0.invalidate() }
        for output in swipe.cancel() { _ = MBPostDockSwipe(output.phase.rawValue, output.progress, 0) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Observation only; capture always requires an explicit setEnabled(true).
    public func start() {
        guard !started else { return }
        started = true
        _ = MBInitialize()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = true
                self?.setEnabled(false)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = false
                self?.refresh()
            }
        })
        observationTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(observationTimer!, forMode: .common)
        refresh()
    }

    public func setEnabled(_ enabled: Bool) {
        if !enabled {
            deactivate()
            status = L("Pausado")
            onChange?()
            return
        }
        start()
        guard !isEnabled else { return }
        guard !sleeping else { status = L("Pausado durante repouso"); onChange?(); return }
        let permission = currentPermissions
        guard permission.canAttemptCapture else {
            status = capture.updatePermissions(permission) ?? permission.pausedStatus
            onChange?()
            return
        }
        _ = capture.updatePermissions(permission)
        guard MBDockSwipeAvailable(), MBPrepareDockSwipe() else {
            status = L("API de gestos indisponível; rolagem preservada")
            onChange?()
            return
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let controller = Unmanaged<MouseController>.fromOpaque(context).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            }
        }
        guard let newTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: Self.eventMask,
                                            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            status = currentPermissions.tapFailureStatus
            onChange?()
            return
        }
        tap = newTap
        tapSource = source
        tapHasKeyAccess = CGPreflightListenEventAccess()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        capture.enable(targetConnected: true)
        refresh()
    }

    // Key and pointer-move events are only acted on when they come from a mouse button that sends a shortcut.
    private static let eventMask: CGEventMask = [CGEventType.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                                 .keyDown, .keyUp, .flagsChanged, .mouseMoved]
        .reduce(0) { $0 | (1 << $1.rawValue) }

    public func requestPermissions() {
        start()
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        if !isEnabled { status = currentPermissions.pausedStatus }
        refresh()
        onChange?()
    }

    public func stop() {
        deactivate()
        observationTimer?.invalidate()
        observationTimer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        started = false
        status = L("Pausado")
        onChange?()
    }

    private func deactivate() {
        frameTimer?.invalidate()
        frameTimer = nil
        cancelButtonGestures()
        cancelEndResends()
        for output in swipe.cancel() { _ = MBPostDockSwipe(output.phase.rawValue, output.progress, 0) }
        activeSender = 0
        verticalSender = 0
        horizontalSender = 0
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        capture.pause()
    }

    /// Key events reach the tap only with Input Monitoring, decided when the tap is created.
    private var tapHasKeyAccess = false

    private func refresh() {
        let count = MBTargetDeviceCount()
        let permission = currentPermissions
        if isEnabled, tap != nil, permission.inputMonitoring, !tapHasKeyAccess {
            // Input Monitoring was just granted: recreate the tap so buttons that send a shortcut are seen.
            deactivate()
            setEnabled(true)
            return
        }
        let details = "Processo \(ProcessInfo.processInfo.processIdentifier): AX=\(permission.accessibility ? 1 : 0), ListenEvent (opcional)=\(permission.inputMonitoring ? 1 : 0), PostEvent=\(permission.eventPosting ? 1 : 0). Mouses HID: \(count); DockSwipe: \(MBDockSwipeAvailable() ? "sim" : "não")."
        let oldStatus = status
        if isEnabled {
            if !permission.canAttemptCapture {
                deactivate()
                status = permission.pausedStatus
            } else if !MBDockSwipeAvailable() {
                deactivate()
                status = L("API de gestos indisponível; rolagem preservada")
            } else {
                status = L("Ativo — mesas, botões e rolagem suave do mouse")
            }
        }
        if let updated = capture.updatePermissions(permission) { status = updated }
        if !isEnabled && wantsEnabled && !sleeping && permission.canAttemptCapture && now - lastAutoEnable > 2 {
            lastAutoEnable = now
            setEnabled(true)
            return
        }
        if diagnostics != details || oldStatus != status {
            diagnostics = details
            onChange?()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            deactivate()
            status = L("Captura interrompida pelo sistema; ative novamente")
            onChange?()
            return passthrough
        }
        guard isEnabled, event.getIntegerValueField(.eventSourceUserData) != marker else { return passthrough }
        if type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged {
            return handleButton(type: type, event: event)
        }
        if type == .keyDown || type == .keyUp || type == .flagsChanged { return handleMouseKey(type: type, event: event) }
        if type == .mouseMoved { return handleKeyButtonMove(event) }
        guard type == .scrollWheel else { return passthrough }
        guard permissionsGranted else {
            deactivate()
            let permission = currentPermissions
            status = capture.updatePermissions(permission) ?? permission.pausedStatus
            onChange?()
            return passthrough
        }
        // Fail open before suppressing an event if construction or association fails.
        guard MBPrepareDockSwipe() else { deactivate(); status = L("Gestos indisponíveis; rolagem preservada"); onChange?(); return passthrough }
        var sender: UInt64 = 0
        var rawX = 0.0
        var rawY = 0.0
        // Without HID data (sender 0) the CGEvent deltas still work.
        _ = MBReadWheel(event, &sender, &rawX, &rawY)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let pointX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let horizontal = continuous && pointX != 0 ? pointX / 10 : (fixedX != 0 ? fixedX : (lineX != 0 ? lineX : pointX / 10))
        let pointY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let pixelsY = pointY != 0 ? pointY : (fixedY != 0 ? fixedY * 10 : lineY * 10)
        let hasVertical = pixelsY != 0 || rawY != 0
        let input = WheelInput(horizontal: horizontal,
                               vertical: hasVertical ? (pixelsY != 0 ? pixelsY : .nan) : 0, rawHorizontal: rawX,
                               phase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
                               momentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
                               synthetic: event.getIntegerValueField(.eventSourceUserData) != 0 ||
                                event.getIntegerValueField(.eventSourceUnixProcessID) != 0)
        if let rawPixels = input.verticalPixels(capable: true) {
            let pixels = rawPixels * NaturalScroll.multiplier(deviceNatural: naturalScroll, systemNatural: systemNaturalScroll)
            let metadata = VerticalScrollMetadata(event: event)
            guard metadata.makeEvent(pixels: 0) != nil else { return passthrough }
            if verticalSender != 0 && verticalSender != sender { capture.vertical.cancel() }
            // Keep pending motion's modifiers and natural-scroll interpretation together.
            if capture.vertical.isActive && verticalMetadata?.isCompatible(with: metadata) == false { return passthrough }
            guard capture.vertical.move(pixels: pixels, speed: verticalSpeed, at: now) else { return passthrough }
            verticalSender = sender
            verticalMetadata = metadata
            startFrames()
            return nil
        }
        guard let steps = input.steps(capable: true) else { return passthrough }
        // Holding the chosen key scrolls sideways (no desktop switch) at the horizontal speed.
        let key = horizontalScrollKey
        if key.isHeld(event.flags) {
            let pixelsX = pointX != 0 ? pointX : (fixedX != 0 ? fixedX * 10 : lineX * 10)
            var metadata = VerticalScrollMetadata(event: event)
            // Apps must see a plain scroll: the key only selects the mode (Option-scroll means "faster" in some apps).
            metadata.flags.remove(key.flag)
            note(L("Rodinha lateral + %@ → rolagem horizontal", key.title))
            if horizontalSender != 0 && horizontalSender != sender { capture.horizontal.cancel() }
            if capture.horizontal.isActive && horizontalMetadata?.isCompatible(with: metadata) == false { return passthrough }
            guard capture.horizontal.move(pixels: pixelsX != 0 ? pixelsX : steps * 10, speed: horizontalSpeed, at: now) else { return passthrough }
            horizontalSender = sender
            horizontalMetadata = metadata
            startFrames()
            return nil
        }
        if activeSender != 0 && activeSender != sender {
            for output in swipe.cancel() { _ = MBPostDockSwipe(output.phase.rawValue, output.progress, 0) }
        }
        activeSender = sender
        cancelEndResends()
        let direction = isInverted ? 1.0 : -1.0
        let wasActive = swipe.isActive
        if fullSwitchPerRoll { swipe.flick(direction * steps, at: now) }
        else { swipe.move(by: direction * steps / stepsPerSpace, at: now) }
        if !wasActive && swipe.isActive { note(steps > 0 ? L("Rodinha lateral → trocar mesa (→)") : L("Rodinha lateral → trocar mesa (←)")) }
        startFrames()
        return nil
    }

    private enum ButtonEventKind { case down, up, move }

    private func handleButton(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Buttons 3+ (otherMouse) only come from mice; left/right are never in the tap mask.
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let kind: ButtonEventKind = type == .otherMouseDown ? .down : type == .otherMouseUp ? .up : .move
        return handleButton(button, kind: kind, event: event)
    }

    // MARK: Buttons that send a keyboard shortcut

    private var mouseSenders: [UInt64: Bool] = [:]
    private var keyButtonFlags: [Int: CGEventFlags] = [:]

    /// True when the event comes from a mouse's HID service rather than a keyboard.
    private func isFromMouse(_ event: CGEvent) -> Bool {
        let sender = MBEventSender(event)
        guard sender != 0 else { return false }
        if let known = mouseSenders[sender] { return known }
        let isMouse = MBTargetConnected(sender)
        mouseSenders[sender] = isMouse
        return isMouse
    }

    /// Only look at key events while identifying or when a slot maps a shortcut-sending button to gestures.
    private var watchesMouseKeys: Bool {
        isIdentifying || MouseButtonSlot.allCases.contains { slot in
            profile.buttonNumber(slot).flatMap(KeyButton.keyCode) != nil && !profile.mapping(slot).handled.isEmpty
        }
    }

    private func handleMouseKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        guard watchesMouseKeys, isFromMouse(event) else { return passthrough }
        // The mouse also sends the shortcut's modifier keys; hide them so apps never see a stray ⌘.
        guard type != .flagsChanged else { return nil }
        let button = KeyButton.number(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)))
        if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return machines[button] != nil || isIdentifying ? nil : passthrough
        }
        if type == .keyDown {
            keyButtonFlags[button] = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        }
        return handleButton(button, kind: type == .keyDown ? .down : .up, event: event)
    }

    /// Pointer motion while a shortcut-sending button is held drives its drag gesture; the pointer itself keeps moving.
    private func handleKeyButtonMove(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        guard let button = machines.first(where: { $0.key >= KeyButton.base && $0.value.isHolding })?.key else { return passthrough }
        _ = handleButton(button, kind: .move, event: event)
        return passthrough
    }

    private func handleButton(_ button: Int, kind: ButtonEventKind, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        let isDown = kind == .down
        if isDown {
            let slot = profile.slot(forButton: button)
            log.info("button down \(button, privacy: .public) slot=\(slot?.rawValue ?? "none", privacy: .public) handled=\(slot.map { self.profile.mapping($0).handled.map(\.rawValue).sorted().joined(separator: ",") } ?? "", privacy: .public)")
        }
        if isIdentifying {
            if isDown {
                isIdentifying = false
                onIdentify?(button)
            }
            return nil
        }
        let current = profile
        guard let slot = current.slot(forButton: button) else {
            if isDown { note(L("%@ · padrão do mouse", buttonName(button))) }
            return passthrough
        }
        if isDown { onButtonPressed?(slot) }
        let mapping = current.mapping(slot)
        if machines[button] == nil {
            // Buttons without remapped gestures stay fully native.
            guard isDown, !mapping.handled.isEmpty else {
                if isDown { note(L("%@ · padrão do mouse", slot.title)) }
                return passthrough
            }
            machines[button] = ButtonGestureMachine(handled: mapping.handled)
        }
        var machine = machines[button]!
        releaseSuspects.remove(button)
        if isDown && machine.isHolding {
            // The previous release never reached us (another tap consumed it): finish that press first.
            recoverRelease(&machine, button: button, mapping: mapping, location: event.location)
        }
        let result: (pass: Bool, outputs: [GestureOutput])
        switch kind {
        case .down: result = machine.down(at: now)
        case .up: result = machine.up(at: now)
        case .move: result = machine.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
        }
        machines[button] = machine.isIdle ? nil : machine
        run(result.outputs, button: button, mapping: mapping, location: event.location)
        scheduleGestureTimer()
        return result.pass ? passthrough : nil
    }

    private func run(_ outputs: [GestureOutput], button: Int, mapping: ButtonMapping, location: CGPoint) {
        for output in outputs {
            switch output {
            case .perform(let gesture):
                note(L("%@ · %@ → %@", buttonName(button), gesture.title, mapping.action(gesture).title))
                perform(mapping.action(gesture), gesture: gesture, mapping: mapping)
            case .replayDown:
                note(L("%@ · padrão do mouse", buttonName(button)))
                postButton(button, down: true, at: location)
            case .replayClick:
                note(L("%@ · %@ → %@", buttonName(button), MouseGesture.click.title, MouseAction.standard.title))
                postButton(button, down: true, at: location)
                postButton(button, down: false, at: location)
            case .dragBegan:
                let action = mapping.action(.drag)
                if action == .switchSpaces {
                    spacesDragActive = true
                    cancelEndResends()
                    // Freeze the pointer like a trackpad swipe; deltas keep arriving.
                    CGAssociateMouseAndMouseCursorPosition(0)
                    note(L("%@ · %@ → %@", buttonName(button), MouseGesture.drag.title, action.title))
                } else {
                    note(L("%@ · %@ → %@", buttonName(button), MouseGesture.drag.title, action.title))
                    perform(action, gesture: .drag, mapping: mapping)
                }
            case .drag(let dx, _):
                guard spacesDragActive else { continue }
                swipe.move(by: (isInverted ? 1 : -1) * dx / Self.dragPixelsPerSpace, at: now)
                startFrames()
            case .dragEnded:
                endSpacesDrag()
            }
        }
    }

    // ponytail: fixed drag distance per desktop; expose a slider if it feels wrong on a given mouse.
    private static let dragPixelsPerSpace = 400.0

    private func endSpacesDrag() {
        guard spacesDragActive else { return }
        spacesDragActive = false
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func perform(_ action: MouseAction, gesture: MouseGesture, mapping: ButtonMapping) {
        log.info("perform \(gesture.rawValue, privacy: .public) -> \(action.rawValue, privacy: .public)")
        switch action {
        case .standard, .none, .switchSpaces: break
        case .back: postKey(33, flags: .maskCommand) // ⌘[
        case .forward: postKey(30, flags: .maskCommand) // ⌘]
        case .shortcut:
            guard let shortcut = mapping.shortcut(gesture) else { return }
            postKey(CGKeyCode(shortcut.keyCode), flags: CGEventFlags(rawValue: shortcut.modifiers))
        case .missionControl:
            if !MBDockNotification("com.apple.expose.awake" as CFString) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            }
        case .showDesktop: _ = MBDockNotification("com.apple.showdesktop.awake" as CFString)
        }
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { return }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func postButton(_ button: Int, down: Bool, at location: CGPoint) {
        if let key = KeyButton.keyCode(button) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { return }
            event.flags = keyButtonFlags[button] ?? []
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
            return
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: down ? .otherMouseDown : .otherMouseUp,
                                  mouseCursorPosition: location, mouseButton: CGMouseButton(rawValue: UInt32(button)) ?? .center) else { return }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    private func scheduleGestureTimer() {
        gestureTimer?.invalidate()
        gestureTimer = nil
        // While a button is held, also poll its physical state: a release consumed by another tap
        // (e.g. Mission Control opening) would otherwise leave the gesture stuck.
        let polling = canReadButtonState && machines.values.contains(where: \.isHolding) ? now + 0.05 : nil
        guard let deadline = (machines.values.compactMap(\.deadline) + [polling].compactMap { $0 }).min() else { return }
        let timer = Timer(timeInterval: max(deadline - now, 0.001), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.gestureTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        gestureTimer = timer
    }

    private func recoverRelease(_ machine: inout ButtonGestureMachine, button: Int, mapping: ButtonMapping, location: CGPoint) {
        log.info("recovered lost release of button \(button, privacy: .public)")
        let release = machine.up(at: now)
        run(release.outputs, button: button, mapping: mapping, location: location)
        // A native press we let through still needs its matching release.
        if release.pass { postButton(button, down: false, at: location) }
    }

    /// Without Input Monitoring the HID state always reads "up", which would end every hold after 0.1 s,
    /// so the poll only runs when that permission exists; otherwise a lost release is fixed on the next press.
    private var canReadButtonState: Bool { CGPreflightListenEventAccess() }

    private func isPhysicallyDown(_ button: Int) -> Bool {
        if let key = KeyButton.keyCode(button) { return CGEventSource.keyState(.hidSystemState, key: key) }
        return CGEventSource.buttonState(.hidSystemState, button: CGMouseButton(rawValue: UInt32(button)) ?? .center)
    }

    private func gestureTick() {
        let current = profile
        let location = CGEvent(source: nil)?.location ?? .zero
        for (button, var machine) in machines {
            if machine.isHolding && canReadButtonState && !isPhysicallyDown(button) {
                if releaseSuspects.insert(button).inserted { continue }
                releaseSuspects.remove(button)
                if let slot = current.slot(forButton: button) {
                    recoverRelease(&machine, button: button, mapping: current.mapping(slot), location: location)
                    machines[button] = machine.isIdle ? nil : machine
                    continue
                }
            }
            let outputs = machine.tick(at: now)
            machines[button] = machine.isIdle ? nil : machine
            if let slot = current.slot(forButton: button) { run(outputs, button: button, mapping: current.mapping(slot), location: location) }
        }
        scheduleGestureTimer()
    }

    private func cancelButtonGestures() {
        for button in Array(machines.keys) { _ = machines[button]?.cancel() }
        machines = [:]
        releaseSuspects = []
        gestureTimer?.invalidate()
        gestureTimer = nil
        endSpacesDrag()
        isIdentifying = false
    }

    private func startFrames() {
        if frameTimer == nil {
            frameTimer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.frame() }
            }
            RunLoop.main.add(frameTimer!, forMode: .common)
        }
    }

    private func frame() {
        let outputs = swipe.frame(at: now)
        for output in outputs {
            guard MBPostDockSwipe(output.phase.rawValue, output.progress, output.velocity) else {
                deactivate()
                status = L("Falha ao gerar gesto; captura pausada")
                onChange?()
                return
            }
            if capture.endRetry.observe(output) { updateEndResends() }
        }
        let pixels = capture.vertical.frame(at: now)
        if pixels != 0 {
            guard let event = verticalMetadata?.makeEvent(pixels: pixels) else {
                deactivate()
                status = L("Falha ao suavizar rolagem; captura pausada")
                onChange?()
                return
            }
            event.post(tap: .cgSessionEventTap)
        }
        let pixelsX = capture.horizontal.frame(at: now)
        if pixelsX != 0 {
            guard let event = horizontalMetadata?.makeEvent(pixels: 0, horizontal: pixelsX) else {
                deactivate()
                status = L("Falha ao suavizar rolagem; captura pausada")
                onChange?()
                return
            }
            event.post(tap: .cgSessionEventTap)
        }
        if !swipe.isActive && !capture.vertical.isActive && !capture.horizontal.isActive {
            frameTimer?.invalidate()
            frameTimer = nil
            activeSender = 0
        }
    }

    private func updateEndResends() {
        endTimers.forEach { $0.invalidate() }
        endTimers = []
        guard let final = capture.endRetry.pending else { return }
        // Retry each ending, including exact chain boundaries; next begin cancels it.
        endTimers = [0.2, 0.5].map { delay in
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isEnabled, self.permissionsGranted,
                          self.capture.endRetry.pending == final else { return }
                    _ = MBPostDockSwipe(final.phase.rawValue, final.progress, 0)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }
    }

    private func cancelEndResends() {
        capture.endRetry.cancel()
        updateEndResends()
    }
}
