import SwiftUI

/// Apple-Messages-style speech bubble with a custom `Path`-drawn curved tail.
public struct MessageBubbleShape: Shape {
    public var isOutbound: Bool
    public var radius: CGFloat

    public init(isOutbound: Bool, radius: CGFloat = 18) {
        self.isOutbound = isOutbound
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        let tail: CGFloat = 8

        // Inset so the tail has room on the tail-side edge.
        let bubble = CGRect(
            x: rect.minX + (isOutbound ? 0 : tail),
            y: rect.minY,
            width: rect.width - tail,
            height: rect.height
        )

        // Rounded rectangle body.
        path.addRoundedRect(
            in: bubble,
            cornerSize: CGSize(width: r, height: r),
            style: .continuous
        )

        // Curved tail near the bottom, drawn as quad curves.
        var tailPath = Path()
        if isOutbound {
            let baseX = bubble.maxX
            let baseY = bubble.maxY - r
            tailPath.move(to: CGPoint(x: baseX - 2, y: baseY))
            tailPath.addQuadCurve(
                to: CGPoint(x: baseX + tail, y: bubble.maxY),
                control: CGPoint(x: baseX + tail, y: baseY + r * 0.5)
            )
            tailPath.addQuadCurve(
                to: CGPoint(x: baseX - r * 0.6, y: bubble.maxY),
                control: CGPoint(x: baseX, y: bubble.maxY)
            )
        } else {
            let baseX = bubble.minX
            let baseY = bubble.maxY - r
            tailPath.move(to: CGPoint(x: baseX + 2, y: baseY))
            tailPath.addQuadCurve(
                to: CGPoint(x: baseX - tail, y: bubble.maxY),
                control: CGPoint(x: baseX - tail, y: baseY + r * 0.5)
            )
            tailPath.addQuadCurve(
                to: CGPoint(x: baseX + r * 0.6, y: bubble.maxY),
                control: CGPoint(x: baseX, y: bubble.maxY)
            )
        }
        path.addPath(tailPath)
        return path
    }
}
