import Foundation
import CoreGraphics

public enum PostageVariant: String, CaseIterable, Codable, Identifiable, Sendable {
    case plain = "纯画框", caption = "底部落款"
    public var id: String { rawValue }
}

public enum PostageDateMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case captureDate = "拍摄日期", custom = "自定义日期", none = "不显示"
    public var id: String { rawValue }
    public func text(metadata: PhotoMetadata, custom: String) -> String {
        if self == .custom { return custom.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard self == .captureDate, let raw = metadata.captureDateTime else { return "" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.isLenient = false
        guard let date = parser.date(from: raw) else { return "" }
        parser.dateFormat = "yyyy/MM/dd"
        return parser.string(from: date)
    }
}

public struct PostageLayout {
    public let width: Int
    public let height: Int
    public let cardRect: CGRect
    public let photoRect: CGRect
    public let captionRect: CGRect
    public let notchRadius: CGFloat

    public static func margin(_ style: FrameStyle) -> Double { min(0.19, max(0.035, style.postageMargin)) }
    public static func border(_ style: FrameStyle) -> Double { min(0.06, max(0.014, style.postageBorder)) }

    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: FrameStyle) {
        let w = CGFloat(max(64, outputWidth))
        let margin = w * Self.margin(style), border = w * Self.border(style)
        let footer = style.postageVariant == .caption ? w * min(0.18, max(0.07, style.postageFooter)) : 0
        let photoW = w - 2 * (margin + border)
        let photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
        let cardH = photoH + border * 2 + footer
        width = Int(w); height = Int(ceil(cardH + margin * 2))
        cardRect = CGRect(x: margin, y: margin, width: w - margin * 2, height: cardH)
        photoRect = CGRect(x: margin + border, y: margin + border + footer, width: photoW, height: photoH)
        captionRect = CGRect(x: photoRect.minX, y: margin + border, width: photoW, height: footer)
        notchRadius = min(w * min(0.022, max(0.006, style.postagePerforation)), border * 0.65, min(cardRect.width, cardH) * 0.08)
    }

    /// One continuous outline, so the shadow follows the paper and each open notch.
    public var outline: CGPath {
        let path = CGMutablePath()
        let rect = cardRect, r = notchRadius, corner = r * 1.6
        func centers(_ length: CGFloat) -> [CGFloat] {
            let available = length - corner * 2
            let count = max(1, Int(floor(available / (r * 4.1))))
            return (1...count).map { corner + available * CGFloat($0) / CGFloat(count + 1) }
        }
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        for x in centers(rect.width) {
            path.addLine(to: CGPoint(x: rect.minX + x - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + x, y: rect.minY), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX, y: rect.minY), radius: corner, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        for y in centers(rect.height) {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y - r))
            path.addArc(center: CGPoint(x: rect.maxX, y: rect.minY + y), radius: r, startAngle: -.pi / 2, endAngle: -.pi * 1.5, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: corner, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
        for x in centers(rect.width).reversed() {
            path.addLine(to: CGPoint(x: rect.minX + x + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + x, y: rect.maxY), radius: r, startAngle: 0, endAngle: -.pi, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX, y: rect.maxY), radius: corner, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        for y in centers(rect.height).reversed() {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + y + r))
            path.addArc(center: CGPoint(x: rect.minX, y: rect.minY + y), radius: r, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addArc(center: CGPoint(x: rect.minX, y: rect.minY), radius: corner, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        path.closeSubpath()
        return path
    }
}
