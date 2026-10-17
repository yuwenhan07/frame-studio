import AppKit
import CoreText

public enum CameraBrand: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "自动识别"
    case nikon = "Nikon", canon = "Canon", sony = "SONY", fujifilm = "FUJIFILM"
    case leica = "Leica · 徕卡", hasselblad = "Hasselblad · 哈苏"
    case lumix = "LUMIX · 松下", olympus = "OLYMPUS", omSystem = "OM SYSTEM"
    case pentax = "PENTAX", ricoh = "RICOH", dji = "DJI", insta360 = "Insta360"
    case custom = "自定义文字"
    public var id: String { rawValue }
    public var label: String { rawValue.components(separatedBy: " · ").first! }

    public static func detect(_ metadata: PhotoMetadata) -> CameraBrand {
        let make = metadata.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (make.isEmpty ? metadata.camera : make).lowercased()
        let aliases: [(CameraBrand, [String])] = [
            (.nikon, ["nikon", "尼康"]), (.canon, ["canon", "佳能"]), (.sony, ["sony", "索尼"]),
            (.fujifilm, ["fuji", "富士"]), (.leica, ["leica", "徕卡"]), (.hasselblad, ["hasselblad", "哈苏"]),
            (.lumix, ["panasonic", "lumix", "松下"]), (.omSystem, ["om digital", "om system"]), (.olympus, ["olympus", "奥林巴斯"]),
            (.pentax, ["pentax", "宾得"]), (.ricoh, ["ricoh", "理光"]), (.dji, ["dji", "大疆"]),
            (.insta360, ["insta360", "insta 360", "影石", "arashi vision", "arashivision"])
        ]
        return aliases.first { entry in entry.1.contains { text.contains($0) } }?.0 ?? .custom
    }

    public func resolved(metadata: PhotoMetadata) -> CameraBrand { self == .automatic ? Self.detect(metadata) : self }
    public var hasVectorMark: Bool { BrandVectors.marks[self] != nil }
    public var markAspect: CGFloat {
        guard let layers = BrandVectors.marks[self] else { return self == .olympus ? 6 : 4.8 }
        let bounds = layers.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        return bounds.width / max(1, bounds.height)
    }

    public static func timestamp(_ metadata: PhotoMetadata) -> String {
        guard let raw = metadata.captureDateTime else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"; formatter.isLenient = false
        guard let date = formatter.date(from: raw) else { return "" }
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Draw the authentic filled outlines, preserving internal white cutouts.
    public func draw(in context: CGContext, rect: CGRect, color: Bool, fallback: String = "") {
        if let layers = BrandVectors.marks[self] {
            let bounds = layers.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
            let scale = min(rect.width / max(1, bounds.width), rect.height / max(1, bounds.height))
            context.saveGState()
            context.translateBy(x: rect.midX - bounds.width * scale / 2 - bounds.minX * scale,
                y: rect.midY + bounds.height * scale / 2 + bounds.minY * scale)
            context.scaleBy(x: scale, y: -scale)
            for layer in layers {
                let white = layer.color.usingColorSpace(.sRGB).map { $0.redComponent > 0.95 && $0.greenComponent > 0.95 && $0.blueComponent > 0.95 } ?? false
                context.setFillColor((color || white ? layer.color : NSColor.black).cgColor)
                context.addPath(layer.path); context.drawPath(using: layer.evenOdd ? .eoFill : .fill)
            }
            context.restoreGState()
        } else {
            let text = self == .custom || self == .automatic ? fallback : label
            let font = NSFont(name: "HelveticaNeue-Bold", size: rect.height * 0.80) ?? .boldSystemFont(ofSize: rect.height * 0.80)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black]))
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            guard bounds.width > 0 else { return }
            let scale = min(1, rect.width / bounds.width, rect.height / max(1, bounds.height))
            context.saveGState()
            context.translateBy(x: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
            context.scaleBy(x: scale, y: scale)
            context.textMatrix = .identity; context.textPosition = .zero
            CTLineDraw(line, context); context.restoreGState()
        }
    }
}

public enum ClassicArrangement: String, CaseIterable, Codable, Identifiable, Sendable {
    case centered = "品牌居中", split = "左文右标", inline = "横向信息"
    public var id: String { rawValue }
}

public struct ClassicLayout {
    public let width: Int
    public let height: Int
    public let photoRect: CGRect
    public let footerRect: CGRect
    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: FrameStyle) {
        let w = CGFloat(max(64, outputWidth))
        let margin = w * min(0.08, max(0, style.classicMargin))
        let footer = w * min(0.22, max(0.06, style.classicFooter))
        let photoW = w - margin * 2
        let photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
        width = Int(w); height = Int(ceil(photoH + margin + footer))
        photoRect = CGRect(x: margin, y: footer, width: photoW, height: photoH)
        footerRect = CGRect(x: 0, y: 0, width: w, height: footer)
    }
}
