import AppKit

public enum CinemaInk: String, Codable, CaseIterable, Identifiable, Sendable {
    case ivory = "暖白字幕", amber = "浅金字幕"
    public var id: String { rawValue }
    public var color: NSColor { PaletteColor(hex: self == .ivory ? "#EEEAE1" : "#DEC992")!.color }
}

private extension KeyedDecodingContainer {
    func limited(_ key: Key, _ fallback: Double, _ range: ClosedRange<Double>) throws -> Double {
        let v = try decodeIfPresent(Double.self, forKey: key) ?? fallback
        return v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : fallback
    }
}

public struct CinemaStyle: Codable, Equatable, Sendable {
    public var subtitle = "把日常，留给时间。"
    public var translation = "Let the ordinary become a scene."
    public var scene = "SCENE 01"
    public var ink: CinemaInk = .ivory
    public var showSignature = false
    public var top = 0.065
    public var bottom = 0.17
    public var position = 0.50
    public var textScale = 1.0
    public init() {}
    private enum CodingKeys: String, CodingKey { case subtitle, translation, scene, ink, showSignature, top, bottom, position, textScale }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? subtitle
        translation = try c.decodeIfPresent(String.self, forKey: .translation) ?? translation
        scene = try c.decodeIfPresent(String.self, forKey: .scene) ?? scene
        ink = try c.decodeIfPresent(CinemaInk.self, forKey: .ink) ?? ink
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        top = try c.limited(.top, top, 0.025...0.14); bottom = try c.limited(.bottom, bottom, 0.12...0.30)
        position = try c.limited(.position, position, 0...1); textScale = try c.limited(.textScale, textScale, 0.65...1.6)
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.top = d.top; v.bottom = d.bottom; v.position = d.position; v.textScale = d.textScale; return v
    }
}

public struct ReceiptStyle: Codable, Equatable, Sendable {
    public var title = "MEMORY RECEIPT"
    public var place = ""
    public var number = "001"
    public var note = "THANK YOU FOR THIS MOMENT"
    public var paper: PrintPaper = .ivory
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var showParameters = false
    public var showSignature = true
    public var margin = 0.10
    public var footer = 0.26
    public var textScale = 1.0
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case title, place, number, note, paper, dateMode, customDate, showParameters, showSignature, margin, footer, textScale
    }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? place
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? number
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? note
        paper = try c.decodeIfPresent(PrintPaper.self, forKey: .paper) ?? paper
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        showParameters = try c.decodeIfPresent(Bool.self, forKey: .showParameters) ?? showParameters
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        margin = try c.limited(.margin, margin, 0.06...0.18); footer = try c.limited(.footer, footer, 0.22...0.38)
        textScale = try c.limited(.textScale, textScale, 0.65...1.6)
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.margin = d.margin; v.footer = d.footer; v.textScale = d.textScale; return v
    }
}

public struct TornPaperStyle: Codable, Equatable, Sendable {
    public var showCaptionArea = false
    public var caption = "A quiet moment."
    public var captionFont = "Times New Roman"
    public var paper: PrintPaper = .ivory
    public var dateMode: TicketDateMode = .captureDate
    public var customDate = ""
    public var showSignature = true
    public var margin = 0.07
    public var border = 0.009
    public var footer = 0.12
    public var roughness = 0.0035
    public var shadow = 0.18
    public var textScale = 1.0
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case showCaptionArea, caption, captionFont, paper, dateMode, customDate, showSignature, margin, border, footer, roughness, shadow, textScale
    }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        showCaptionArea = try c.decodeIfPresent(Bool.self, forKey: .showCaptionArea) ?? showCaptionArea
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? caption
        captionFont = try c.decodeIfPresent(String.self, forKey: .captionFont) ?? captionFont
        paper = try c.decodeIfPresent(PrintPaper.self, forKey: .paper) ?? paper
        dateMode = try c.decodeIfPresent(TicketDateMode.self, forKey: .dateMode) ?? dateMode
        customDate = try c.decodeIfPresent(String.self, forKey: .customDate) ?? customDate
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? showSignature
        margin = try c.limited(.margin, margin, 0.035...0.14); border = try c.limited(.border, border, 0.004...0.08)
        if !c.contains(.showCaptionArea), border == 0.04 { border = 0.009 } // Replace the former broad-border default; preserve custom widths.
        footer = try c.limited(.footer, footer, 0.09...0.22); roughness = try c.limited(.roughness, roughness, 0.001...0.008)
        shadow = try c.limited(.shadow, shadow, 0...0.35); textScale = try c.limited(.textScale, textScale, 0.65...1.6)
    }
    public func resetLayout() -> Self {
        var v = self; let d = Self(); v.margin = d.margin; v.border = d.border; v.footer = d.footer
        v.roughness = d.roughness; v.shadow = d.shadow; v.textScale = d.textScale; return v
    }
}

public struct KeepsakeLayout {
    public let width: Int, height: Int
    public let photoRect: CGRect, cardRect: CGRect, headerRect: CGRect, footerRect: CGRect
    public static func sideMargin(_ style: FrameStyle) -> Double {
        switch style.template {
        case .cinema: return 0
        case .receipt: return min(0.18, max(0.06, style.receipt.margin)) + 0.035
        case .tornPaper: return min(0.14, max(0.035, style.tornPaper.margin)) + min(0.08, max(0.004, style.tornPaper.border))
        default: return 0
        }
    }
    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: FrameStyle) {
        let w = CGFloat(max(64, outputWidth)), side = w * Self.sideMargin(style)
        let photoW = w - side * 2, photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
        let top: CGFloat, bottom: CGFloat, outer: CGFloat
        switch style.template {
        case .cinema:
            top = w * min(0.14, max(0.025, style.cinema.top)); bottom = w * min(0.30, max(0.12, style.cinema.bottom)); outer = 0
        case .receipt:
            outer = w * min(0.18, max(0.06, style.receipt.margin))
            top = outer + w * 0.15; bottom = outer + w * min(0.38, max(0.22, style.receipt.footer))
        default:
            outer = w * min(0.14, max(0.035, style.tornPaper.margin))
            top = side
            bottom = style.tornPaper.showCaptionArea ? outer + w * min(0.22, max(0.09, style.tornPaper.footer)) : side
        }
        width = Int(w); height = Int(ceil(top + photoH + bottom))
        photoRect = CGRect(x: side, y: bottom, width: photoW, height: photoH)
        cardRect = CGRect(x: outer, y: outer, width: w - outer * 2, height: CGFloat(height) - outer * 2)
        headerRect = CGRect(x: side, y: photoRect.maxY, width: photoW, height: CGFloat(height) - outer - photoRect.maxY)
        footerRect = CGRect(x: side, y: outer, width: photoW, height: bottom - outer)
    }
}

