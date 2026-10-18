import Foundation

// Add a template ID and a renderer branch to grow the catalog without changing photo import/export.
public enum TemplateID: String, CaseIterable, Codable, Identifiable, Sendable {
    case softFrame
    case colorCircles, colorSquares
    case colorWalk
    case postageFrame
    case classicFrame
    case tickets
    public var id: String { rawValue }
    public var isPalette: Bool { self == .colorCircles || self == .colorSquares }
    public var title: String {
        switch self { case .softFrame: return "柔焦画框"; case .colorCircles: return "圆形色卡"; case .colorSquares: return "方形色卡"; case .colorWalk: return "Color Walk"; case .postageFrame: return "邮票画框"; case .classicFrame: return "经典画框"; case .tickets: return "Tickets 票券" }
    }
    public var subtitle: String {
        switch self { case .softFrame: return "同源虚化 · 悬浮照片"; case .colorCircles: return "照片主色 · 圆形呈现"; case .colorSquares: return "照片主色 · 方形与菱形"; case .colorWalk: return "一张照片 · 一种色调"; case .postageFrame: return "齿孔白边 · 旅途落款"; case .classicFrame: return "经典品牌 · 纯白底栏"; case .tickets: return "旅途票根 · 邮戳与条码" }
    }
}

public enum PaletteOrder: String, CaseIterable, Codable, Identifiable, Sendable {
    case lightness = "由深到浅", dominance = "面积占比"
    public var id: String { rawValue }
}

public struct FrameStyle: Codable, Equatable, Sendable {
    public var template: TemplateID = .softFrame
    public var margin: Double = 0.028
    public var portraitMargin: Double = 0.08
    public var topSpace: Double = 0.085
    public var footerSpace: Double = 0.19
    public var corner: Double = 0.022
    public var blur: Double = 0.036
    public var shadow: Double = 0.72
    public var brightness: Double = 0
    public var textScale: Double = 1
    public var signatureScale: Double = 1
    public var signatureChineseFont: String = SignatureTypography.defaultFontFamily
    public var signatureEnglishFont: String = SignatureTypography.defaultFontFamily
    public var paletteCount: Int = 5
    public var paletteMargin: Double = 0.02
    public var paletteFooter: Double = 0.16
    public var paletteSwatchSize: Double = 0.065
    public var paletteShowHex = true
    public var paletteShowSignature = true
    public var paletteDiamond = true
    public var paletteOrder: PaletteOrder = .lightness
    public var colorWalkHeader: Double = 0.585
    public var colorWalkTextScale: Double = 1
    public var colorWalkTextPosition: Double = 0.50
    public var colorWalkStamp = "Stay alive · keep trying"
    public var colorWalkShowStamp = true
    public var colorWalkDetail: ColorWalkDetail = .captureTime
    public var colorWalkCustomDetail = ""
    public var colorWalkInk: ColorWalkInk = .white
    public var postageVariant: PostageVariant = .plain
    public var postageMargin: Double = 0.105
    public var postageBorder: Double = 0.027
    public var postagePerforation: Double = 0.0135
    public var postageFooter: Double = 0.10
    public var postageBlur: Double = 0.04
    public var postageBrightness: Double = 0
    public var postageShadow: Double = 0.45
    public var postageTextScale: Double = 1
    public var postagePlace = ""
    public var postageDateMode: PostageDateMode = .captureDate
    public var postageCustomDate = ""
    public var ticketMargin: Double = 0.17
    public var ticketBorder: Double = 0.028
    public var ticketFooter: Double = 0.205
    public var ticketPerforation: Double = 0.0065
    public var ticketBlur: Double = 0.045
    public var ticketBrightness: Double = -0.08
    public var ticketShadow: Double = 0.25
    public var ticketTextScale: Double = 1
    public var ticketMarkScale: Double = 1
    public var ticketTitle: String = "TICKETS"
    public var ticketSubtitle: String = ""
    public var ticketDateMode: TicketDateMode = .captureDate
    public var ticketCustomDate: String = ""
    public var ticketMark: TicketMark = .stamp
    public var ticketStampTop: String = "WORLD POST"
    public var ticketStampBottom: String = "AIR MAIL"
    public var ticketBarcodeValue: String = "FRAMESTUDIO"
    public var classicArrangement: ClassicArrangement = .centered
    public var classicBrand: CameraBrand = .automatic
    public var classicFooter: Double = 0.12
    public var classicMargin: Double = 0
    public var classicBrandScale: Double = 1
    public var classicInfoScale: Double = 1
    public var classicBrandColor = true
    public var classicShowCamera = false
    public var classicShowParameters = true
    public var classicShowDate = false
    public var classicShowSignature = false
    public var classicUseCustomLogo = false
    public var whiteText = true
    public var whiteBrand = false
    public var showBrand = true
    public var showCamera = true
    public var showParameters = true
    public var signature = ""
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case template, margin, portraitMargin, topSpace, footerSpace, corner, blur, shadow
        case brightness, textScale, signatureScale, whiteText, whiteBrand, showBrand, showCamera, showParameters, signature
        case signatureChineseFont, signatureEnglishFont
        case paletteCount, paletteMargin, paletteFooter, paletteSwatchSize, paletteShowHex, paletteShowSignature, paletteDiamond, paletteOrder
        case colorWalkHeader, colorWalkTextScale, colorWalkStamp, colorWalkShowStamp, colorWalkDetail, colorWalkCustomDetail, colorWalkInk
        case colorWalkTextPosition
        case postageVariant, postageMargin, postageBorder, postagePerforation, postageFooter
        case postageBlur, postageBrightness, postageShadow, postageTextScale, postagePlace, postageDateMode, postageCustomDate
        case ticketMargin, ticketBorder, ticketFooter, ticketPerforation, ticketBlur, ticketBrightness, ticketShadow, ticketTextScale, ticketMarkScale, ticketTitle, ticketSubtitle, ticketDateMode, ticketCustomDate, ticketMark, ticketStampTop, ticketStampBottom, ticketBarcodeValue
        case classicArrangement, classicBrand, classicFooter, classicMargin, classicBrandScale, classicInfoScale
        case classicBrandColor, classicShowCamera, classicShowParameters, classicShowDate, classicShowSignature, classicUseCustomLogo
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        template = try values.decodeIfPresent(TemplateID.self, forKey: .template) ?? template
        margin = try values.decodeIfPresent(Double.self, forKey: .margin) ?? margin
        // Older saved styles have no portrait-specific margin. Keep all their other settings.
        portraitMargin = try values.decodeIfPresent(Double.self, forKey: .portraitMargin) ?? portraitMargin
        topSpace = try values.decodeIfPresent(Double.self, forKey: .topSpace) ?? topSpace
        footerSpace = try values.decodeIfPresent(Double.self, forKey: .footerSpace) ?? footerSpace
        corner = try values.decodeIfPresent(Double.self, forKey: .corner) ?? corner
        blur = try values.decodeIfPresent(Double.self, forKey: .blur) ?? blur
        shadow = try values.decodeIfPresent(Double.self, forKey: .shadow) ?? shadow
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        textScale = try values.decodeIfPresent(Double.self, forKey: .textScale) ?? textScale
        // Signatures used to share textScale. Preserve their saved size during migration.
        signatureScale = try values.decodeIfPresent(Double.self, forKey: .signatureScale) ?? textScale
        signatureChineseFont = try values.decodeIfPresent(String.self, forKey: .signatureChineseFont) ?? signatureChineseFont
        signatureEnglishFont = try values.decodeIfPresent(String.self, forKey: .signatureEnglishFont) ?? signatureEnglishFont
        paletteCount = try values.decodeIfPresent(Int.self, forKey: .paletteCount) ?? paletteCount
        paletteMargin = try values.decodeIfPresent(Double.self, forKey: .paletteMargin) ?? paletteMargin
        paletteFooter = try values.decodeIfPresent(Double.self, forKey: .paletteFooter) ?? paletteFooter
        paletteSwatchSize = try values.decodeIfPresent(Double.self, forKey: .paletteSwatchSize) ?? paletteSwatchSize
        paletteShowHex = try values.decodeIfPresent(Bool.self, forKey: .paletteShowHex) ?? paletteShowHex
        paletteShowSignature = try values.decodeIfPresent(Bool.self, forKey: .paletteShowSignature) ?? paletteShowSignature
        paletteDiamond = try values.decodeIfPresent(Bool.self, forKey: .paletteDiamond) ?? paletteDiamond
        paletteOrder = try values.decodeIfPresent(PaletteOrder.self, forKey: .paletteOrder) ?? paletteOrder
        colorWalkHeader = try values.decodeIfPresent(Double.self, forKey: .colorWalkHeader) ?? colorWalkHeader
        colorWalkTextScale = try values.decodeIfPresent(Double.self, forKey: .colorWalkTextScale) ?? colorWalkTextScale
        colorWalkTextPosition = try values.decodeIfPresent(Double.self, forKey: .colorWalkTextPosition) ?? colorWalkTextPosition
        colorWalkStamp = try values.decodeIfPresent(String.self, forKey: .colorWalkStamp) ?? colorWalkStamp
        colorWalkShowStamp = try values.decodeIfPresent(Bool.self, forKey: .colorWalkShowStamp) ?? colorWalkShowStamp
        colorWalkDetail = try values.decodeIfPresent(ColorWalkDetail.self, forKey: .colorWalkDetail) ?? colorWalkDetail
        colorWalkCustomDetail = try values.decodeIfPresent(String.self, forKey: .colorWalkCustomDetail) ?? colorWalkCustomDetail
        colorWalkInk = try values.decodeIfPresent(ColorWalkInk.self, forKey: .colorWalkInk) ?? colorWalkInk
        postageVariant = try values.decodeIfPresent(PostageVariant.self, forKey: .postageVariant) ?? postageVariant
        postageMargin = try values.decodeIfPresent(Double.self, forKey: .postageMargin) ?? postageMargin
        postageBorder = try values.decodeIfPresent(Double.self, forKey: .postageBorder) ?? postageBorder
        postagePerforation = try values.decodeIfPresent(Double.self, forKey: .postagePerforation) ?? postagePerforation
        postageFooter = try values.decodeIfPresent(Double.self, forKey: .postageFooter) ?? postageFooter
        postageBlur = try values.decodeIfPresent(Double.self, forKey: .postageBlur) ?? postageBlur
        postageBrightness = try values.decodeIfPresent(Double.self, forKey: .postageBrightness) ?? postageBrightness
        postageShadow = try values.decodeIfPresent(Double.self, forKey: .postageShadow) ?? postageShadow
        postageTextScale = try values.decodeIfPresent(Double.self, forKey: .postageTextScale) ?? postageTextScale
        postagePlace = try values.decodeIfPresent(String.self, forKey: .postagePlace) ?? postagePlace
        postageDateMode = try values.decodeIfPresent(PostageDateMode.self, forKey: .postageDateMode) ?? postageDateMode
        postageCustomDate = try values.decodeIfPresent(String.self, forKey: .postageCustomDate) ?? postageCustomDate
        ticketMargin = try values.decodeIfPresent(Double.self, forKey: .ticketMargin) ?? ticketMargin
        ticketBorder = try values.decodeIfPresent(Double.self, forKey: .ticketBorder) ?? ticketBorder
        ticketFooter = try values.decodeIfPresent(Double.self, forKey: .ticketFooter) ?? ticketFooter
        ticketPerforation = try values.decodeIfPresent(Double.self, forKey: .ticketPerforation) ?? ticketPerforation
        ticketBlur = try values.decodeIfPresent(Double.self, forKey: .ticketBlur) ?? ticketBlur
        ticketBrightness = try values.decodeIfPresent(Double.self, forKey: .ticketBrightness) ?? ticketBrightness
        ticketShadow = try values.decodeIfPresent(Double.self, forKey: .ticketShadow) ?? ticketShadow
        ticketTextScale = try values.decodeIfPresent(Double.self, forKey: .ticketTextScale) ?? ticketTextScale
        ticketMarkScale = try values.decodeIfPresent(Double.self, forKey: .ticketMarkScale) ?? ticketMarkScale
        ticketTitle = try values.decodeIfPresent(String.self, forKey: .ticketTitle) ?? ticketTitle
        ticketSubtitle = try values.decodeIfPresent(String.self, forKey: .ticketSubtitle) ?? ticketSubtitle
        ticketDateMode = try values.decodeIfPresent(TicketDateMode.self, forKey: .ticketDateMode) ?? ticketDateMode
        ticketCustomDate = try values.decodeIfPresent(String.self, forKey: .ticketCustomDate) ?? ticketCustomDate
        ticketMark = try values.decodeIfPresent(TicketMark.self, forKey: .ticketMark) ?? ticketMark
        ticketStampTop = try values.decodeIfPresent(String.self, forKey: .ticketStampTop) ?? ticketStampTop
        ticketStampBottom = try values.decodeIfPresent(String.self, forKey: .ticketStampBottom) ?? ticketStampBottom
        ticketBarcodeValue = try values.decodeIfPresent(String.self, forKey: .ticketBarcodeValue) ?? ticketBarcodeValue
        classicArrangement = try values.decodeIfPresent(ClassicArrangement.self, forKey: .classicArrangement) ?? classicArrangement
        classicBrand = try values.decodeIfPresent(CameraBrand.self, forKey: .classicBrand) ?? classicBrand
        classicFooter = try values.decodeIfPresent(Double.self, forKey: .classicFooter) ?? classicFooter
        classicMargin = try values.decodeIfPresent(Double.self, forKey: .classicMargin) ?? classicMargin
        classicBrandScale = try values.decodeIfPresent(Double.self, forKey: .classicBrandScale) ?? classicBrandScale
        classicInfoScale = try values.decodeIfPresent(Double.self, forKey: .classicInfoScale) ?? classicInfoScale
        classicBrandColor = try values.decodeIfPresent(Bool.self, forKey: .classicBrandColor) ?? classicBrandColor
        classicShowCamera = try values.decodeIfPresent(Bool.self, forKey: .classicShowCamera) ?? classicShowCamera
        classicShowParameters = try values.decodeIfPresent(Bool.self, forKey: .classicShowParameters) ?? classicShowParameters
        classicShowDate = try values.decodeIfPresent(Bool.self, forKey: .classicShowDate) ?? classicShowDate
        classicShowSignature = try values.decodeIfPresent(Bool.self, forKey: .classicShowSignature) ?? classicShowSignature
        classicUseCustomLogo = try values.decodeIfPresent(Bool.self, forKey: .classicUseCustomLogo) ?? classicUseCustomLogo
        whiteText = try values.decodeIfPresent(Bool.self, forKey: .whiteText) ?? whiteText
        whiteBrand = try values.decodeIfPresent(Bool.self, forKey: .whiteBrand) ?? whiteBrand
        showBrand = try values.decodeIfPresent(Bool.self, forKey: .showBrand) ?? showBrand
        showCamera = try values.decodeIfPresent(Bool.self, forKey: .showCamera) ?? showCamera
        showParameters = try values.decodeIfPresent(Bool.self, forKey: .showParameters) ?? showParameters
        signature = try values.decodeIfPresent(String.self, forKey: .signature) ?? signature
        // A damaged or hand-edited local session must not feed extreme values into
        // font sizes, UI integer formatting or Core Graphics. Match the UI ranges.
        let limits: [(WritableKeyPath<FrameStyle, Double>, ClosedRange<Double>)] = [
            (\.margin, 0.015...0.15), (\.portraitMargin, 0.015...0.15),
            (\.topSpace, 0.025...0.15), (\.footerSpace, 0.13...0.30), (\.corner, 0...0.05),
            (\.blur, 0...0.085), (\.shadow, 0...1), (\.brightness, -0.5...0.5),
            (\.textScale, 0.65...1.5), (\.signatureScale, 0.5...2),
            (\.paletteMargin, 0...0.08), (\.paletteFooter, 0.10...0.25), (\.paletteSwatchSize, 0.03...0.095),
            (\.colorWalkHeader, 0.25...1), (\.colorWalkTextScale, 0.5...2), (\.colorWalkTextPosition, 0...1),
            (\.postageMargin, 0.035...0.19), (\.postageBorder, 0.014...0.06), (\.postagePerforation, 0.006...0.022),
            (\.postageFooter, 0.07...0.18), (\.postageBlur, 0...0.085), (\.postageBrightness, -0.5...0.5),
            (\.postageShadow, 0...1), (\.postageTextScale, 0.5...2),
            (\.ticketMargin, 0.08...0.24), (\.ticketBorder, 0.018...0.05), (\.ticketFooter, 0.13...0.30),
            (\.ticketPerforation, 0.004...0.012), (\.ticketBlur, 0...0.085), (\.ticketBrightness, -0.5...0.5),
            (\.ticketShadow, 0...1), (\.ticketTextScale, 0.5...2), (\.ticketMarkScale, 0.6...1.3),
            (\.classicFooter, 0.06...0.22), (\.classicMargin, 0...0.08),
            (\.classicBrandScale, 0.5...2), (\.classicInfoScale, 0.5...2)
        ]
        for (key, range) in limits { self[keyPath: key] = min(range.upperBound, max(range.lowerBound, self[keyPath: key])) }
        paletteCount = min(8, max(2, paletteCount))
    }

    public func sideMargin(imageWidth: Int, imageHeight: Int) -> Double {
        if template == .colorWalk { return 0 }
        if template == .classicFrame { return min(0.08, max(0, classicMargin)) }
        if template == .tickets { return TicketLayout.margin(self) + TicketLayout.border(self) }
        if template == .postageFrame { return PostageLayout.margin(self) + PostageLayout.border(self) }
        if template.isPalette { return min(0.12, max(0, paletteMargin)) }
        return min(0.15, max(0.005, imageHeight > imageWidth ? portraitMargin : margin))
    }
}

public struct FrameLayout {
    public let width: Int
    public let height: Int
    public let photoRect: CGRect
    public let titleCenterY: CGFloat
    public let parametersCenterY: CGFloat
    public let signatureCenterY: CGFloat

    public init(imageWidth: Int, imageHeight: Int, outputWidth: Int, style: FrameStyle) {
        let w = CGFloat(max(64, outputWidth))
        if style.template == .tickets {
            let ticket = TicketLayout(imageWidth: imageWidth, imageHeight: imageHeight, outputWidth: Int(w), style: style)
            self.width = ticket.width; self.height = ticket.height; self.photoRect = ticket.photoRect
            self.titleCenterY = ticket.captionRect.midY; self.parametersCenterY = ticket.captionRect.midY
            self.signatureCenterY = ticket.captionRect.midY
            return
        }
        if style.template == .classicFrame {
            let classic = ClassicLayout(imageWidth: imageWidth, imageHeight: imageHeight, outputWidth: Int(w), style: style)
            self.width = classic.width; self.height = classic.height; self.photoRect = classic.photoRect
            self.titleCenterY = classic.footerRect.midY
            self.parametersCenterY = classic.footerRect.midY
            self.signatureCenterY = classic.footerRect.midY
            return
        }
        if style.template == .postageFrame {
            let stamp = PostageLayout(imageWidth: imageWidth, imageHeight: imageHeight, outputWidth: Int(w), style: style)
            self.width = stamp.width; self.height = stamp.height
            self.photoRect = stamp.photoRect
            self.titleCenterY = stamp.captionRect.maxY - stamp.captionRect.height * 0.27
            self.parametersCenterY = stamp.captionRect.maxY - stamp.captionRect.height * 0.75
            self.signatureCenterY = stamp.captionRect.midY
            return
        }
        if style.template == .colorWalk {
            let photoH = w * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
            let header = w * CGFloat(min(1, max(0.25, style.colorWalkHeader)))
            self.width = Int(w)
            self.height = Int(ceil(photoH + header))
            self.photoRect = CGRect(x: 0, y: 0, width: w, height: photoH)
            let center = photoH + header * CGFloat(1 - min(1, max(0, style.colorWalkTextPosition)))
            self.titleCenterY = center + header * 0.06
            self.parametersCenterY = center - header * 0.07
            self.signatureCenterY = center
            return
        }
        let margin = CGFloat(style.sideMargin(imageWidth: imageWidth, imageHeight: imageHeight))
        if style.template.isPalette {
            let footer = CGFloat(min(0.28, max(0.10, style.paletteFooter)))
            let photoW = w * (1 - margin * 2)
            let photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
            self.width = Int(w)
            self.height = Int(ceil(photoH + w * (margin + footer)))
            self.photoRect = CGRect(x: w * margin, y: w * footer, width: photoW, height: photoH)
            self.titleCenterY = w * footer * 0.60
            self.parametersCenterY = w * footer * 0.22
            self.signatureCenterY = w * footer + w * 0.022
            return
        }
        let top = CGFloat(min(0.2, max(0.02, style.topSpace)))
        let footer = CGFloat(min(0.35, max(0.12, style.footerSpace)))
        let photoW = w * (1 - margin * 2)
        let photoH = photoW * CGFloat(max(1, imageHeight)) / CGFloat(max(1, imageWidth))
        let h = ceil(w * (top + footer) + photoH)
        self.width = Int(w)
        self.height = Int(h)
        // Core Graphics uses bottom-left coordinates.
        self.photoRect = CGRect(x: w * margin, y: h - w * top - photoH, width: photoW, height: photoH)
        self.titleCenterY = w * footer * 0.61
        self.parametersCenterY = w * footer * (style.signature.isEmpty ? 0.26 : 0.32)
        self.signatureCenterY = w * footer * 0.105
    }
}

public enum ExportSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case original = "原图尺寸", ultra = "3840 px", large = "2400 px", standard = "1920 px"
    public var id: String { rawValue }
    public func width(for photo: PhotoDocument, style: FrameStyle) -> Int {
        let margin = style.sideMargin(imageWidth: photo.width, imageHeight: photo.height)
        let original = Int(ceil(Double(photo.width) / (1 - margin * 2)))
        switch self {
        case .original: return original
        case .ultra: return min(3840, original)
        case .large: return min(2400, original)
        case .standard: return min(1920, original)
        }
    }
}
