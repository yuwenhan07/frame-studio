import AppKit

public struct PaletteColor: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let fraction: Double
    public init(red: UInt8, green: UInt8, blue: UInt8, fraction: Double = 0) {
        self.red = red; self.green = green; self.blue = blue; self.fraction = fraction
    }
    public init?(hex: String, fraction: Double = 0) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.utf8.count == 6,
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8((value >> 16) & 255), green: UInt8((value >> 8) & 255),
                  blue: UInt8(value & 255), fraction: fraction)
    }
    public var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }
    public var color: NSColor { NSColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1) }
    public var lightness: Double { 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue) }
}

// Immutable source histogram. Reused for count changes, previews and full-resolution exports.
public struct PhotoPalette: Sendable {
    private struct Sample: Sendable {
        let r: Double, g: Double, b: Double, weight: Double
    }
    private let samples: [Sample]

    public init(image: CGImage) {
        let scale = min(1, 192 / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Match the renderer's white backing for transparent photographs.
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { samples = []; return }
        var histogram: [Int: (r: Double, g: Double, b: Double, n: Double)] = [:]
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
            let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            let old = histogram[key] ?? (0, 0, 0, 0)
            histogram[key] = (old.r + Double(r), old.g + Double(g), old.b + Double(b), old.n + 1)
        }
        samples = histogram.keys.sorted().map { key in
            let item = histogram[key]!
            return Sample(r: item.r / item.n / 255, g: item.g / item.n / 255,
                          b: item.b / item.n / 255, weight: item.n)
        }
    }

    public func colors(count requested: Int, order: PaletteOrder = .lightness) -> [PaletteColor] {
        guard !samples.isEmpty else { return [] }
        let count = min(samples.count, min(8, max(1, requested)))
        func distance(_ a: Sample, _ b: Sample) -> Double {
            let r = a.r - b.r, g = a.g - b.g, blue = a.b - b.b
            return 0.30 * r * r + 0.59 * g * g + 0.11 * blue * blue
        }
        // Stable weighted farthest-point seeding; no random palette changes between exports.
        var centers = [samples.max(by: { $0.weight < $1.weight })!]
        while centers.count < count {
            let next = samples.max { a, b in
                let da = centers.map { distance(a, $0) }.min()! * sqrt(a.weight)
                let db = centers.map { distance(b, $0) }.min()! * sqrt(b.weight)
                return da < db
            }!
            guard centers.allSatisfy({ distance(next, $0) > 0.000001 }) else { break }
            centers.append(next)
        }
        var weights = [Double](repeating: 0, count: centers.count)
        for _ in 0..<18 {
            var sums = [(r: Double, g: Double, b: Double, n: Double)](repeating: (0, 0, 0, 0), count: centers.count)
            for sample in samples {
                let index = centers.indices.min { distance(sample, centers[$0]) < distance(sample, centers[$1]) }!
                sums[index].r += sample.r * sample.weight
                sums[index].g += sample.g * sample.weight
                sums[index].b += sample.b * sample.weight
                sums[index].n += sample.weight
            }
            var movement = 0.0
            for index in centers.indices where sums[index].n > 0 {
                let sum = sums[index]
                let updated = Sample(r: sum.r / sum.n, g: sum.g / sum.n, b: sum.b / sum.n, weight: sum.n)
                movement = max(movement, distance(centers[index], updated))
                centers[index] = updated
            }
            weights = sums.map(\.n)
            if movement < 0.0000001 { break }
        }
        let total = weights.reduce(0, +)
        var colors: [PaletteColor] = []
        for index in centers.indices where weights[index] > 0 {
            let c = centers[index]
            let color = PaletteColor(red: UInt8(min(255, max(0, (c.r * 255).rounded()))),
                green: UInt8(min(255, max(0, (c.g * 255).rounded()))),
                blue: UInt8(min(255, max(0, (c.b * 255).rounded()))), fraction: weights[index] / total)
            if let existing = colors.firstIndex(where: { $0.hex == color.hex }) {
                let previous = colors[existing]
                colors[existing] = PaletteColor(red: color.red, green: color.green, blue: color.blue,
                                               fraction: previous.fraction + color.fraction)
            } else { colors.append(color) }
        }
        return colors.sorted {
            let a = order == .lightness ? $0.lightness : -$0.fraction
            let b = order == .lightness ? $1.lightness : -$1.fraction
            return a == b ? $0.hex < $1.hex : a < b
        }
    }
}
