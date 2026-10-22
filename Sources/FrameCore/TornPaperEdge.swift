import AppKit

/// Stable procedural geometry: irregular tears at two scales, with occasional deeper notches.
/// The seed describes the paper, so moving sliders or exporting never produces a different tear.
public enum TornPaperEdge {
    private struct Random {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 32) / CGFloat(UInt32.max)
        }
    }

    public static func points(rect: CGRect, depth: CGFloat, step: CGFloat, seed: UInt64 = 7319) -> [CGPoint] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        let depth = max(0, min(depth, min(rect.width, rect.height) * 0.08))
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        let normals = [CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)]
        var random = Random(state: seed), result: [CGPoint] = []
        for edge in 0..<4 {
            let a = corners[edge], b = corners[(edge + 1) % 4], normal = normals[edge]
            let length = hypot(b.x - a.x, b.y - a.y)
            let count = max(12, min(4096, Int(ceil(length / max(0.1, step)))))
            var anchors: [(position: CGFloat, inset: CGFloat)] = [(0, depth * (0.12 + random.next() * 0.15))]
            var position: CGFloat = 0
            while position < 1 {
                position = min(1, position + (3 + random.next() * 9) / CGFloat(count))
                let notch = random.next() < 0.14
                let inset = depth * (notch ? 0.78 + random.next() * 0.22 : 0.04 + random.next() * 0.43)
                anchors.append((position, inset))
            }
            var segment = 0
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count)
                while segment + 1 < anchors.count - 1 && anchors[segment + 1].position < t { segment += 1 }
                let lo = anchors[segment], hi = anchors[segment + 1]
                let fraction = (t - lo.position) / max(0.000001, hi.position - lo.position)
                let broad = lo.inset + (hi.inset - lo.inset) * fraction
                let fine = (random.next() - 0.5) * depth * 0.24
                let inset = min(depth, max(0, broad + fine))
                result.append(CGPoint(x: a.x + (b.x - a.x) * t + normal.dx * inset,
                                      y: a.y + (b.y - a.y) * t + normal.dy * inset))
            }
        }
        return result
    }

    public static func path(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first); for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath(); return path
    }

    static func fibers(in context: CGContext, points: [CGPoint], width: CGFloat, seed: UInt64) {
        guard points.count > 2 else { return }
        var random = Random(state: seed)
        context.saveGState(); context.setLineCap(.round); context.setLineJoin(.round)
        // A broken, thin white core with short strands is more natural than a uniform outline.
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            let dx = b.x - a.x, dy = b.y - a.y, length = max(0.0001, hypot(dx, dy))
            if random.next() < 0.78 {
                context.setStrokeColor(NSColor(srgbRed: 1, green: 0.995, blue: 0.975, alpha: 0.38 + random.next() * 0.50).cgColor)
                context.setLineWidth(width * (0.00055 + random.next() * 0.0010))
                context.move(to: a); context.addLine(to: b); context.strokePath()
            }
            if random.next() < 0.40 {
                let span = width * (0.0005 + random.next() * 0.0019)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.22 + random.next() * 0.45).cgColor)
                context.setLineWidth(width * (0.00025 + random.next() * 0.0004))
                context.move(to: a)
                context.addLine(to: CGPoint(x: a.x + dy / length * span - dx / length * span * 0.25,
                                           y: a.y - dx / length * span - dy / length * span * 0.25))
                context.strokePath()
            }
        }
        context.restoreGState()
    }
}
