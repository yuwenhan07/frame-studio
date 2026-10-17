// Original, deterministic artwork for the public demo. No photograph or EXIF is used.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.dropFirst().first ?? "Assets/Sample.jpg"
let width = 2400, height = 1600
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func polygon(_ points: [CGPoint], _ fill: CGColor) {
    let path = CGMutablePath()
    path.addLines(between: points); path.closeSubpath()
    context.addPath(path); context.setFillColor(fill); context.fillPath()
}
func gradient(_ rect: CGRect, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    context.saveGState(); context.clip(to: rect)
    let value = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(value, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}
gradient(CGRect(x: 0, y: 0, width: width, height: height),
         [color(0.91, 0.69, 0.60), color(0.71, 0.57, 0.62), color(0.32, 0.44, 0.56)],
         from: CGPoint(x: 0, y: 650), to: CGPoint(x: 0, y: 1600))
context.setFillColor(color(1, 0.85, 0.65))
context.fillEllipse(in: CGRect(x: 1660, y: 1070, width: 180, height: 180))
polygon([CGPoint(x: 0, y: 650), CGPoint(x: 0, y: 900), CGPoint(x: 330, y: 1080),
         CGPoint(x: 650, y: 970), CGPoint(x: 1030, y: 1320), CGPoint(x: 1430, y: 980),
         CGPoint(x: 1710, y: 1090), CGPoint(x: 2040, y: 870), CGPoint(x: 2400, y: 1000),
         CGPoint(x: 2400, y: 650)], color(0.40, 0.45, 0.51))
polygon([CGPoint(x: 1030, y: 1320), CGPoint(x: 760, y: 1070), CGPoint(x: 930, y: 1120),
         CGPoint(x: 1000, y: 1090), CGPoint(x: 1090, y: 1160), CGPoint(x: 1200, y: 1120)], color(0.92, 0.81, 0.77))
polygon([CGPoint(x: 1030, y: 1320), CGPoint(x: 1110, y: 1050), CGPoint(x: 1430, y: 980)], color(0.32, 0.39, 0.47))
polygon([CGPoint(x: 0, y: 630), CGPoint(x: 0, y: 760), CGPoint(x: 450, y: 970),
         CGPoint(x: 770, y: 780), CGPoint(x: 1230, y: 900), CGPoint(x: 1670, y: 720),
         CGPoint(x: 2050, y: 950), CGPoint(x: 2400, y: 780), CGPoint(x: 2400, y: 630)], color(0.25, 0.36, 0.41))
gradient(CGRect(x: 0, y: 0, width: width, height: 660),
         [color(0.18, 0.32, 0.37), color(0.49, 0.55, 0.55), color(0.77, 0.65, 0.59)],
         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 660))
for index in 0..<120 {
    let y = CGFloat((index * 137 + 31) % 640)
    let x = CGFloat((index * 317 + 83) % 2400)
    let length = CGFloat(30 + (index * 47) % 240)
    context.setStrokeColor(color(0.91, 0.77, 0.65, 0.06 + CGFloat(index % 4) * 0.025))
    context.setLineWidth(1.5 + (660 - y) / 250)
    context.move(to: CGPoint(x: x, y: y)); context.addLine(to: CGPoint(x: x + length, y: y))
    context.strokePath()
}
polygon([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 340), CGPoint(x: 430, y: 220),
         CGPoint(x: 770, y: 130), CGPoint(x: 1250, y: 0)], color(0.12, 0.23, 0.26))
for index in 0..<23 {
    let x = CGFloat(index * 34 - 50), base = CGFloat(255 - index * 6)
    let treeHeight = CGFloat(100 + (index * 29) % 140)
    context.setFillColor(color(0.10, 0.20, 0.23))
    context.fill(CGRect(x: x - 3, y: base, width: 6, height: treeHeight))
    for tier in 0..<4 {
        let y = base + CGFloat(tier) * treeHeight * 0.19
        let half = treeHeight * (0.24 - CGFloat(tier) * 0.035)
        polygon([CGPoint(x: x - half, y: y), CGPoint(x: x, y: y + treeHeight * 0.48),
                 CGPoint(x: x + half, y: y)], color(0.10, 0.20, 0.23))
    }
}
let image = context.makeImage()!
let data = NSMutableData()
let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image,
    [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot encode demo artwork") }
try (data as Data).write(to: URL(fileURLWithPath: output), options: .atomic)
print("Generated \(output) (\(width) × \(height), original procedural artwork)")
