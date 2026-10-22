import AppKit
import CoreText

extension FrameRenderer {
    func renderWalkTicket(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                          width: Int, context: CGContext, preview: Bool, colors: [PaletteColor]) throws -> CGImage {
        let settings = style.walkTicket
        let l = WalkTicketLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: settings)
        let w = CGFloat(l.width), card = l.card, body = l.body
        let paper = settings.paperColor(photo: photo), rgb = paper.usingColorSpace(.sRGB) ?? paper
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        let ink = luminance < 0.53 ? NSColor.white : NSColor(srgbRed: 0.19, green: 0.18, blue: 0.16, alpha: 1)
        let secondary = ink.withAlphaComponent(0.58)
        context.setFillColor(NSColor(srgbRed: 0.972, green: 0.956, blue: 0.921, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: l.width, height: l.height))
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -w * 0.012), blur: w * 0.028,
                          color: NSColor.black.withAlphaComponent(min(1, max(0, settings.shadow))).cgColor)
        context.addPath(l.outline); context.setFillColor(paper.cgColor); context.fillPath()
        context.restoreGState()
        context.saveGState(); context.addPath(l.outline); context.clip()

        context.saveGState()
        context.addPath(CGPath(roundedRect: l.photoRect, cornerWidth: w * 0.012, cornerHeight: w * 0.012, transform: nil))
        context.clip(); context.setFillColor(NSColor.white.cgColor); context.fill(l.photoRect)
        let image = preview ? photo.preview : photo.image
        let factor = settings.photoMode == .fill
            ? max(l.photoSlot.width / CGFloat(image.width), l.photoSlot.height / CGFloat(image.height))
            : min(l.photoSlot.width / CGFloat(image.width), l.photoSlot.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        context.draw(image, in: CGRect(x: l.photoSlot.midX - size.width / 2, y: l.photoSlot.midY - size.height / 2,
                                      width: size.width, height: size.height))
        context.restoreGState()

        func line(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, title: Bool = false, mono: Bool = false) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let text = text.replacingOccurrences(of: "\n", with: " ")
            let value: NSAttributedString
            if mono {
                value = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), .foregroundColor: color])
            } else {
                let attributed = SignatureTypography.attributedString(text, size: size,
                    chineseFamily: style.signatureChineseFont,
                    englishFamily: title ? settings.titleFont : style.signatureEnglishFont, color: color)
                if title {
                    let copy = NSMutableAttributedString(attributedString: attributed)
                    attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { font, range, _ in
                        if let font = font as? NSFont {
                            copy.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask]), range: range)
                        }
                    }
                    value = copy
                } else { value = attributed }
            }
            let textLine = CTLineCreateWithAttributedString(value)
            let bounds = CTLineGetBoundsWithOptions(textLine, [.useGlyphPathBounds])
            guard bounds.width > 0, bounds.height > 0 else { return }
            let fit = min(1, rect.width / bounds.width, rect.height * 0.94 / bounds.height)
            context.saveGState(); context.clip(to: rect)
            context.translateBy(x: rect.minX, y: rect.midY); context.scaleBy(x: fit, y: fit)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: -bounds.minX, y: -bounds.midY)
            CTLineDraw(textLine, context); context.restoreGState()
        }
        func textBox(_ center: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: body.minX, y: card.minY + card.height * (center - height / 2), width: body.width, height: card.height * height)
        }
        let scale = CGFloat(min(2, max(0.5, settings.textScale)))
        line(settings.heading, in: textBox(0.90, 0.07), size: w * 0.021 * scale, color: ink)
        line(settings.title, in: textBox(0.74, 0.21), size: w * 0.067 * scale, color: ink, title: true)
        line(settings.subtitle, in: textBox(0.56, 0.10), size: w * 0.027 * scale, color: ink)
        line(settings.dateMode.text(metadata: metadata, custom: settings.customDate), in: textBox(0.44, 0.055), size: w * 0.016 * scale, color: secondary, mono: true)
        line(settings.notes, in: textBox(0.375, 0.055), size: w * 0.014 * scale, color: secondary)

        let palette = Array(colors.prefix(8))
        if settings.showPalette && !palette.isEmpty {
            let slots = body.width / CGFloat(palette.count)
            let size = min(w * 0.048, slots * 0.80, card.height * 0.14)
            for (index, color) in palette.enumerated() {
                let x = body.minX + CGFloat(index) * slots
                let rect = CGRect(x: x, y: card.minY + card.height * 0.19, width: size, height: size)
                context.addPath(CGPath(roundedRect: rect, cornerWidth: w * 0.006, cornerHeight: w * 0.006, transform: nil))
                context.setFillColor(color.color.cgColor); context.fillPath()
                context.addPath(CGPath(roundedRect: rect, cornerWidth: w * 0.006, cornerHeight: w * 0.006, transform: nil))
                context.setStrokeColor(ink.withAlphaComponent(0.15).cgColor); context.setLineWidth(max(0.4, w * 0.0006)); context.strokePath()
                if settings.showHex {
                    line(color.hex, in: CGRect(x: x, y: rect.minY - w * 0.016, width: slots * 0.94, height: w * 0.012), size: w * 0.009, color: secondary, mono: true)
                }
            }
            line("COLOR CARD · \(palette.count) TONES", in: textBox(0.10, 0.035), size: w * 0.011, color: secondary, mono: true)
            for (index, color) in palette.enumerated() {
                context.setFillColor(color.color.cgColor)
                let slot = l.ribbonRect.width / CGFloat(palette.count)
                context.fill(CGRect(x: l.ribbonRect.minX + CGFloat(index) * slot, y: l.ribbonRect.minY,
                                    width: slot * 0.92, height: l.ribbonRect.height))
            }
        }

        context.setFillColor(ink.withAlphaComponent(0.43).cgColor)
        let dot = w * 0.0034, first = card.minY + l.notch * 1.6, last = card.maxY - l.notch * 1.6
        let count = max(2, Int((last - first) / (dot * 3.2)))
        for i in 0...count {
            let y = first + (last - first) * CGFloat(i) / CGFloat(count)
            context.fillEllipse(in: CGRect(x: l.separatorX - dot, y: y - dot, width: dot * 2, height: dot * 2))
        }
        context.saveGState()
        context.translateBy(x: l.stub.minX + l.stub.width * 0.27, y: l.stub.midY)
        context.rotate(by: .pi / 2)
        line(settings.admission, in: CGRect(x: -card.height * 0.35, y: -w * 0.012, width: card.height * 0.70, height: w * 0.024), size: w * 0.013, color: secondary, mono: true)
        context.restoreGState()

        if settings.showBarcode {
            // A fixed, decorative rhythm in the same ink as the ticket captions.
            // It carries no payload and has no barcode backing plate.
            let lengths: [CGFloat] = [0.61, 0.82, 0.91, 0.72, 0.56, 0.44, 0.55, 0.75,
                0.92, 0.98, 0.85, 0.68, 0.50, 0.44, 0.59, 0.79, 0.95, 0.99,
                0.86, 0.69, 0.51, 0.43, 0.53, 0.74, 0.92, 0.97, 0.85, 0.66,
                0.48, 0.42, 0.58, 0.78, 0.92, 0.81, 0.63, 0.47]
            context.saveGState(); context.clip(to: l.barcodeRect)
            context.setStrokeColor(secondary.cgColor)
            context.setLineWidth(max(0.5, w * 0.0016)); context.setLineCap(.butt)
            for (index, length) in lengths.enumerated() {
                let y = l.barcodeRect.maxY - l.barcodeRect.height * (CGFloat(index) + 0.5) / CGFloat(lengths.count)
                context.move(to: CGPoint(x: l.barcodeRect.minX, y: y))
                context.addLine(to: CGPoint(x: l.barcodeRect.minX + l.barcodeRect.width * length, y: y))
            }
            context.strokePath(); context.restoreGState()
        }
        line(settings.stubCaption, in: CGRect(x: l.barcodeRect.minX - w * 0.005, y: card.minY + card.height * 0.018,
            width: l.stub.maxX - l.barcodeRect.minX - w * 0.015, height: card.height * 0.045), size: w * 0.0105, color: secondary, mono: true)
        context.restoreGState()
        guard let image = context.makeImage() else { throw FrameError.rendering }
        return image
    }
}
