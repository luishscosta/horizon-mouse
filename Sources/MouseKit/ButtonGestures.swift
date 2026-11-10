import CoreGraphics
import Foundation

/// Keys are the pt-BR source text; Contents/Resources/*.lproj/Localizable.strings translate them.
public func L(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: key, table: nil) }
public func L(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }

public enum MouseGesture: String, Codable, CaseIterable, Sendable {
    case click, doubleClick, hold, drag
    public var title: String {
        switch self {
        case .click: L("Click")
        case .doubleClick: L("Double click")
        case .hold: L("Hold")
        case .drag: L("Drag")
        }
    }
}

public enum MouseAction: String, Codable, CaseIterable, Sendable {
    case standard, back, forward, shortcut, missionControl, showDesktop, switchSpaces, none
    public var title: String {
        switch self {
        case .standard: L("Mouse default")
        case .back: L("Back")
        case .forward: L("Forward")
        case .shortcut: L("Shortcut…")
        case .missionControl: "Mission Control"
        case .showDesktop: L("Show Desktop")
        case .switchSpaces: L("Switch Desktops")
        case .none: L("No action")
        }
    }
}

public struct KeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var display: String
    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

extension KeyShortcut {
    /// Modifiers a shortcut stores and displays, in display order.
    public static let modifierSymbols: [(flag: CGEventFlags, symbol: String)] = [
        (.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"),
    ]
    public static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    /// Keys offered in the picker (macOS virtual key codes). "Space" is localized when displayed.
    public static let keyLabels: [(code: UInt16, label: String)] = [
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"), (38, "J"), (40, "K"),
        (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"),
        (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0"),
        (49, "Space"), (36, "↩"), (48, "⇥"), (51, "⌫"), (53, "⎋"),
        (123, "←"), (124, "→"), (126, "↑"), (125, "↓"),
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
        (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
        (27, "-"), (24, "="), (33, "["), (30, "]"), (41, ";"), (39, "'"), (43, ","), (47, "."), (44, "/"), (42, "\\"), (50, "`"),
    ]

    public static func keyLabel(_ code: UInt16) -> String? {
        keyLabels.first { $0.code == code }.map { $0.label == "Space" ? L("Space") : $0.label }
    }

    /// Builds a shortcut with its display text; `character` names keys missing from ``keyLabels``.
    public static func make(keyCode: UInt16, flags: CGEventFlags, character: String? = nil) -> KeyShortcut {
        let kept = flags.intersection(modifierMask)
        let symbols = modifierSymbols.filter { kept.contains($0.flag) }.map(\.symbol).joined()
        let key = keyLabel(keyCode) ?? character?.uppercased() ?? "?"
        return KeyShortcut(keyCode: keyCode, modifiers: kept.rawValue, display: symbols + key)
    }

    public static func isArrow(_ keyCode: UInt16) -> Bool { (123...126).contains(keyCode) }

    /// A real arrow press carries the fn and numeric-pad flags; macOS shortcuts such as ⌃→ only match with them.
    public var playbackFlags: CGEventFlags {
        var flags = CGEventFlags(rawValue: modifiers).intersection(Self.modifierMask)
        if Self.isArrow(keyCode) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        return flags
    }
}

public struct ButtonMapping: Codable, Equatable, Sendable {
    public var actions: [String: MouseAction] = [:]
    public var shortcuts: [String: KeyShortcut] = [:]
    public init(_ actions: [MouseGesture: MouseAction] = [:]) {
        for (gesture, action) in actions { self.actions[gesture.rawValue] = action }
    }
    public func action(_ gesture: MouseGesture) -> MouseAction { actions[gesture.rawValue] ?? .standard }
    public mutating func set(_ action: MouseAction, for gesture: MouseGesture) { actions[gesture.rawValue] = action }
    public func shortcut(_ gesture: MouseGesture) -> KeyShortcut? { shortcuts[gesture.rawValue] }
    public mutating func set(_ shortcut: KeyShortcut?, for gesture: MouseGesture) { shortcuts[gesture.rawValue] = shortcut }
    /// Gestures that need the button press withheld; standard ones replay the original click.
    public var handled: Set<MouseGesture> { Set(MouseGesture.allCases.filter { action($0) != .standard }) }
}

/// Extra mouse controls that can be remapped (left/right always stay native). CGEvent button numbers are zero-based.
public enum MouseButtonSlot: String, Codable, CaseIterable, Sendable {
    case top, middle, front, back
    public var title: String {
        switch self {
        case .top: L("Button above the wheel")
        case .middle: L("Middle button")
        case .front: L("Front side button")
        case .back: L("Back side button")
        }
    }
    /// The top button has no fixed number: it is learned with "Identify button".
    public var fixedButtonNumber: Int? {
        switch self {
        case .middle: 2
        case .back: 3
        case .front: 4
        case .top: nil
        }
    }
}

/// Some mice send a keyboard shortcut from a button (for example the middle button sends ⌘Space).
/// Such a button gets a virtual number above every real button: base + key code.
public enum KeyButton {
    public static let base = 1000
    public static func number(keyCode: Int) -> Int { base + keyCode }
    public static func keyCode(_ number: Int) -> CGKeyCode? { number >= base ? CGKeyCode(number - base) : nil }
}

public struct MappingProfile: Codable, Equatable, Sendable {
    public var buttons: [String: ButtonMapping]
    public var topButtonNumber: Int?
    /// Button numbers learned with "Identify button" for slots whose usual number the mouse does not send.
    public var learned: [String: Int]?

    public init(buttons: [String: ButtonMapping] = [:], topButtonNumber: Int? = nil) {
        self.buttons = buttons
        self.topButtonNumber = topButtonNumber
    }

    /// Side buttons keep their native click and switch desktops when dragged.
    public static let defaults = MappingProfile(buttons: [
        MouseButtonSlot.front.rawValue: ButtonMapping([.drag: .switchSpaces]),
        MouseButtonSlot.back.rawValue: ButtonMapping([.drag: .switchSpaces])
    ])

    public func mapping(_ slot: MouseButtonSlot) -> ButtonMapping { buttons[slot.rawValue] ?? ButtonMapping() }
    public mutating func set(_ mapping: ButtonMapping, for slot: MouseButtonSlot) { buttons[slot.rawValue] = mapping }

    public func buttonNumber(_ slot: MouseButtonSlot) -> Int? {
        learned?[slot.rawValue] ?? slot.fixedButtonNumber ?? topButtonNumber
    }

    /// Ties a button the mouse sends to a slot: the top button, or a slot the mouse reports differently.
    public mutating func learn(_ number: Int, for slot: MouseButtonSlot) {
        if slot == .top { topButtonNumber = number } else { learned = (learned ?? [:]).merging([slot.rawValue: number]) { $1 } }
    }

    public func slot(forButton number: Int) -> MouseButtonSlot? {
        MouseButtonSlot.allCases.first { buttonNumber($0) == number }
    }
}

/// Outputs of ``ButtonGestureMachine``. The controller turns them into actions or replayed events.
public enum GestureOutput: Equatable, Sendable {
    case perform(MouseGesture)
    case replayDown
    case replayClick
    case dragBegan
    case drag(dx: Double, dy: Double)
    case dragEnded
}

/// Recognizes click, double click, hold and drag for one button. Pure: time and motion are passed in.
public struct ButtonGestureMachine: Sendable {
    public static let holdDelay = 0.45
    public static let doubleClickWindow = 0.3
    public static let dragThreshold = 6.0

    enum Phase: Equatable {
        case idle
        case pressed(at: Double, dx: Double, dy: Double)
        case waitingDouble(releasedAt: Double)
        case secondPress
        case dragging
        case holdFired
        case passthrough
    }

    public let handled: Set<MouseGesture>
    private(set) var phase = Phase.idle

    public init(handled: Set<MouseGesture>) { self.handled = handled }

    public var isIdle: Bool { phase == .idle }

    /// True while the machine believes the button is down.
    public var isHolding: Bool {
        switch phase {
        case .pressed, .secondPress, .dragging, .holdFired, .passthrough: true
        case .idle, .waitingDouble: false
        }
    }

    /// When the controller should call ``tick(at:)`` next.
    public var deadline: Double? {
        switch phase {
        case .pressed(let at, _, _): at + Self.holdDelay
        case .waitingDouble(let released): released + Self.doubleClickWindow
        default: nil
        }
    }

    /// Returns whether the original event must reach the system.
    public mutating func down(at time: Double) -> (pass: Bool, outputs: [GestureOutput]) {
        if case .waitingDouble(let released) = phase, time - released <= Self.doubleClickWindow {
            phase = .secondPress
            return (false, [])
        }
        var outputs: [GestureOutput] = []
        if case .waitingDouble = phase { outputs = finishSingleClick() }
        phase = .pressed(at: time, dx: 0, dy: 0)
        return (false, outputs)
    }

    public mutating func move(dx: Double, dy: Double) -> (pass: Bool, outputs: [GestureOutput]) {
        switch phase {
        case .pressed(let at, let x, let y):
            let total = (x + dx, y + dy)
            guard hypot(total.0, total.1) >= Self.dragThreshold else {
                phase = .pressed(at: at, dx: total.0, dy: total.1)
                return (false, [])
            }
            guard handled.contains(.drag) else {
                phase = .passthrough
                return (true, [.replayDown])
            }
            phase = .dragging
            return (false, [.dragBegan, .drag(dx: total.0, dy: total.1)])
        case .dragging: return (false, [.drag(dx: dx, dy: dy)])
        case .passthrough, .idle, .waitingDouble: return (true, [])
        case .secondPress, .holdFired: return (false, [])
        }
    }

    public mutating func up(at time: Double) -> (pass: Bool, outputs: [GestureOutput]) {
        switch phase {
        case .pressed:
            if handled.contains(.doubleClick) {
                phase = .waitingDouble(releasedAt: time)
                return (false, [])
            }
            phase = .idle
            return (false, [handled.contains(.click) ? .perform(.click) : .replayClick])
        case .secondPress:
            phase = .idle
            return (false, [.perform(.doubleClick)])
        case .dragging:
            phase = .idle
            return (false, [.dragEnded])
        case .holdFired:
            phase = .idle
            return (false, [])
        case .passthrough, .idle, .waitingDouble:
            if phase == .passthrough { phase = .idle }
            return (true, [])
        }
    }

    public mutating func tick(at time: Double) -> [GestureOutput] {
        switch phase {
        case .pressed(let at, _, _) where time - at >= Self.holdDelay:
            if handled.contains(.hold) {
                phase = .holdFired
                return [.perform(.hold)]
            }
            // Native long press (e.g. middle-button autoscroll) keeps working.
            phase = .passthrough
            return [.replayDown]
        case .waitingDouble(let released) where time - released >= Self.doubleClickWindow:
            phase = .idle
            return finishSingleClick()
        default:
            return []
        }
    }

    /// Ends any gesture in progress (pause, disconnect, settings change).
    public mutating func cancel() -> [GestureOutput] {
        let wasDragging = phase == .dragging
        phase = .idle
        return wasDragging ? [.dragEnded] : []
    }

    private func finishSingleClick() -> [GestureOutput] {
        [handled.contains(.click) ? .perform(.click) : .replayClick]
    }
}

/// Holding this key makes the side wheel send its original horizontal scroll instead of switching desktops.
public enum HorizontalScrollKey: String, CaseIterable, Sendable {
    case none, option, shift, control, command
    public var title: String {
        switch self {
        case .none: L("None")
        case .option: "⌥ Option"
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .command: "⌘ Command"
        }
    }
    public var flag: CGEventFlags {
        switch self {
        case .none: []
        case .option: .maskAlternate
        case .shift: .maskShift
        case .control: .maskControl
        case .command: .maskCommand
        }
    }
    public func isHeld(_ flags: CGEventFlags) -> Bool { self != .none && flags.contains(flag) }
}

/// Vertical direction for the mouse relative to the system-wide natural scrolling setting.
public enum NaturalScroll {
    public static func multiplier(deviceNatural: Bool, systemNatural: Bool) -> Double {
        deviceNatural == systemNatural ? 1 : -1
    }
}
