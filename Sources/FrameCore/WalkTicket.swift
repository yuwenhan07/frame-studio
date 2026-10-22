import AppKit

public enum WalkTicketTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case charcoal = "深灰", cream = "奶油白", orange = "暖橙", brown = "咖啡棕", photo = "照片主色", custom = "自定义"
    public var id: String { rawValue }
}

public enum WalkTicketPhotoMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case fit = "完整照片", fill = "填满裁切"
    public var id: String { rawValue }
}

public struct WalkTicketStyle: Codable, Equatable, Sendable {
    public var theme: WalkTicketTheme = .charcoal
    public var customHex = "#494644"
    public var heading = ""
    public var title = "COLOR WALK"
    public var subtitle = "漫步日志"
    public var notes = ""
    public var titleFont = "Times New Roman"
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var admission = "ADMIT ONE · NO. 02"
    public var stubCaption = "ROUTE WALK"
    public var showBarcode = true
    public var showPalette = true
    public var showHex = false
    public var paletteCount = 4
    public var photoMode: WalkTicketPhotoMode = .fit
    public var margin: Double = 0.09
    public var aspect: Double = 0.50
    public var corner: Double = 0.025
    public var textScale: Double = 1
    public var shadow: Double = 0.30
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, customHex, heading, title, subtitle, notes, titleFont, dateMode, customDate
        case admission, stubCaption, showBarcode, showPalette, showHex, paletteCount, photoMode
        case margin, aspect, corner, textScale, shadow
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(WalkTicketTheme.self, forKey: .theme) ?? theme
        customHex = try c.decodeIfPresent(String.self, forKey: .customHex) ?? customHex
        customHex = PaletteColor(hex: customHex)?.hex ?? "#494644"
        heading = try c.decodeIfPresent(String.self, forKey: .heading) ?? heading
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? subtitle
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? notes
        titleFont = try c.decodeIfPresent(String.self, forKey: .titleFont) ?? titleFont
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        admission = try c.decodeIfPresent(String.self, forKey: .admission) ?? admission
        stubCaption = try c.decodeIfPresent(String.self, forKey: .stubCaption) ?? stubCaption
        showBarcode = try c.decodeIfPresent(Bool.self, forKey: .showBarcode) ?? showBarcode
        showPalette = try c.decodeIfPresent(Bool.self, forKey: .showPalette) ?? showPalette
        showHex = try c.decodeIfPresent(Bool.self, forKey: .showHex) ?? showHex
        paletteCount = min(8, max(2, try c.decodeIfPresent(Int.self, forKey: .paletteCount) ?? paletteCount))
        photoMode = try c.decodeIfPresent(WalkTicketPhotoMode.self, forKey: .photoMode) ?? photoMode
        for (key, path, range) in [
            (CodingKeys.margin, \Self.margin, 0.05...0.16), (.aspect, \.aspect, 0.44...0.64),
            (.corner, \.corner, 0...0.045), (.textScale, \.textScale, 0.5...2), (.shadow, \.shadow, 0...1)
        ] {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? self[keyPath: path]
            self[keyPath: path] = value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : Self()[keyPath: path]
        }
    }

    public func paperColor(photo: PhotoDocument? = nil) -> NSColor {
        let hex: String
        switch theme {
        case .charcoal: hex = "#494644"
        case .cream: hex = "#FFFCF5"
        case .orange: hex = "#FF884B"
        case .brown: hex = "#593600"
        case .photo: return photo?.palette.colorWalkColor().color ?? NSColor(srgbRed: 0.29, green: 0.27, blue: 0.26, alpha: 1)
        case .custom: hex = customHex
        }
        return (PaletteColor(hex: hex) ?? PaletteColor(hex: "#494644")!).color
    }

    public func resetLayout() -> Self {
        var updated = self
        let defaults = Self()
        updated.margin = defaults.margin; updated.aspect = defaults.aspect; updated.corner = defaults.corner
        updated.textScale = defaults.textScale; updated.shadow = defaults.shadow
        return updated
    }
}

public struct WalkTicketLayout {
    public let width: Int, height: Int
    public let card: CGRect, photoSlot: CGRect, photoRect: CGRect, body: CGRect, stub: CGRect
    public let separatorX: CGFloat, notch: CGFloat, corner: CGFloat
    public let barcodeRect: CGRect, ribbonRect: CGRect

    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: WalkTicketStyle) {
        let w = CGFloat(max(64, outputWidth)), margin = w * min(0.16, max(0.05, style.margin))
        let cw = w - margin * 2, ch = cw * min(0.64, max(0.44, style.aspect)), pad = cw * 0.04
        width = Int(w); height = Int(ceil(ch + margin * 1.4))
        card = CGRect(x: margin, y: margin * 0.7, width: cw, height: ch)
        photoSlot = CGRect(x: card.minX + pad, y: card.minY + pad, width: cw * 0.305, height: ch - pad * 2)
        let factor = min(photoSlot.width / CGFloat(max(1, imageWidth)), photoSlot.height / CGFloat(max(1, imageHeight)))
        let size = CGSize(width: CGFloat(max(1, imageWidth)) * factor, height: CGFloat(max(1, imageHeight)) * factor)
        photoRect = style.photoMode == .fill ? photoSlot : CGRect(x: photoSlot.midX - size.width / 2,
            y: photoSlot.midY - size.height / 2, width: size.width, height: size.height)
        separatorX = card.minX + cw * 0.74
        body = CGRect(x: photoSlot.maxX + cw * 0.035, y: card.minY + pad,
            width: separatorX - photoSlot.maxX - cw * 0.07, height: ch - pad * 2)
        stub = CGRect(x: separatorX, y: card.minY, width: card.maxX - separatorX, height: ch)
        notch = min(w * 0.018, ch * 0.065)
        corner = min(w * min(0.045, max(0, style.corner)), pad)
        barcodeRect = CGRect(x: stub.midX + stub.width * 0.13 - w * 0.0375,
            y: card.minY + pad * 0.85, width: w * 0.075, height: ch * 0.46)
        ribbonRect = CGRect(x: barcodeRect.minX, y: card.maxY - pad - ch * 0.25,
            width: barcodeRect.width, height: ch * 0.25)
    }

    public static func originalWidth(imageWidth: Int, imageHeight: Int, style: WalkTicketStyle) -> Int {
        let layout = Self(imageWidth: imageWidth, imageHeight: imageHeight, outputWidth: 1000, style: style)
        let sx = layout.photoSlot.width / CGFloat(max(1, imageWidth))
        let sy = layout.photoSlot.height / CGFloat(max(1, imageHeight))
        let scale = style.photoMode == .fill ? max(sx, sy) : min(sx, sy)
        return Int(ceil(1000 / scale))
    }

    public var outline: CGPath {
        let p = CGMutablePath(), r = corner, c = card, n = notch, x = separatorX
        p.move(to: CGPoint(x: c.minX + r, y: c.minY))
        p.addLine(to: CGPoint(x: x - n, y: c.minY))
        p.addArc(center: CGPoint(x: x, y: c.minY), radius: n, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: c.maxX - r, y: c.minY))
        p.addQuadCurve(to: CGPoint(x: c.maxX, y: c.minY + r), control: CGPoint(x: c.maxX, y: c.minY))
        p.addLine(to: CGPoint(x: c.maxX, y: c.maxY - r))
        p.addQuadCurve(to: CGPoint(x: c.maxX - r, y: c.maxY), control: CGPoint(x: c.maxX, y: c.maxY))
        p.addLine(to: CGPoint(x: x + n, y: c.maxY))
        p.addArc(center: CGPoint(x: x, y: c.maxY), radius: n, startAngle: 0, endAngle: -.pi, clockwise: true)
        p.addLine(to: CGPoint(x: c.minX + r, y: c.maxY))
        p.addQuadCurve(to: CGPoint(x: c.minX, y: c.maxY - r), control: CGPoint(x: c.minX, y: c.maxY))
        p.addLine(to: CGPoint(x: c.minX, y: c.minY + r))
        p.addQuadCurve(to: CGPoint(x: c.minX + r, y: c.minY), control: CGPoint(x: c.minX, y: c.minY))
        p.closeSubpath()
        return p
    }
}
