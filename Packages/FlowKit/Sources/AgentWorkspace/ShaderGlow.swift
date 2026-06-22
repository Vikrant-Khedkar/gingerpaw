import SwiftUI

/// A SwiftUI approximation of the ShaderGradient plane (color1/2/3 = #00100f / #db7e14 /
/// #d0bce1): a slow flowing plasma — rotating angular base + two drifting radial blobs +
/// a faint grain. Native equivalent of the React/WebGL component (which can't run here).
struct ShaderGlow: View {
    var speed: Double = 0.4

    private let c1 = Color(hex: 0x00100f)   // near-black teal
    private let c2 = Color(hex: 0xdb7e14)   // ginger
    private let c3 = Color(hex: 0xd0bce1)   // lavender

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate * speed
            ZStack {
                AngularGradient(gradient: Gradient(colors: [c1, c2, c3, c2, c1]),
                                center: .center,
                                angle: .degrees((t * 60).truncatingRemainder(dividingBy: 360)))
                RadialGradient(gradient: Gradient(colors: [c2.opacity(0.95), .clear]),
                               center: UnitPoint(x: 0.5 + 0.32 * cos(t * 0.9), y: 0.5 + 0.32 * sin(t * 1.3)),
                               startRadius: 0, endRadius: 24)
                RadialGradient(gradient: Gradient(colors: [c3.opacity(0.8), .clear]),
                               center: UnitPoint(x: 0.5 + 0.30 * cos(t * 1.4 + 2), y: 0.5 + 0.30 * sin(t * 0.7 + 1)),
                               startRadius: 0, endRadius: 20)
            }
            .blur(radius: 5)
        }
        .overlay(grain.opacity(0.06).blendMode(.overlay))
        .drawingGroup()
    }

    private var grain: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9e3779b9
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 40) / Double(1 << 24) }
            for _ in 0..<260 {
                let x = rnd() * size.width, y = rnd() * size.height
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)),
                         with: .color(.white.opacity(rnd())))
            }
        }
    }
}
