// TitleSequence.swift
// Manifold — Brand Title Sequence (SwiftUI port of /brand/iter-05-final.html)
//
// Drop-in usage:
//
//   import SwiftUI
//   struct SplashView: View {
//     var body: some View {
//       ManifoldTitleSequence(speed: 2.5)   // compressed splash variant
//         .frame(minWidth: 600, minHeight: 400)
//     }
//   }
//
// Architecture:
//   - SwiftUI Canvas drives the particle field at 60fps via TimelineView
//   - Custom braces are SwiftUI Paths (translated from SVG), stroked with a vertical gradient
//   - State machine: .seed → .reveal → cycle of [bar, files, emails, history]
//   - Text sampling uses CGContext bitmap → pixel scan → point array
//
// macOS 13+ / iOS 16+ (uses SwiftUI Canvas).
// Tested against the Manifold project's macOS-only target.

import SwiftUI
#if canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

// MARK: - Public View

public struct ManifoldTitleSequence: View {
    public enum SlotState: String, Equatable {
        case bar, files, emails, history, tasks
        var text: String? {
            switch self {
            case .bar: return nil
            case .files: return "/files"
            case .emails: return "/emails"
            case .history: return "/history"
            case .tasks: return "/tasks"
            }
        }
    }

    public var speed: Double
    public var cycle: [SlotState]
    public var tagline: String
    public var wordmark: String

    public init(
        speed: Double = 1.0,
        cycle: [SlotState] = [.files, .bar, .emails, .bar, .history, .bar],
        wordmark: String = "MANIFOLD",
        tagline: String = "ACCESS, RECORDED."
    ) {
        self.speed = speed
        self.cycle = cycle
        self.wordmark = wordmark
        self.tagline = tagline
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                BackgroundLayer()
                CompositionLayer(
                    speed: speed,
                    cycle: cycle,
                    wordmark: wordmark,
                    tagline: tagline,
                    size: proxy.size
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - Tokens

private enum Tokens {
    static let bgDeep   = Color(red: 0.020, green: 0.020, blue: 0.027)
    static let bgLift   = Color(red: 0.063, green: 0.063, blue: 0.075)
    static let ink      = Color(red: 0.945, green: 0.925, blue: 0.878)
    static let inkWarm  = Color(red: 1.000, green: 0.851, blue: 0.627)
    static let inkCold  = Color(red: 0.722, green: 0.784, blue: 0.878)
    static let inkSoft  = Color(red: 0.839, green: 0.816, blue: 0.761)
    static let inkMute  = Color(red: 0.416, green: 0.400, blue: 0.369)
    static let gate     = Color(red: 1.000, green: 0.878, blue: 0.698)
}

// MARK: - Background

private struct BackgroundLayer: View {
    var body: some View {
        ZStack {
            Tokens.bgDeep
            RadialGradient(
                colors: [Tokens.gate.opacity(0.05), .clear],
                center: UnitPoint(x: 0.5, y: 0.47),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Tokens.bgLift, Tokens.bgDeep],
                center: UnitPoint(x: 0.5, y: 0.47),
                startRadius: 60,
                endRadius: 600
            )
            .opacity(0.9)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Composition (mark + wordmark + tagline)

private struct CompositionLayer: View {
    let speed: Double
    let cycle: [ManifoldTitleSequence.SlotState]
    let wordmark: String
    let tagline: String
    let size: CGSize

    @State private var startedAt: Date = Date()
    @State private var phase: AnimationPhase = .seed
    @State private var slotState: ManifoldTitleSequence.SlotState = .bar
    @State private var halosVisible: Bool = false
    @State private var seedVisible: Bool = false
    @State private var bracesRevealed: Bool = false
    @State private var wordmarkRevealed: Bool = false
    @State private var taglineRevealed: Bool = false

    enum AnimationPhase { case seed, reveal, cycling }

    var body: some View {
        ZStack {
            // Halos
            HalosLayer(visible: halosVisible)

            // Mark cluster: brace | slot | brace
            HStack(spacing: 92) {
                BraceShape(side: .left)
                    .stroke(braceGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 80, height: 240)
                    .opacity(bracesRevealed ? 1 : 0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.85).delay(1.2 / speed), value: bracesRevealed)

                ParticleSlot(
                    slotState: $slotState,
                    speed: speed
                )
                .frame(width: 360, height: 280)

                BraceShape(side: .right)
                    .stroke(braceGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 80, height: 240)
                    .opacity(bracesRevealed ? 1 : 0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.85).delay(1.5 / speed), value: bracesRevealed)
            }

            // Seed line
            SeedLine()
                .frame(width: 220, height: 1)
                .scaleEffect(x: seedVisible ? 1 : 0, y: 1, anchor: .center)
                .opacity(seedVisible ? 0.9 : 0)
                .animation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 1.0 / speed), value: seedVisible)

            // Wordmark + tagline below the mark
            VStack(spacing: 22) {
                Spacer().frame(height: 320)
                Wordmark(text: wordmark, revealed: wordmarkRevealed, speed: speed)
                Text(tagline)
                    .font(.system(size: 12, weight: .light, design: .default))
                    .tracking(4)
                    .foregroundColor(Tokens.inkMute)
                    .opacity(taglineRevealed ? 0.8 : 0)
                    .animation(.easeOut(duration: 0.9 / speed), value: taglineRevealed)
                Spacer()
            }
        }
        .onAppear { runSequence() }
    }

    private var braceGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 1.0).opacity(0.95),
                Tokens.ink,
                Color(white: 0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func runSequence() {
        let s = speed
        // Seed appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 / s) { seedVisible = true }
        // Seed fades, halos rise, braces iris in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3 / s) {
            withAnimation(.easeIn(duration: 0.7 / s)) { seedVisible = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3 / s) {
            withAnimation(.easeOut(duration: 1.5 / s)) { halosVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / s) {
            bracesRevealed = true
        }
        // Particle field reveals
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4 / s) {
            slotState = .bar  // triggers particle system to scatter→bar
        }
        // Wordmark + tagline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2 / s) { wordmarkRevealed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.4 / s) { taglineRevealed = true }
        // Cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.4 / s) {
            startCycle()
        }
    }

    private func startCycle() {
        var idx = 0
        func step() {
            let state = cycle[idx % cycle.count]
            slotState = state
            let dur = (state == .bar ? 0.85 : 1.10) / speed
            let hold = (state == .bar ? 1.6 : 2.8) / speed
            idx += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.38 + hold) {
                step()
            }
        }
        step()
    }
}

// MARK: - Wordmark

private struct Wordmark: View {
    let text: String
    let revealed: Bool
    let speed: Double

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(text.enumerated()), id: \.offset) { idx, ch in
                Text(String(ch))
                    .font(.system(size: 28, weight: .light, design: .default))
                    .foregroundColor(Tokens.inkSoft)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 10)
                    .animation(
                        .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.7 / speed)
                            .delay(Double(idx) * 0.08 / speed),
                        value: revealed
                    )
            }
        }
    }
}

// MARK: - Halos

private struct HalosLayer: View {
    let visible: Bool

    var body: some View {
        ZStack {
            // Cold halo (back)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Tokens.inkCold.opacity(0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 200
                    )
                )
                .frame(width: 380, height: 420)
                .blur(radius: 32)
                .opacity(visible ? 0.65 : 0)

            // Far warm halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Tokens.gate.opacity(0.16), .clear],
                        center: .center, startRadius: 0, endRadius: 280
                    )
                )
                .frame(width: 540, height: 480)
                .blur(radius: 46)
                .opacity(visible ? 0.6 : 0)

            // Near warm halo
            Capsule()
                .fill(
                    RadialGradient(
                        colors: [Tokens.gate.opacity(0.42), .clear],
                        center: .center, startRadius: 0, endRadius: 160
                    )
                )
                .frame(width: 280, height: 360)
                .blur(radius: 18)
                .opacity(visible ? 0.55 : 0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Seed line

private struct SeedLine: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, Tokens.ink.opacity(0.6), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Brace shape (single-stroke path)

private struct BraceShape: Shape {
    enum Side { case left, right }
    let side: Side

    func path(in rect: CGRect) -> Path {
        let s = CGSize(width: 80, height: 240)
        let sx = rect.width / s.width
        let sy = rect.height / s.height

        // Mirror for right side
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let xx = side == .left ? x : (s.width - x)
            return CGPoint(x: xx * sx, y: y * sy)
        }

        var path = Path()
        path.move(to: p(64, 8))
        path.addCurve(to: p(26, 40), control1: p(36, 8), control2: p(26, 18))
        path.addLine(to: p(26, 100))
        path.addCurve(to: p(6, 120), control1: p(26, 110), control2: p(18, 116))
        path.addCurve(to: p(26, 140), control1: p(18, 124), control2: p(26, 130))
        path.addLine(to: p(26, 200))
        path.addCurve(to: p(64, 232), control1: p(26, 222), control2: p(36, 232))
        return path
    }
}

// MARK: - Particle slot

private struct ParticleSlot: View {
    @Binding var slotState: ManifoldTitleSequence.SlotState
    let speed: Double

    @State private var system = ParticleSystem(atomCount: 120)
    @State private var lastState: ManifoldTitleSequence.SlotState = .bar
    @State private var lastTransition: Date = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                system.update(now: now)
                system.draw(into: context, size: size)
            }
        }
        .onChange(of: slotState) { _, newState in
            morph(to: newState)
        }
        .onAppear {
            // After brief delay, scatter atoms into the bar
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4 / speed) {
                system.beginInitialReveal(speed: speed)
            }
        }
    }

    private func morph(to state: ManifoldTitleSequence.SlotState) {
        let dur = (state == .bar ? 0.85 : 1.10) / speed
        switch state {
        case .bar:
            system.morphTo(targets: ParticleSystem.barTargets(count: system.atomCount), duration: dur)
        default:
            if let text = state.text {
                let targets = ParticleSystem.textTargets(text: text, count: system.atomCount)
                system.morphTo(targets: targets, duration: dur)
            }
        }
        lastState = state
        lastTransition = Date()
    }
}

// MARK: - Particle System

private final class ParticleSystem {
    struct Atom {
        var x: CGFloat = 0, y: CGFloat = 0
        var sx: CGFloat = 0, sy: CGFloat = 0
        var tx: CGFloat = 0, ty: CGFloat = 0
        var cpx: CGFloat = 0, cpy: CGFloat = 0
        var size: CGFloat = 1.5
        var color: Color = Tokens.ink
        var delay: Double = 0
        var duration: Double = 0.9
        var tStart: TimeInterval = 0
        var inFlight: Bool = false
        var shimmerPhase: Double = 0
    }

    let atomCount: Int
    var atoms: [Atom]

    init(atomCount: Int) {
        self.atomCount = atomCount
        var initial: [Atom] = []
        for i in 0..<atomCount {
            var a = Atom()
            a.x = CGFloat.random(in: -350...350)
            a.y = CGFloat.random(in: -250...250)
            a.shimmerPhase = .random(in: 0...(2 * .pi))
            // Variable size based on spine position
            let t = (Double(i) / Double(atomCount - 1) - 0.5) * 2
            a.size = 1.55 - abs(CGFloat(t)) * 0.4
            // Color variation
            let r = Double.random(in: 0...1)
            if r < 0.92 { a.color = Tokens.ink }
            else if r < 0.99 { a.color = Tokens.inkWarm }
            else { a.color = Tokens.inkCold }
            initial.append(a)
        }
        self.atoms = initial
    }

    func beginInitialReveal(speed: Double) {
        let targets = ParticleSystem.barTargets(count: atomCount)
        morphTo(targets: targets, duration: 1.5 / speed, maxStagger: 0.7 / speed)
    }

    func morphTo(targets: [CGPoint], duration: Double, maxStagger: Double = 0.26) {
        guard targets.count == atomCount else { return }
        // Greedy nearest-neighbor assignment
        var used = [Bool](repeating: false, count: targets.count)
        let order = atoms.indices.sorted { atoms[$0].y < atoms[$1].y }
        var assignment = [Int](repeating: -1, count: atomCount)
        for ai in order {
            var best = -1
            var bestD: CGFloat = .infinity
            for ti in targets.indices {
                if used[ti] { continue }
                let dx = atoms[ai].x - targets[ti].x
                let dy = atoms[ai].y - targets[ti].y
                let d = dx*dx + dy*dy
                if d < bestD { bestD = d; best = ti }
            }
            if best >= 0 { assignment[ai] = best; used[best] = true }
        }
        let now = Date().timeIntervalSinceReferenceDate
        for i in atoms.indices {
            let target = targets[assignment[i]]
            atoms[i].sx = atoms[i].x
            atoms[i].sy = atoms[i].y
            atoms[i].tx = target.x
            atoms[i].ty = target.y
            // Perpendicular bezier control
            let dx = atoms[i].tx - atoms[i].sx
            let dy = atoms[i].ty - atoms[i].sy
            let len = sqrt(dx*dx + dy*dy)
            let px = -dy / max(len, 1)
            let py = dx / max(len, 1)
            let curve = CGFloat.random(in: -1...1) * min(60, len * 0.35)
            atoms[i].cpx = (atoms[i].sx + atoms[i].tx) / 2 + px * curve
            atoms[i].cpy = (atoms[i].sy + atoms[i].ty) / 2 + py * curve
            atoms[i].delay = (Double(i) / Double(atomCount)) * maxStagger + .random(in: 0...0.08)
            atoms[i].duration = duration
            atoms[i].tStart = now + atoms[i].delay
            atoms[i].inFlight = true
        }
    }

    func update(now: TimeInterval) {
        for i in atoms.indices {
            update(&atoms[i], now: now)
        }
    }

    private func update(_ a: inout Atom, now: TimeInterval) {
        let elapsed = now - a.tStart
        if elapsed < 0 { return }
        if !a.inFlight {
            // At rest — position stays; shimmer applied at draw time only.
            return
        }
        let t = min(1, elapsed / a.duration)
        if t >= 1 {
            a.inFlight = false
            a.x = a.tx; a.y = a.ty
            return
        }
        let e = easeInOutCubic(t)
        let u = 1 - e
        a.x = u*u*a.sx + 2*u*e*a.cpx + e*e*a.tx
        a.y = u*u*a.sy + 2*u*e*a.cpy + e*e*a.ty
    }

    func draw(into context: GraphicsContext, size: CGSize) {
        let cx = size.width / 2, cy = size.height / 2
        let now = Date().timeIntervalSinceReferenceDate
        for a in atoms {
            // Brownian shimmer at draw time (does not accumulate into stored position)
            let sx: CGFloat = a.inFlight ? 0 : CGFloat(sin((now + a.shimmerPhase) * 1.7) * 0.35)
            let sy: CGFloat = a.inFlight ? 0 : CGFloat(cos((now + a.shimmerPhase) * 2.1) * 0.35)
            let x = cx + a.x + sx
            let y = cy + a.y + sy
            // Brightness peaks at t=0.5 of in-flight, otherwise 1.0 at rest
            let bright: Double = {
                if a.inFlight {
                    let elapsed = now - a.tStart
                    let t = max(0, min(1, elapsed / a.duration))
                    return max(0, 1 - abs(t - 0.5) * 2)
                } else {
                    return 1
                }
            }()
            let r = a.size + 0.7 * bright
            let opacity = 0.55 + 0.45 * bright
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            // Bloom layer (larger soft glow drawn first)
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: -r * 0.8, dy: -r * 0.8)),
                with: .color(Tokens.inkWarm.opacity(opacity * 0.35))
            )
            // Core atom
            context.fill(Path(ellipseIn: rect), with: .color(a.color.opacity(opacity)))
        }
    }

    private func easeInOutCubic(_ t: Double) -> Double {
        return t < 0.5 ? 4*t*t*t : 1 - pow(-2*t + 2, 3) / 2
    }

    static func barTargets(count: Int) -> [CGPoint] {
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1) - 0.5
            return CGPoint(x: 0, y: CGFloat(t * 200))
        }
    }

    static func textTargets(text: String, count: Int, fontSize: CGFloat = 84) -> [CGPoint] {
        let W = 360, H = 200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: W * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return barTargets(count: count) }

        let font = PlatformFont.systemFont(ofSize: fontSize, weight: .light)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PlatformColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let stringSize = attrString.size()

        #if canImport(AppKit)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attrString.draw(at: CGPoint(
            x: (CGFloat(W) - stringSize.width) / 2,
            y: (CGFloat(H) - stringSize.height) / 2
        ))
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(ctx)
        attrString.draw(at: CGPoint(
            x: (CGFloat(W) - stringSize.width) / 2,
            y: (CGFloat(H) - stringSize.height) / 2
        ))
        UIGraphicsPopContext()
        #endif

        guard let data = ctx.data else { return barTargets(count: count) }
        let buffer = data.bindMemory(to: UInt8.self, capacity: W * H * 4)

        var samples: [CGPoint] = []
        var y = 0
        while y < H {
            var x = 0
            while x < W {
                let i = (y * W + x) * 4
                if buffer[i + 3] > 100 {
                    samples.append(CGPoint(x: CGFloat(x - W/2), y: CGFloat(y - H/2)))
                }
                x += 2
            }
            y += 2
        }
        guard !samples.isEmpty else { return barTargets(count: count) }
        var out: [CGPoint] = []
        for i in 0..<count {
            out.append(samples[(i * samples.count) / count])
        }
        out.shuffle()
        return out
    }
}

// MARK: - Preview

#if DEBUG
struct ManifoldTitleSequence_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ManifoldTitleSequence()
                .frame(width: 900, height: 560)
                .previewDisplayName("Cinematic")
            ManifoldTitleSequence(speed: 2.5)
                .frame(width: 900, height: 560)
                .previewDisplayName("Splash")
        }
    }
}
#endif
