import AppKit
import MouseKit
import SwiftUI

/// Whip settings, stored in UserDefaults next to the other app settings.
enum WhipPrefs {
    static let defaultColor = "#8C5426"
    static let defaultApps = [
        "com.anthropic.claudefordesktop", "com.google.antigravity", "com.apple.Terminal", "com.googlecode.iterm2",
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.github.wez.wezterm"
    ]
    static var color: String {
        get { UserDefaults.standard.string(forKey: "Mesa.whip.color") ?? defaultColor }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.whip.color") }
    }
    static var apps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "Mesa.whip.apps") ?? defaultApps }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.whip.apps") }
    }
    static var text: String {
        get { UserDefaults.standard.string(forKey: "Mesa.whip.text") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.whip.text") }
    }
    static var enter: Bool {
        get { UserDefaults.standard.bool(forKey: "Mesa.whip.enter") }
        set { UserDefaults.standard.set(newValue, forKey: "Mesa.whip.enter") }
    }
    static var model: WhipModel {
        get { WhipModel(rawValue: UserDefaults.standard.string(forKey: "Mesa.whip.model") ?? "") ?? .classic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "Mesa.whip.model") }
    }
    /// Modifier that must be held with the click for the macro to run; none = every click.
    static var macroKey: HorizontalScrollKey {
        get { HorizontalScrollKey(rawValue: UserDefaults.standard.string(forKey: "Mesa.whip.macroKey") ?? "") ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "Mesa.whip.macroKey") }
    }
    static var shortcut: KeyShortcut? {
        get { UserDefaults.standard.data(forKey: "Mesa.whip.shortcut").flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "Mesa.whip.shortcut") }
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .brown
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

enum WhipTip { case knot, flap, dot, frayed }

/// A whip model, after real whip families: how long the handle and lash are, how limp the lash is and how it is drawn.
enum WhipModel: String, CaseIterable, Identifiable {
    case classic, stock, signal, snake, crop, neon
    var id: Self { self }
    var title: String {
        switch self {
        case .classic: L("Bullwhip")
        case .stock: L("Stockwhip")
        case .signal: L("Signal whip")
        case .snake: L("Snake whip")
        case .crop: L("Riding crop")
        case .neon: L("Neon")
        }
    }
    var count: Int { [.classic: 24, .stock: 22, .signal: 12, .snake: 26, .crop: 9, .neon: 28][self]! }
    var segment: CGFloat { [.classic: 7, .stock: 7, .signal: 7, .snake: 8, .crop: 9, .neon: 6.5][self]! }
    /// The stockwhip has a long handle, the snake whip none to speak of (just a heel knot).
    var handle: CGFloat { [.classic: 54, .stock: 84, .signal: 44, .snake: 18, .crop: 66, .neon: 50][self]! }
    var widths: (CGFloat, CGFloat) { [.classic: (5.5, 1.5), .stock: (4.5, 1.2), .signal: (5, 3), .snake: (8, 1.5), .crop: (4.5, 3.5), .neon: (3.5, 1.2)][self]! }
    /// Stiffness at the lash root and how fast it fades per segment; the crop stays stiff to the tip.
    var stiffness: (CGFloat, CGFloat) { [.classic: (0.5, 0.07), .stock: (0.55, 0.07), .signal: (0.6, 0.05), .snake: (0.35, 0.06), .crop: (0.95, 0.04), .neon: (0.4, 0.06)][self]! }
    var gravity: CGFloat { [.classic: 1500, .stock: 1400, .signal: 1500, .snake: 1800, .crop: 1500, .neon: 1300][self]! }
    var braid: Bool { self != .crop && self != .neon }
    var glow: Bool { self == .neon }
    var tip: WhipTip { [.classic: .knot, .stock: .knot, .signal: .frayed, .snake: .knot, .crop: .flap, .neon: .dot][self]! }
    var length: CGFloat { CGFloat(count) * segment }
}

enum WhipArt {
    /// Draws a whip from points [handle base, handle top / lash root, lash…] (view coordinates).
    static func draw(_ ctx: inout GraphicsContext, _ pts: [CGPoint], model: WhipModel, color: Color, scale k: CGFloat = 1) {
        guard pts.count > 3 else { return }
        let dark = Color(red: 0.36, green: 0.10, blue: 0.06), grip = Color(red: 0.62, green: 0.18, blue: 0.10)
        let base = pts[0], top = pts[1]
        let dx = top.x - base.x, dy = top.y - base.y, len = max(hypot(dx, dy), 0.001), ux = dx / len, uy = dy / len
        func along(_ f: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: base.x + ux * len * f - uy * side * k, y: base.y + uy * len * f + ux * side * k)
        }
        let (w0, w1) = model.widths
        if model.glow {
            var lash = Path()
            lash.move(to: pts[1]); for p in pts[2...] { lash.addLine(to: p) }
            ctx.stroke(lash, with: .color(color.opacity(0.18)), style: StrokeStyle(lineWidth: 16 * k, lineCap: .round, lineJoin: .round))
            ctx.stroke(lash, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 8 * k, lineCap: .round, lineJoin: .round))
        }
        for i in 2..<pts.count {   // lash, tapering
            var seg = Path()
            seg.move(to: pts[i - 1]); seg.addLine(to: pts[i])
            let width = (w0 - (w0 - w1) * CGFloat(i) / CGFloat(pts.count)) * k
            ctx.stroke(seg, with: .color(model.glow ? .white.opacity(0.9) : color), style: StrokeStyle(lineWidth: model.glow ? width * 0.5 : width, lineCap: .butt))
            if model.braid && i % 3 == 0 {
                ctx.stroke(seg, with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: [1.5, 5.5]))
            }
        }
        if let tip = pts.last, let before = pts.dropLast().last {
            let a = atan2(tip.y - before.y, tip.x - before.x)
            switch model.tip {
            case .knot: ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 3 * k, y: tip.y - 2 * k, width: 6 * k, height: 4 * k)), with: .color(dark))
            case .dot: ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4 * k, y: tip.y - 4 * k, width: 8 * k, height: 8 * k)), with: .color(color))
            case .flap:
                var flap = Path()
                flap.addRoundedRect(in: CGRect(x: -6 * k, y: -4 * k, width: 12 * k, height: 8 * k), cornerSize: CGSize(width: 2 * k, height: 2 * k))
                ctx.fill(flap.applying(CGAffineTransform(rotationAngle: a).concatenating(CGAffineTransform(translationX: tip.x, y: tip.y))), with: .color(dark))
            case .frayed:
                for d in [-0.5, 0, 0.5] {
                    var thread = Path()
                    thread.move(to: tip)
                    thread.addLine(to: CGPoint(x: tip.x + cos(a + d) * 9 * k, y: tip.y + sin(a + d) * 9 * k))
                    ctx.stroke(thread, with: .color(color), lineWidth: 1.4 * k)
                }
            }
        }
        // handle: rigid wrapped grip, end bands and the little loop at the bottom
        let loopCenter = along(-0.12)
        ctx.stroke(Path(ellipseIn: CGRect(x: loopCenter.x - 4 * k, y: loopCenter.y - 4 * k, width: 8 * k, height: 8 * k)), with: .color(dark), lineWidth: 2 * k)
        var body = Path()
        body.move(to: along(0)); body.addLine(to: along(1))
        ctx.stroke(body, with: .color(grip), style: StrokeStyle(lineWidth: 10 * k, lineCap: .round))
        for f in stride(from: 0.12, through: 0.88, by: 0.19) {
            var band = Path()
            band.move(to: along(f, -4)); band.addLine(to: along(f + 0.1, 4))
            ctx.stroke(band, with: .color(dark.opacity(0.7)), lineWidth: 2 * k)
        }
        for f in [0.0, 1.0] {
            var cap = Path()
            cap.move(to: along(f, -6)); cap.addLine(to: along(f, 6))
            ctx.stroke(cap, with: .color(dark), style: StrokeStyle(lineWidth: 4 * k, lineCap: .round))
        }
    }

    /// A resting S-curve of the model for previews: handle upright at the bottom, lash curling above it.
    static func preview(_ model: WhipModel, in size: CGSize, phase: Double) -> (points: [CGPoint], scale: CGFloat) {
        // One scale for every model (sized by the longest), so their different lengths show.
        let reach = WhipModel.allCases.map { $0.handle + $0.length * 0.82 }.max() ?? 1
        let k = min(1.35, (size.height - 24) / reach)
        let base = CGPoint(x: size.width / 2, y: size.height - 8)
        let top = CGPoint(x: base.x, y: base.y - model.handle * k)
        let amp = 40 * (model.length / 170) * k
        var pts = [base, top]
        for i in 1..<model.count {
            let t = Double(i) / Double(model.count - 1)
            pts.append(CGPoint(x: top.x + amp * sin(t * .pi * 2.2 + phase) * min(1, t * 3),
                               y: top.y - CGFloat(t) * model.length * 0.82 * k))
        }
        return (pts, k)
    }
}

/// Fun mode: a whip that swings with the pointer, cracks on click and urges on the chosen apps.
/// A rigid handle (its own angle, held upright by a stiff spring) carries a limp lash that gets lighter towards the
/// tip, so the wrist sweep of a crack sends a loop down the lash that snaps the tip.
@MainActor
final class WhipOverlay: ObservableObject {
    /// Points relative to the pointer, y up: [0] handle base, [1] handle top (lash root), then the lash.
    @Published var points: [CGPoint] = []
    @Published var phrase: (text: String, time: Date)?
    @Published var spark: Date = .distantPast
    @Published var color = Color(hex: WhipPrefs.color)
    @Published var style = WhipPrefs.model
    /// Runs the user's macro; set by the app model.
    var onSnap: (() -> Void)?

    static let size = CGSize(width: 560, height: 460)
    private var handleLength: CGFloat { style.handle }
    private var lashLength: CGFloat { style.segment }
    private static let phrases = [L("Faster!"), L("Keep going!"), L("Hurry up!"), L("Don't stop!"), L("Go, go, go!"), L("Chop chop!")]

    private var window: NSWindow?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var apps = Set(WhipPrefs.apps)
    private var pos: [CGPoint] = [], prev: [CGPoint] = []   // lash, screen coordinates, y up
    private var hand = CGPoint.zero, handVelocity = CGPoint.zero, angle: CGFloat = .pi / 2, spin: CGFloat = 0
    private var crackStart = Date.distantPast, crackSparked = true, macroArmed = true
    private var lastSay = Date(), lastSnap = Date.distantPast
    private var clock: CGFloat = 0

    var isOn = false {
        didSet { guard isOn != oldValue else { return }; isOn ? start() : stop() }
    }

    /// Re-reads color and app list after the settings change.
    func reload() {
        color = Color(hex: WhipPrefs.color)
        apps = Set(WhipPrefs.apps)
        if style != WhipPrefs.model {
            style = WhipPrefs.model
            if window != nil { rebuildLash() }
        }
    }

    private func rebuildLash() {
        let root = handleTop()
        pos = (0..<style.count).map { CGPoint(x: root.x, y: root.y - CGFloat($0) * lashLength) }
        prev = pos
    }

    var inTargetApp: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(apps.contains) ?? false }

    private func start() {
        reload()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: WhipCanvas(model: self))
        window.isReleasedWhenClosed = false
        self.window = window

        let (rest, _) = goal(NSEvent.mouseLocation, at: -1)
        hand = rest; handVelocity = .zero; angle = .pi / 2; spin = 0
        rebuildLash()
        window.orderFrontRegardless()

        let down: (NSEvent) -> Void = { [weak self] event in MainActor.assumeIsolated { self?.crack(event.modifierFlags) } }
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: down) as Any,
                    NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { down($0); return $0 } as Any]
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stop() {
        timer?.invalidate()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        window?.orderOut(nil)
        window = nil
    }

    func crack(_ modifiers: NSEvent.ModifierFlags) {
        crackStart = Date()
        crackSparked = false
        let key = WhipPrefs.macroKey
        macroArmed = key == .none || CGEventFlags(rawValue: UInt64(modifiers.rawValue)).contains(key.flag)
        if inTargetApp { say() }
    }

    private func say() { phrase = (Self.phrases.randomElement()!, Date()) }

    private func handleTop() -> CGPoint {
        CGPoint(x: hand.x + cos(angle) * handleLength, y: hand.y + sin(angle) * handleLength)
    }

    /// Where the hand and the handle angle want to be: held upright beside the pointer; on a crack, the wrist
    /// winds back, sweeps forward and returns.
    private func goal(_ mouse: CGPoint, at t: TimeInterval) -> (hand: CGPoint, angle: CGFloat) {
        func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f * f * (3 - 2 * f) }
        let rest = (x: 30.0, y: 6.0, a: Double.pi / 2), back = (x: 58.0, y: 40.0, a: 0.55), fore = (x: -62.0, y: -10.0, a: 2.7)
        let v: (x: Double, y: Double, a: Double)
        switch t {
        case ..<0: v = rest
        case ..<0.14: let f = t / 0.14; v = (lerp(rest.x, back.x, f), lerp(rest.y, back.y, f), lerp(rest.a, back.a, f))
        case ..<0.22: let f = (t - 0.14) / 0.08; v = (lerp(back.x, fore.x, f), lerp(back.y, fore.y, f), lerp(back.a, fore.a, f))
        case ..<0.5: let f = (t - 0.22) / 0.28; v = (lerp(fore.x, rest.x, f), lerp(fore.y, rest.y, f), lerp(fore.a, rest.a, f))
        default: v = rest
        }
        return (CGPoint(x: mouse.x + v.x, y: mouse.y + v.y), CGFloat(v.a))
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let t = Date().timeIntervalSince(crackStart)
        window?.setFrameOrigin(NSPoint(x: mouse.x - Self.size.width / 2, y: mouse.y - Self.size.height / 2))

        let substeps = 2, dt: CGFloat = 1.0 / 60 / CGFloat(substeps)
        let goal = goal(mouse, at: t)
        for _ in 0..<substeps {
            clock += dt
            step(dt: dt, goal: goal, cracking: t < 0.5)
        }
        if !crackSparked {
            let last = pos.count - 1
            let tip = hypot(pos[last].x - prev[last].x, pos[last].y - prev[last].y) / dt
            if (t > 0.12 && tip > 2800) || t > 0.32 {   // the loop reached the tip: that is the snap
                crackSparked = true
                spark = Date()
                NSSound(named: "Pop")?.play()
                if macroArmed, Date().timeIntervalSince(lastSnap) > 0.6 { lastSnap = Date(); onSnap?() }
            }
        }
        points = ([hand, handleTop()] + pos.dropFirst()).map { CGPoint(x: $0.x - mouse.x, y: $0.y - mouse.y) }
        if inTargetApp, Date().timeIntervalSince(lastSay) > 5 { lastSay = Date(); say() }
    }

    private func step(dt: CGFloat, goal: (hand: CGPoint, angle: CGFloat), cracking: Bool) {
        // Handle: the hand follows the pointer on a spring; the handle angle is held by a stiff spring, so it stays
        // upright and only leans a little with the motion.
        let k: CGFloat = cracking ? 4200 : 1100, c: CGFloat = cracking ? 95 : 52
        handVelocity.x += (k * (goal.hand.x - hand.x) - c * handVelocity.x) * dt
        handVelocity.y += (k * (goal.hand.y - hand.y) - c * handVelocity.y) * dt
        hand.x += handVelocity.x * dt; hand.y += handVelocity.y * dt
        let lean = cracking ? 0 : max(-0.3, min(0.3, handVelocity.x * 0.0004))
        let ka: CGFloat = cracking ? 2600 : 1400, ca: CGFloat = cracking ? 55 : 60
        spin += (ka * (goal.angle + lean - angle) - ca * spin) * dt
        angle += spin * dt

        // Lash: Verlet from the handle top, with gravity, a gentle sway and a bit of stiffness near the root.
        let n = pos.count
        let root = handleTop()
        var velocity = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n { velocity[i] = CGPoint(x: (pos[i].x - prev[i].x) * 0.994, y: (pos[i].y - prev[i].y) * 0.994) }
        for i in 0..<n {
            prev[i] = pos[i]
            if i == 0 { pos[0] = root; prev[0] = root; continue }
            let depth = CGFloat(i) / CGFloat(n)
            let ax = 260 * depth * sin(clock * 2.3 + CGFloat(i) * 0.45)
            let ay = -style.gravity + 140 * depth * cos(clock * 1.7 + CGFloat(i) * 0.6)
            var step = CGPoint(x: velocity[i].x + ax * dt * dt, y: velocity[i].y + ay * dt * dt)
            let length = hypot(step.x, step.y)
            if length > 45 { step = CGPoint(x: step.x / length * 45, y: step.y / length * 45) }   // survives a mouse teleport
            pos[i] = CGPoint(x: pos[i].x + step.x, y: pos[i].y + step.y)
        }
        func invMass(_ i: Int) -> CGFloat { i == 0 ? 0 : 0.9 + 2.6 * CGFloat(i) / CGFloat(n) }
        for _ in 0..<10 {
            for i in 1..<n {
                let dx = pos[i].x - pos[i - 1].x, dy = pos[i].y - pos[i - 1].y
                let distance = max(hypot(dx, dy), 0.001)
                let share = (distance - lashLength) / distance / (invMass(i) + invMass(i - 1))
                pos[i - 1].x += dx * share * invMass(i - 1); pos[i - 1].y += dy * share * invMass(i - 1)
                pos[i].x -= dx * share * invMass(i); pos[i].y -= dy * share * invMass(i)
            }
        }
        // The first stretch of the lash leaves the handle in line with it, then goes limp.
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        for i in 1..<(n - 1) {
            let stiffness = max(0, style.stiffness.0 - style.stiffness.1 * CGFloat(i))
            guard stiffness > 0 else { break }
            let base = i == 1 ? direction : { () -> CGPoint in
                let dx = pos[i].x - pos[i - 1].x, dy = pos[i].y - pos[i - 1].y, len = max(hypot(dx, dy), 0.001)
                return CGPoint(x: dx / len, y: dy / len)
            }()
            let want = CGPoint(x: pos[i].x + base.x * lashLength, y: pos[i].y + base.y * lashLength)
            if i == 1 {   // pull the first lash point itself onto the handle's line
                pos[1].x += (root.x + direction.x * lashLength - pos[1].x) * stiffness
                pos[1].y += (root.y + direction.y * lashLength - pos[1].y) * stiffness
            }
            pos[i + 1].x += (want.x - pos[i + 1].x) * stiffness
            pos[i + 1].y += (want.y - pos[i + 1].y) * stiffness
        }
    }
}

private struct WhipCanvas: View {
    @ObservedObject var model: WhipOverlay

    var body: some View {
        let now = Date()
        ZStack {
            Canvas { ctx, size in
                guard model.points.count > 3 else { return }
                let pts = model.points.map { CGPoint(x: size.width / 2 + $0.x, y: size.height / 2 - $0.y) }
                WhipArt.draw(&ctx, pts, model: model.style, color: model.color)
                if now.timeIntervalSince(model.spark) < 0.12, let tip = pts.last {   // the "stalo"
                    for i in 0..<8 {
                        let a = Double(i) * .pi / 4
                        var spark = Path()
                        spark.move(to: CGPoint(x: tip.x + cos(a) * 6, y: tip.y + sin(a) * 6))
                        spark.addLine(to: CGPoint(x: tip.x + cos(a) * 20, y: tip.y + sin(a) * 20))
                        ctx.stroke(spark, with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
            }
            if let phrase = model.phrase, now.timeIntervalSince(phrase.time) < 1.4 {
                Text(phrase.text)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.white)).overlay(Capsule().stroke(.black, lineWidth: 2))
                    .foregroundStyle(.black)
                    .offset(x: 100, y: -140)
            }
        }
    }
}
