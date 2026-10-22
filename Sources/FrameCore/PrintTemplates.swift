import AppKit

public enum PrintPaper: String, CaseIterable, Codable, Identifiable, Sendable {
    case ivory = "暖白", white = "纯白", charcoal = "炭黑"
    public var id: String { rawValue }
    public var color: NSColor {
        PaletteColor(hex: self == .ivory ? "#F7F3EA" : (self == .white ? "#FFFEFC" : "#292A29"))!.color
    }
    public var ink: NSColor { PaletteColor(hex: self == .charcoal ? "#F2EEE6" : "#34332F")!.color }
}

public enum EditorialAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case photo = "照片主色", custom = "自定义"
    public var id: String { rawValue }
}

// Local session files are editable; keep all decoded dimensions within the UI ranges.
private extension KeyedDecodingContainer {
    func bounded(_ key: Key, default fallback: Double, range: ClosedRange<Double>) throws -> Double {
        let value = try decodeIfPresent(Double.self, forKey: key) ?? fallback
        return value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

public struct Film35Style: Codable, Equatable, Sendable {
    public var label = "FILM"
    public var number = "01"
    public var showSprockets = true
    public var showParameters = false
    public var showSignature = true
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var margin = 0.065
    public var rail = 0.085
    public var textScale = 1.0
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case label, number, showSprockets, showParameters, showSignature, dateMode, customDate, margin, rail, textScale
    }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? label
        if label == "FRAME 35" { label = "FILM" } // Migrate the old format-specific default; keep custom labels.
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? number
        showSprockets = try c.decodeIfPresent(Bool.self, forKey: .showSprockets) ?? showSprockets
        showParameters = try c.decodeIfPresent(Bool.self, forKey: .showParameters) ?? showParameters
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        margin = try c.bounded(.margin, default: margin, range: 0.035...0.12)
        rail = try c.bounded(.rail, default: rail, range: 0.065...0.14)
        textScale = try c.bounded(.textScale, default: textScale, range: 0.65...1.6)
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.margin = d.margin; v.rail = d.rail; v.textScale = d.textScale; return v
    }
}

public struct GalleryStyle: Codable, Equatable, Sendable {
    public var paper: PrintPaper = .ivory
    public var title = ""
    public var subtitle = ""
    public var titleFont = "Times New Roman"
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var showSignature = true
    public var showOutline = true
    public var margin = 0.10
    public var footer = 0.16
    public var textScale = 1.0
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case paper, title, subtitle, titleFont, dateMode, customDate, showSignature, showOutline, margin, footer, textScale
    }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        paper = try c.decodeIfPresent(PrintPaper.self, forKey: .paper) ?? paper
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? subtitle
        titleFont = try c.decodeIfPresent(String.self, forKey: .titleFont) ?? titleFont
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        showOutline = try c.decodeIfPresent(Bool.self, forKey: .showOutline) ?? showOutline
        margin = try c.bounded(.margin, default: margin, range: 0.045...0.18)
        footer = try c.bounded(.footer, default: footer, range: 0.12...0.26)
        textScale = try c.bounded(.textScale, default: textScale, range: 0.65...1.6)
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.margin = d.margin; v.footer = d.footer; v.textScale = d.textScale; return v
    }
}

public struct EditorialStyle: Codable, Equatable, Sendable {
    public var paper: PrintPaper = .ivory
    public var title = "WANDER"
    public var subtitle = "旅行影像日志"
    public var edition = "VOL. 01"
    public var notes = ""
    public var titleFont = "Times New Roman"
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var showSignature = true
    public var showAccent = true
    public var accent: EditorialAccent = .photo
    public var accentHex = "#8B7565"
    public var margin = 0.055
    public var header = 0.23
    public var footer = 0.12
    public var textScale = 1.0
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case paper, title, subtitle, edition, notes, titleFont, dateMode, customDate, showSignature, showAccent, accent, accentHex
        case margin, header, footer, textScale
    }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        paper = try c.decodeIfPresent(PrintPaper.self, forKey: .paper) ?? paper
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? subtitle
        edition = try c.decodeIfPresent(String.self, forKey: .edition) ?? edition
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? notes
        titleFont = try c.decodeIfPresent(String.self, forKey: .titleFont) ?? titleFont
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        showAccent = try c.decodeIfPresent(Bool.self, forKey: .showAccent) ?? showAccent
        accent = try c.decodeIfPresent(EditorialAccent.self, forKey: .accent) ?? accent
        accentHex = PaletteColor(hex: try c.decodeIfPresent(String.self, forKey: .accentHex) ?? accentHex)?.hex ?? "#8B7565"
        margin = try c.bounded(.margin, default: margin, range: 0.025...0.12)
        header = try c.bounded(.header, default: header, range: 0.17...0.32)
        footer = try c.bounded(.footer, default: footer, range: 0.09...0.20)
        textScale = try c.bounded(.textScale, default: textScale, range: 0.65...1.6)
    }
    public func accentColor(photo: PhotoDocument) -> NSColor {
        accent == .photo ? photo.palette.colorWalkColor().color : (PaletteColor(hex: accentHex) ?? PaletteColor(hex: "#8B7565")!).color
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.margin = d.margin; v.header = d.header; v.footer = d.footer; v.textScale = d.textScale; return v
    }
}

public struct InstantStyle: Codable, Equatable, Sendable {
    public var paper: PrintPaper = .white
    public var caption = "Keep this moment."
    public var captionFont = "Noteworthy"
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var showSignature = true
    public var margin = 0.065
    public var border = 0.04
    public var footer = 0.15
    public var textScale = 1.0
    public var shadow = 0.18
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case paper, caption, captionFont, dateMode, customDate, showSignature, margin, border, footer, textScale, shadow
    }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        paper = try c.decodeIfPresent(PrintPaper.self, forKey: .paper) ?? paper
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? caption
        captionFont = try c.decodeIfPresent(String.self, forKey: .captionFont) ?? captionFont
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        margin = try c.bounded(.margin, default: margin, range: 0.035...0.12)
        border = try c.bounded(.border, default: border, range: 0.025...0.075)
        footer = try c.bounded(.footer, default: footer, range: 0.10...0.24)
        textScale = try c.bounded(.textScale, default: textScale, range: 0.65...1.6)
        shadow = try c.bounded(.shadow, default: shadow, range: 0...0.35)
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.margin = d.margin; v.border = d.border; v.footer = d.footer
        v.textScale = d.textScale; v.shadow = d.shadow; return v
    }
}

/// All four print layouts preserve the complete oriented photograph.
public struct PrintLayout {
    public let width: Int, height: Int
    public let photoRect: CGRect, cardRect: CGRect, headerRect: CGRect, footerRect: CGRect
    public static func sideMargin(imageWidth: Int, imageHeight: Int, style: FrameStyle) -> Double {
        let portrait = imageHeight > imageWidth
        switch style.template {
        case .film35: return min(0.12, max(0.035, style.film35.margin))
        case .gallery: return min(0.18, max(0.045, style.gallery.margin)) + (portrait ? 0.02 : 0)
        case .editorial: return min(0.12, max(0.025, style.editorial.margin))
        case .instant: return min(0.12, max(0.035, style.instant.margin)) + min(0.075, max(0.025, style.instant.border))
        default: return 0
        }
    }
    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: FrameStyle) {
        let w = CGFloat(max(64, outputWidth))
        let side = w * Self.sideMargin(imageWidth: imageWidth, imageHeight: imageHeight, style: style)
        let photoW = w - side * 2
        let photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
        let top: CGFloat, bottom: CGFloat
        switch style.template {
        case .film35:
            top = w * min(0.14, max(0.065, style.film35.rail)); bottom = top
        case .gallery:
            top = side; bottom = w * min(0.26, max(0.12, style.gallery.footer))
        case .editorial:
            top = w * min(0.32, max(0.17, style.editorial.header))
            bottom = w * min(0.20, max(0.09, style.editorial.footer))
        case .instant:
            top = side
            bottom = w * (min(0.12, max(0.035, style.instant.margin)) + min(0.24, max(0.10, style.instant.footer)))
        default: top = side; bottom = side
        }
        width = Int(w); height = Int(ceil(photoH + top + bottom))
        photoRect = CGRect(x: side, y: bottom, width: photoW, height: photoH)
        headerRect = CGRect(x: side, y: photoRect.maxY, width: photoW, height: CGFloat(height) - photoRect.maxY)
        footerRect = CGRect(x: side, y: 0, width: photoW, height: bottom)
        if style.template == .instant {
            let margin = w * min(0.12, max(0.035, style.instant.margin))
            cardRect = CGRect(x: margin, y: margin, width: w - margin * 2, height: CGFloat(height) - margin * 2)
        } else { cardRect = CGRect(x: 0, y: 0, width: w, height: CGFloat(height)) }
    }
}
