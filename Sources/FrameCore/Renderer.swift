import AppKit
import CoreImage
import CoreText

public final class FrameRenderer {
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    public init() {}

    public func render(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                       width: Int, preview: Bool = false, logo: CGImage? = nil, palette: [PaletteColor]? = nil,
                       colorWalkColor: PaletteColor? = nil) throws -> CGImage {
        let layout = FrameLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        guard Double(layout.width) * Double(layout.height) <= 80_000_000 else { throw FrameError.oversized }
        guard let context = CGContext(data: nil, width: layout.width, height: layout.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw FrameError.rendering }
        context.interpolationQuality = .high
        let canvas = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        if style.template.isKeepsake {
            return try renderKeepsake(photo: photo, metadata: metadata, style: style, width: width, context: context, preview: preview)
        }
        if style.template.isPrint {
            return try renderPrint(photo: photo, metadata: metadata, style: style, width: width, context: context, preview: preview)
        }
        if style.template == .walkTicket {
            return try renderWalkTicket(photo: photo, metadata: metadata, style: style, width: width, context: context,
                preview: preview, colors: palette ?? photo.palette.colors(count: style.activePaletteCount, order: style.paletteOrder))
        }
        if style.template == .tickets {
            return try renderTicket(photo: photo, metadata: metadata, style: style, width: width, context: context, preview: preview)
        }
        if style.template == .classicFrame {
            return try renderClassic(photo: photo, metadata: metadata, style: style, width: width, context: context, preview: preview, logo: logo)
        }
        if style.template == .colorWalk {
            return try renderColorWalk(photo: photo, metadata: metadata, style: style, layout: layout,
                context: context, preview: preview, color: colorWalkColor ?? photo.palette.colorWalkColor(), palette: palette)
        }
        if style.template.isPalette {
            return try renderPalette(photo: photo, style: style, layout: layout, context: context,
                preview: preview, colors: palette ?? photo.palette.colors(count: style.paletteCount, order: style.paletteOrder))
        }
        if style.template == .postageFrame {
            return try renderPostage(photo: photo, metadata: metadata, style: style, width: width, context: context, preview: preview)
        }
        try drawBlurredBackground(photo: photo, canvas: canvas, context: context, blur: style.blur, brightness: style.brightness)
        let rect = layout.photoRect
        let radius = CGFloat(style.corner) * canvas.width
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -canvas.width * 0.004),
                          blur: canvas.width * 0.023,
                          color: NSColor.black.withAlphaComponent(style.shadow).cgColor)
        context.addPath(path)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        // Flatten transparent source images onto white inside the photograph.
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.draw(preview ? photo.preview : photo.image, in: rect)
        context.restoreGState()

        let textColor = style.whiteText ? NSColor.white : NSColor.black
        let brandColor = style.whiteBrand ? NSColor.white : NSColor.black
        let titleSize = canvas.width * 0.027 * style.textScale
        let brandSize = canvas.width * 0.036 * style.textScale
        let brandText = style.showBrand ? metadata.brand.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let cameraText = style.showCamera ? metadata.camera.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let cameraFont = NSFont(name: "HelveticaNeue-Light", size: titleSize) ?? .systemFont(ofSize: titleSize, weight: .light)
        let brandFont = NSFont(name: "HelveticaNeue-BoldItalic", size: brandSize) ?? .boldSystemFont(ofSize: brandSize)
        let brandLine = makeLine(brandText, font: brandFont, color: brandColor)
        let cameraLine = makeLine(cameraText, font: cameraFont, color: textColor)
        let usesLogo = style.showBrand && logo != nil
        let brandW: CGFloat = usesLogo ? (brandSize * 0.9 * CGFloat(logo!.width) / CGFloat(logo!.height)) : lineWidth(brandLine)
        let cameraW = lineWidth(cameraLine)
        let gap: CGFloat = brandW > 0 && cameraW > 0 ? canvas.width * 0.01 : 0
        let total = brandW + gap + cameraW
        // Fit long camera names and uploaded logos as a centered group.
        let fit = min(1, canvas.width * 0.88 / max(1, total))
        context.saveGState()
        context.translateBy(x: (canvas.width - total * fit) / 2, y: layout.titleCenterY)
        context.scaleBy(x: fit, y: fit)
        if usesLogo, let logo = logo {
            context.draw(logo, in: CGRect(x: 0, y: -brandSize * 0.45, width: brandW, height: brandSize * 0.9))
        } else { draw(brandLine, in: context, x: 0, centerY: 0) }
        draw(cameraLine, in: context, x: brandW + gap, centerY: 0)
        context.restoreGState()

        if style.showParameters {
            let font = NSFont(name: "HelveticaNeue-Light", size: canvas.width * 0.0205 * style.textScale)
                ?? .systemFont(ofSize: canvas.width * 0.0205 * style.textScale, weight: .light)
            drawCentered(metadata.parameterLine, font: font, color: textColor,
                         y: layout.parametersCenterY, width: canvas.width, in: context)
        }
        if !style.signature.isEmpty {
            let signature = SignatureTypography.attributedString(style.signature,
                size: canvas.width * 0.012 * style.signatureScale,
                chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont,
                color: textColor.withAlphaComponent(0.85))
            drawCentered(CTLineCreateWithAttributedString(signature), y: layout.signatureCenterY,
                         width: canvas.width, in: context)
        }
        guard let image = context.makeImage() else { throw FrameError.rendering }
        return image
    }

    func drawBlurredBackground(photo: PhotoDocument, canvas: CGRect, context: CGContext,
                                       blur: Double, brightness: Double) throws {
        // Limit only the already-blurred background. The foreground uses original pixels at export.
        let backgroundScale = min(1, 1800 / CGFloat(max(canvas.width, canvas.height)))
        let smallCanvas = CGRect(x: 0, y: 0, width: canvas.width * backgroundScale, height: canvas.height * backgroundScale)
        var background = CIImage(cgImage: photo.preview)
        let scale = max(smallCanvas.width / background.extent.width, smallCanvas.height / background.extent.height)
        background = background.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        background = background.transformed(by: CGAffineTransform(
            translationX: (smallCanvas.width - background.extent.width) / 2 - background.extent.minX,
            y: (smallCanvas.height - background.extent.height) / 2 - background.extent.minY))
        background = background.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: CGFloat(blur) * canvas.width * backgroundScale
        ]).cropped(to: smallCanvas)
        if let image = ci.createCGImage(background, from: smallCanvas, format: .RGBA8, colorSpace: colorSpace) {
            context.draw(image, in: canvas)
        } else { throw FrameError.rendering }
        if brightness != 0 {
            context.setFillColor((brightness > 0 ? NSColor.white : NSColor.black)
                .withAlphaComponent(abs(brightness)).cgColor)
            context.fill(canvas)
        }
    }

    private func renderPostage(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                               width: Int, context: CGContext, preview: Bool) throws -> CGImage {
        let layout = PostageLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        let w = CGFloat(layout.width)
        try drawBlurredBackground(photo: photo, canvas: CGRect(x: 0, y: 0, width: layout.width, height: layout.height),
            context: context, blur: min(0.085, max(0, style.postageBlur)), brightness: min(0.5, max(-0.5, style.postageBrightness)))
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -w * 0.008), blur: w * 0.023,
            color: NSColor.black.withAlphaComponent(min(1, max(0, style.postageShadow))).cgColor)
        context.addPath(layout.outline)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(layout.photoRect)
        context.draw(preview ? photo.preview : photo.image, in: layout.photoRect)
        if style.postageVariant == .caption {
            let rect = layout.captionRect
            let scale = CGFloat(min(2, max(0.5, style.postageTextScale)))
            func line(_ text: String, size: CGFloat, bold: Bool) -> CTLine {
                let string = SignatureTypography.attributedString(text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
                    size: size * scale, chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont,
                    color: NSColor(white: 0.20, alpha: 1))
                let attributed = NSMutableAttributedString(attributedString: string)
                if bold {
                    string.enumerateAttribute(.font, in: NSRange(location: 0, length: string.length)) { value, range, _ in
                        if let font = value as? NSFont {
                            attributed.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range)
                        }
                    }
                }
                return CTLineCreateWithAttributedString(attributed)
            }
            let title = line(style.postagePlace, size: w * 0.037, bold: true)
            let date = line(style.postageDateMode.text(metadata: metadata, custom: style.postageCustomDate), size: w * 0.027, bold: false)
            let titleH = CTLineGetBoundsWithOptions(title, [.useGlyphPathBounds]).height
            let dateH = CTLineGetBoundsWithOptions(date, [.useGlyphPathBounds]).height
            let gap: CGFloat = titleH > 0 && dateH > 0 ? w * 0.019 * scale : 0
            let totalH = titleH + dateH + gap
            let fit = min(1, rect.width * 0.94 / max(1, lineWidth(title), lineWidth(date)), rect.height * 0.82 / max(1, totalH))
            context.saveGState()
            context.clip(to: rect)
            context.translateBy(x: rect.maxX - w * 0.018, y: rect.midY)
            context.scaleBy(x: fit, y: fit)
            if titleH > 0 { draw(title, in: context, x: -lineWidth(title), centerY: totalH / 2 - titleH / 2) }
            if dateH > 0 { draw(date, in: context, x: -lineWidth(date), centerY: -totalH / 2 + dateH / 2) }
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw FrameError.rendering }
        return image
    }

    private func renderColorWalk(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle, layout: FrameLayout,
                                 context: CGContext, preview: Bool, color: PaletteColor, palette: [PaletteColor]?) throws -> CGImage {
        let w = CGFloat(layout.width)
        let striped = style.colorWalkBackground == .horizontalStripes
        let fallback = striped ? PaletteColor(hex: "#FFFFFF")! : color
        let header = CGRect(x: 0, y: layout.photoRect.maxY, width: w, height: CGFloat(layout.height) - layout.photoRect.maxY)
        let colors = striped ? Array((palette ?? photo.palette.colors(count: style.colorWalkStripeCount, order: style.paletteOrder)).prefix(8)) : []
        // Use whole-pixel interior boundaries. The final band meets the photograph exactly.
        let bands: [(rect: CGRect, color: PaletteColor)] = colors.enumerated().map { index, color in
            let top = (header.height * CGFloat(index) / CGFloat(colors.count)).rounded()
            let bottom = index == colors.count - 1 ? header.height
                : (header.height * CGFloat(index + 1) / CGFloat(colors.count)).rounded()
            return (CGRect(x: 0, y: header.maxY - bottom, width: w, height: bottom - top), color)
        }
        context.setFillColor(fallback.color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: CGFloat(layout.height)))
        context.saveGState(); context.setShouldAntialias(false)
        for band in bands { context.setFillColor(band.color.color.cgColor); context.fill(band.rect) }
        context.restoreGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(layout.photoRect)
        context.draw(preview ? photo.preview : photo.image, in: layout.photoRect)
        if style.colorWalkShowStamp {
            let ink = style.colorWalkInk.color(on: fallback)
            let scale = CGFloat(min(2, max(0.5, style.colorWalkTextScale)))
            func line(_ text: String, size: CGFloat, bold: Bool, color: NSColor) -> CTLine {
                let string = SignatureTypography.attributedString(text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
                    size: size, chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont, color: color)
                let attributed = NSMutableAttributedString(attributedString: string)
                if bold {
                    string.enumerateAttribute(.font, in: NSRange(location: 0, length: string.length)) { value, range, _ in
                        if let font = value as? NSFont {
                            attributed.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range)
                        }
                    }
                }
                return CTLineCreateWithAttributedString(attributed)
            }
            let detailText = style.colorWalkDetail.text(metadata: metadata, custom: style.colorWalkCustomDetail)
            let title = line(style.colorWalkStamp, size: w * 0.046 * scale, bold: true, color: ink)
            let detail = line(detailText, size: w * 0.036 * scale, bold: false, color: ink)
            let titleH = CTLineGetBoundsWithOptions(title, [.useGlyphPathBounds]).height
            let detailH = CTLineGetBoundsWithOptions(detail, [.useGlyphPathBounds]).height
            let gap: CGFloat = titleH > 0 && detailH > 0 ? w * 0.032 * scale : 0
            let totalH = titleH + detailH + gap
            let headerH = CGFloat(layout.height) - layout.photoRect.maxY
            let fit = min(1, w * 0.86 / max(1, lineWidth(title), lineWidth(detail)), headerH * 0.70 / max(1, totalH))
            // Move both lines together and keep the entire stamp inside the color field.
            let padding = headerH * 0.04
            let halfHeight = totalH * fit / 2
            let requestedCenter = headerH * CGFloat(1 - min(1, max(0, style.colorWalkTextPosition)))
            let center = min(headerH - padding - halfHeight, max(padding + halfHeight, requestedCenter))
            // In automatic mode, each part of a glyph follows the stripe beneath it.
            // This also handles a stamp centered exactly across a dark/light boundary.
            let inkBands = striped && style.colorWalkInk == .automatic && !bands.isEmpty
                ? bands : [(rect: header, color: fallback)]
            for band in inkBands {
                let bandInk = style.colorWalkInk.color(on: band.color)
                let titleLine = line(style.colorWalkStamp, size: w * 0.046 * scale, bold: true, color: bandInk)
                let detailLine = line(detailText, size: w * 0.036 * scale, bold: false, color: bandInk)
                context.saveGState(); context.clip(to: band.rect)
                context.translateBy(x: w / 2, y: layout.photoRect.maxY + center)
                context.scaleBy(x: fit, y: fit)
                if titleH > 0 { draw(titleLine, in: context, x: -lineWidth(titleLine) / 2, centerY: totalH / 2 - titleH / 2) }
                if detailH > 0 { draw(detailLine, in: context, x: -lineWidth(detailLine) / 2, centerY: -totalH / 2 + detailH / 2) }
                context.restoreGState()
            }
        }
        guard let image = context.makeImage() else { throw FrameError.rendering }
        return image
    }

    private func renderPalette(photo: PhotoDocument, style: FrameStyle, layout: FrameLayout,
                               context: CGContext, preview: Bool, colors: [PaletteColor]) throws -> CGImage {
        let w = CGFloat(layout.width)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: CGFloat(layout.height)))
        context.draw(preview ? photo.preview : photo.image, in: layout.photoRect)
        let footer = layout.photoRect.minY
        let slots = layout.photoRect.width / CGFloat(max(1, colors.count))
        let diamond = style.template == .colorSquares && style.paletteDiamond
        let size = min(w * min(0.1, max(0.025, style.paletteSwatchSize)), slots * (diamond ? 0.55 : 0.72), footer * (diamond ? 0.48 : 0.64))
        let centerY = footer * (style.paletteShowHex ? 0.61 : 0.5)
        for (index, color) in colors.enumerated() {
            let x = layout.photoRect.minX + slots * (CGFloat(index) + 0.5)
            context.saveGState()
            context.translateBy(x: x, y: centerY)
            if diamond { context.rotate(by: .pi / 4) }
            let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            context.setFillColor(color.color.cgColor)
            if style.template == .colorCircles { context.fillEllipse(in: rect) }
            else {
                context.addPath(CGPath(roundedRect: rect, cornerWidth: size * 0.075, cornerHeight: size * 0.075, transform: nil))
                context.fillPath()
            }
            context.restoreGState()
            if style.paletteShowHex {
                context.saveGState()
                context.translateBy(x: x - slots / 2, y: 0)
                drawCentered(color.hex, font: .monospacedSystemFont(ofSize: min(w * 0.014, slots * 0.115, footer * 0.10), weight: .regular),
                    color: NSColor(white: 0.18, alpha: 1), y: footer * 0.21, width: slots, in: context)
                context.restoreGState()
            }
        }
        if style.paletteShowSignature && !style.signature.isEmpty {
            let signature = SignatureTypography.attributedString(style.signature, size: w * 0.012 * style.signatureScale,
                chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont, color: .white)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -w * 0.001), blur: w * 0.003,
                              color: NSColor.black.withAlphaComponent(0.7).cgColor)
            drawCentered(CTLineCreateWithAttributedString(signature), y: layout.signatureCenterY, width: w, in: context)
            context.restoreGState()
        }
        guard let result = context.makeImage() else { throw FrameError.rendering }
        return result
    }

    private func makeLine(_ text: String, font: NSFont, color: NSColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    }
    private func lineWidth(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }
    private func draw(_ line: CTLine, in context: CGContext, x: CGFloat, centerY: CGFloat) {
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: centerY - bounds.midY)
        CTLineDraw(line, context)
    }
    private func drawCentered(_ text: String, font: NSFont, color: NSColor,
                              y: CGFloat, width: CGFloat, in context: CGContext) {
        drawCentered(makeLine(text, font: font, color: color), y: y, width: width, in: context)
    }
    private func drawCentered(_ line: CTLine, y: CGFloat, width: CGFloat, in context: CGContext) {
        let measured = lineWidth(line)
        let fit = min(1, width * 0.88 / max(1, measured))
        context.saveGState()
        context.translateBy(x: (width - measured * fit) / 2, y: y)
        context.scaleBy(x: fit, y: fit)
        draw(line, in: context, x: 0, centerY: 0)
        context.restoreGState()
    }
}
