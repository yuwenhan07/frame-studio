import Foundation
import CoreGraphics
import CoreImage

public enum TicketMark: String, CaseIterable, Codable, Identifiable, Sendable {
    case stamp = "旅行邮戳", barcode = "条形码", none = "不显示"
    public var id: String { rawValue }
}

public enum TicketDateMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case captureDate = "拍摄日期", custom = "自定义日期", none = "不显示"
    public var id: String { rawValue }
    public func text(metadata: PhotoMetadata, custom: String) -> String {
        if self == .custom { return custom.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard self == .captureDate, let raw = metadata.captureDateTime else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = formatter.date(from: raw) else { return "" }
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date).uppercased()
    }
}

public enum TicketBarcode {
    public static func content(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func isValid(_ value: String) -> Bool {
        let text = content(value)
        return !text.isEmpty && text.utf8.count <= 48 && text.utf8.allSatisfy { (32...126).contains($0) }
    }
    private static let context = CIContext(options: [.cacheIntermediates: false])
    public static func image(_ value: String) -> CGImage? {
        guard isValid(value), let data = content(value).data(using: .ascii),
              let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(10, forKey: "inputQuietSpace")
        guard let image = filter.outputImage else { return nil }
        return context.createCGImage(image, from: image.extent)
    }
}

public struct TicketLayout {
    public let width: Int, height: Int
    public let cardRect: CGRect, photoRect: CGRect, captionRect: CGRect
    public let separatorY: CGFloat, perforation: CGFloat, sideNotch: CGFloat
    public static func margin(_ style: FrameStyle) -> Double { min(0.24, max(0.08, style.ticketMargin)) }
    public static func border(_ style: FrameStyle) -> Double { min(0.05, max(0.018, style.ticketBorder)) }

    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: FrameStyle) {
        let w = CGFloat(max(64, outputWidth)), margin = w * Self.margin(style)
        let vertical = margin * 0.7, border = w * Self.border(style)
        let footer = w * min(0.30, max(0.13, style.ticketFooter))
        let photoW = w - 2 * (margin + border)
        let photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
        width = Int(w); height = Int(ceil(photoH + border * 2 + footer + vertical * 2))
        cardRect = CGRect(x: margin, y: vertical, width: w - margin * 2, height: photoH + border * 2 + footer)
        photoRect = CGRect(x: margin + border, y: vertical + border + footer, width: photoW, height: photoH)
        separatorY = photoRect.minY - border * 0.5
        captionRect = CGRect(x: photoRect.minX, y: vertical + border * 0.48, width: photoW,
            height: separatorY - border * 0.7 - (vertical + border * 0.48))
        perforation = min(w * min(0.012, max(0.004, style.ticketPerforation)), border * 0.48)
        sideNotch = min(w * 0.014, border * 0.80)
    }

    /// Fine perforation on the short edges; straight sides with a tear-off notch.
    public var outline: CGPath {
        let rect = cardRect, r = perforation, notch = sideNotch
        let count = min(127, max(3, Int(floor(rect.width / (r * 4.4))) | 1))
        let centers = (1...count).map { rect.width * CGFloat($0) / CGFloat(count + 1) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for x in centers {
            path.addLine(to: CGPoint(x: rect.minX + x - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + x, y: rect.minY), radius: r,
                        startAngle: .pi, endAngle: 0, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: separatorY - notch))
        path.addArc(center: CGPoint(x: rect.maxX, y: separatorY), radius: notch,
                    startAngle: -.pi / 2, endAngle: -.pi * 1.5, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        for x in centers.reversed() {
            path.addLine(to: CGPoint(x: rect.minX + x + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + x, y: rect.maxY), radius: r,
                        startAngle: 0, endAngle: -.pi, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: separatorY + notch))
        path.addArc(center: CGPoint(x: rect.minX, y: separatorY), radius: notch,
                    startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
