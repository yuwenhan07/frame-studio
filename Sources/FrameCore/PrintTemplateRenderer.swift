import AppKit
import CoreText

struct PrintText {
    let context: CGContext
    let style: FrameStyle
    func line(_ text: String, rect: CGRect, size: CGFloat, ink: NSColor,
              font: String? = nil, mono: Bool = false, align: CGFloat = 0, tracking: CGFloat = 0) {
        let clean = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let value: NSMutableAttributedString
        if mono {
            value = NSMutableAttributedString(string: clean, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), .foregroundColor: ink])
        } else {
            value = NSMutableAttributedString(attributedString: SignatureTypography.attributedString(clean, size: size,
                chineseFamily: style.signatureChineseFont, englishFamily: font ?? style.signatureEnglishFont, color: ink))
        }
        if tracking != 0 { value.addAttribute(.kern, value: tracking, range: NSRange(location: 0, length: value.length)) }
        let line = CTLineCreateWithAttributedString(value)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(1, rect.width / bounds.width, rect.height * 0.90 / bounds.height)
        context.saveGState(); context.clip(to: rect)
        context.translateBy(x: rect.minX + (rect.width - bounds.width * fit) * align, y: rect.midY)
        context.scaleBy(x: fit, y: fit); context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.minX, y: -bounds.midY)
        CTLineDraw(line, context); context.restoreGState()
    }
}

extension FrameRenderer {
    func renderPrint(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                     width: Int, context: CGContext, preview: Bool) throws -> CGImage {
        let l = PrintLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        let w = CGFloat(l.width), r = l.photoRect, text = PrintText(context: context, style: style)
        func fill(_ rect: CGRect, _ color: NSColor) { context.setFillColor(color.cgColor); context.fill(rect) }
        func rule(_ from: CGPoint, _ to: CGPoint, color: NSColor, weight: CGFloat) {
            context.saveGState(); context.setStrokeColor(color.cgColor); context.setLineWidth(weight)
            context.move(to: from); context.addLine(to: to); context.strokePath(); context.restoreGState()
        }
        let canvas = CGRect(x: 0, y: 0, width: l.width, height: l.height)
        switch style.template {
        case .film35: fill(canvas, PaletteColor(hex: "#161716")!.color)
        case .gallery: fill(canvas, style.gallery.paper.color)
        case .editorial: fill(canvas, style.editorial.paper.color)
        case .instant:
            fill(canvas, PaletteColor(hex: "#EAE7E0")!.color)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -w * 0.008), blur: w * 0.021,
                color: NSColor.black.withAlphaComponent(min(0.35, max(0, style.instant.shadow))).cgColor)
            fill(l.cardRect, style.instant.paper.color); context.restoreGState()
        default: break
        }
        // Every template uses the complete oriented image, with no implicit crop or filter.
        fill(r, .white); context.draw(preview ? photo.preview : photo.image, in: r)

        switch style.template {
        case .film35:
            let s = style.film35, amber = PaletteColor(hex: "#D5A563")!.color
            let scale = CGFloat(min(1.6, max(0.65, s.textScale)))
            if s.showSprockets {
                let count = max(5, Int(r.width / (w * 0.062)))
                let slot = r.width / CGFloat(count)
                for index in 0..<count {
                    let x = r.minX + (CGFloat(index) + 0.5) * slot - w * 0.018
                    for y in [w * 0.009, CGFloat(l.height) - w * 0.022] {
                        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w * 0.036, height: w * 0.013),
                            cornerWidth: w * 0.0025, cornerHeight: w * 0.0025, transform: nil))
                        context.setFillColor(PaletteColor(hex: "#E8E3D8")!.color.cgColor); context.fillPath()
                    }
                }
            }
            context.setStrokeColor(amber.withAlphaComponent(0.32).cgColor); context.setLineWidth(w * 0.0007)
            context.stroke(r.insetBy(dx: -w * 0.003, dy: -w * 0.003))
            text.line(s.label, rect: CGRect(x: r.minX, y: r.maxY + w * 0.012, width: r.width * 0.70, height: w * 0.027),
                size: w * 0.014 * scale, ink: amber, mono: true, tracking: w * 0.0015)
            text.line(s.number.isEmpty ? "" : "\(s.number)  ▷", rect: CGRect(x: r.maxX - r.width * 0.25, y: r.maxY + w * 0.012,
                width: r.width * 0.25, height: w * 0.027), size: w * 0.014 * scale, ink: amber, mono: true, align: 1)
            let parameters = s.showParameters ? metadata.parameterLine : ""
            let signature = s.showSignature ? style.signature : ""
            let baseline = w * 0.030, lineHeight = w * 0.029
            if !parameters.isEmpty {
                text.line(parameters, rect: CGRect(x: r.minX, y: baseline,
                    width: r.width * (signature.isEmpty ? 0.65 : 0.32), height: lineHeight),
                    size: w * 0.011 * scale, ink: amber, mono: true)
            }
            if !signature.isEmpty {
                text.line(signature, rect: CGRect(x: r.minX + (parameters.isEmpty ? 0 : r.width * 0.35), y: baseline,
                    width: r.width * (parameters.isEmpty ? 0.65 : 0.30), height: lineHeight),
                    size: w * 0.011 * scale * CGFloat(min(2, max(0.5, style.signatureScale))), ink: amber)
            }
            text.line(s.dateMode.text(metadata: metadata, custom: s.customDate),
                rect: CGRect(x: r.maxX - r.width * 0.30, y: w * 0.032, width: r.width * 0.30, height: w * 0.025),
                size: w * 0.011 * scale, ink: amber, mono: true, align: 1)
        case .gallery:
            let s = style.gallery, ink = s.paper.ink, secondary = ink.withAlphaComponent(0.58)
            let scale = CGFloat(min(1.6, max(0.65, s.textScale))), f = l.footerRect
            if s.showOutline {
                context.setStrokeColor(ink.withAlphaComponent(0.30).cgColor); context.setLineWidth(w * 0.0006)
                context.stroke(r.insetBy(dx: -w * 0.005, dy: -w * 0.005))
            }
            text.line(s.title, rect: CGRect(x: f.minX, y: f.height * 0.57, width: f.width * 0.75, height: f.height * 0.24),
                size: w * 0.028 * scale, ink: ink, font: s.titleFont)
            text.line(s.subtitle, rect: CGRect(x: f.minX, y: f.height * 0.36, width: f.width * 0.75, height: f.height * 0.15),
                size: w * 0.0125 * scale, ink: secondary)
            text.line(s.dateMode.text(metadata: metadata, custom: s.customDate),
                rect: CGRect(x: f.minX, y: f.height * 0.18, width: f.width * 0.55, height: f.height * 0.13),
                size: w * 0.0105 * scale, ink: secondary, mono: true)
            if s.showSignature {
                text.line(style.signature, rect: CGRect(x: f.minX + f.width * 0.60, y: f.height * 0.18,
                    width: f.width * 0.40, height: f.height * 0.18), size: w * 0.014 * scale * CGFloat(style.signatureScale), ink: ink, align: 1)
            }
        case .editorial:
            let s = style.editorial, ink = s.paper.ink, secondary = ink.withAlphaComponent(0.60)
            let h = l.headerRect, f = l.footerRect, scale = CGFloat(min(1.6, max(0.65, s.textScale)))
            text.line("TRAVEL JOURNAL", rect: CGRect(x: h.minX, y: h.minY + h.height * 0.77, width: h.width * 0.65, height: h.height * 0.10),
                size: w * 0.010 * scale, ink: secondary, mono: true, tracking: w * 0.0011)
            text.line(s.edition, rect: CGRect(x: h.minX + h.width * 0.72, y: h.minY + h.height * 0.77,
                width: h.width * 0.28, height: h.height * 0.10), size: w * 0.010 * scale, ink: secondary, mono: true, align: 1)
            text.line(s.title, rect: CGRect(x: h.minX - w * 0.001, y: h.minY + h.height * 0.27, width: h.width, height: h.height * 0.43),
                size: w * 0.098 * scale, ink: ink, font: s.titleFont, tracking: -w * 0.0013)
            text.line(s.subtitle, rect: CGRect(x: h.minX, y: h.minY + h.height * 0.10, width: h.width, height: h.height * 0.10),
                size: w * 0.012 * scale, ink: secondary, tracking: w * 0.0005)
            if s.showAccent {
                rule(CGPoint(x: h.minX, y: r.maxY + w * 0.006), CGPoint(x: h.maxX, y: r.maxY + w * 0.006),
                    color: s.accentColor(photo: photo), weight: w * 0.0025)
            }
            text.line(s.notes, rect: CGRect(x: f.minX, y: f.height * 0.55, width: f.width * 0.72, height: f.height * 0.23),
                size: w * 0.014 * scale, ink: ink)
            text.line(s.dateMode.text(metadata: metadata, custom: s.customDate),
                rect: CGRect(x: f.minX, y: f.height * 0.25, width: f.width * 0.57, height: f.height * 0.17),
                size: w * 0.0105 * scale, ink: secondary, mono: true)
            if s.showSignature {
                text.line(style.signature, rect: CGRect(x: f.minX + f.width * 0.66, y: f.height * 0.25,
                    width: f.width * 0.34, height: f.height * 0.21), size: w * 0.013 * scale * CGFloat(style.signatureScale), ink: ink, align: 1)
            }
        case .instant:
            let s = style.instant, ink = s.paper.ink, scale = CGFloat(min(1.6, max(0.65, s.textScale)))
            let bottom = l.cardRect.minY, height = r.minY - bottom
            text.line(s.caption, rect: CGRect(x: r.minX, y: bottom + height * 0.51, width: r.width, height: height * 0.30),
                size: w * 0.032 * scale, ink: ink, font: s.captionFont, align: 0.5)
            text.line(s.dateMode.text(metadata: metadata, custom: s.customDate),
                rect: CGRect(x: r.minX, y: bottom + height * 0.18, width: r.width * 0.62, height: height * 0.17),
                size: w * 0.0105 * scale, ink: ink.withAlphaComponent(0.55), mono: true)
            if s.showSignature {
                text.line(style.signature, rect: CGRect(x: r.minX + r.width * 0.66, y: bottom + height * 0.17,
                    width: r.width * 0.34, height: height * 0.20), size: w * 0.014 * scale * CGFloat(style.signatureScale), ink: ink, align: 1)
            }
        default: break
        }
        guard let image = context.makeImage() else { throw FrameError.rendering }
        return image
    }
}
