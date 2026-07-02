import SwiftUI

/// The 5 selectable animated backgrounds.
public enum BackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case aurora, bokeh, starfield, waves, pulse
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Dispatches to the selected animated background.
public struct ChatBackground: View {
    public let style: BackgroundStyle
    public init(style: BackgroundStyle) { self.style = style }

    public var body: some View {
        switch style {
        case .aurora: AuroraBackground()
        case .bokeh: BokehBackground()
        case .starfield: StarfieldBackground()
        case .waves: WavesBackground()
        case .pulse: PulseBackground()
        }
    }
}

// 1. Aurora — TimelineView + Canvas flowing gradient blobs.
struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let colors: [Color] = [.purple, .blue, .teal, .pink]
                for i in 0..<4 {
                    let phase = t * 0.3 + Double(i)
                    let x = size.width * (0.5 + 0.35 * cos(phase))
                    let y = size.height * (0.5 + 0.35 * sin(phase * 1.3))
                    let r = size.width * 0.4
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [colors[i].opacity(0.35), .clear]),
                            center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r
                        )
                    )
                }
            }
            .blur(radius: 40)
        }
        .background(Color.black.opacity(0.02))
        .ignoresSafeArea()
    }
}

// 2. Bokeh — Canvas drifting translucent circles.
struct BokehBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<18 {
                    let seed = Double(i)
                    let x = size.width * (0.5 + 0.45 * sin(t * 0.1 + seed))
                    let y = (size.height * 1.2) * ((seed / 18) + 0.1 * sin(t * 0.05 + seed)).truncatingRemainder(dividingBy: 1)
                    let r = 10 + 30 * (seed.truncatingRemainder(dividingBy: 3))
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(Color.mint.opacity(0.12))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// 3. Starfield — TimelineView parallax dots.
struct StarfieldBackground: View {
    private let stars: [(CGFloat, CGFloat, CGFloat)] = (0..<80).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0.5...2))
    }
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for star in stars {
                    let drift = CGFloat((t * 0.02 * Double(star.2)).truncatingRemainder(dividingBy: 1))
                    let y = (star.1 + drift).truncatingRemainder(dividingBy: 1) * size.height
                    let x = star.0 * size.width
                    let r = star.2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(.white.opacity(0.7))
                    )
                }
            }
        }
        .background(Color.black.opacity(0.9))
        .ignoresSafeArea()
    }
}

// 4. Waves — Canvas layered sine waves.
struct WavesBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for layer in 0..<3 {
                    var path = Path()
                    let amp = 20.0 + Double(layer) * 12
                    let yBase = size.height * (0.4 + Double(layer) * 0.15)
                    path.move(to: CGPoint(x: 0, y: yBase))
                    for x in stride(from: 0.0, through: Double(size.width), by: 6) {
                        let y = yBase + amp * sin(x / 60 + t + Double(layer))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(Color.blue.opacity(0.12 + Double(layer) * 0.05)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

// 5. Pulse — PhaseAnimator breathing radial gradient.
struct PulseBackground: View {
    var body: some View {
        PhaseAnimator([0.0, 1.0]) { phase in
            RadialGradient(
                colors: [Color.indigo.opacity(0.35), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 300 + CGFloat(phase) * 200
            )
            .ignoresSafeArea()
        } animation: { _ in
            .easeInOut(duration: 3).repeatForever(autoreverses: true)
        }
    }
}
