import AppKit
import CoreText

extension FrameRenderer {
    func renderClassic(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                       width: Int, context: CGContext, preview: Bool, logo: CGImage?) throws -> CGImage {
        let layout = ClassicLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        let w = CGFloat(layout.width), footer = layout.footerRect
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        context.draw(preview ? photo.preview : photo.image, in: layout.photoRect)
        let brand = style.classicBrand.resolved(metadata: metadata)
        let customLogo = style.classicUseCustomLogo ? logo : nil
        let fallback = metadata.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBrand = customLogo != nil || brand != .custom || !fallback.isEmpty
        let aspect = customLogo.map { CGFloat($0.width) / CGFloat(max(1, $0.height)) } ?? brand.markAspect
        let brandScale = CGFloat(min(2, max(0.5, style.classicBrandScale)))
        let infoScale = CGFloat(min(2, max(0.5, style.classicInfoScale)))
        let arrangement = style.classicArrangement
        let baseH: CGFloat = w * (brand == .leica ? 0.052 : (arrangement == .inline ? 0.027 : 0.035))
        let brandH = hasBrand ? min(baseH, w * 0.30 / max(0.1, aspect)) * brandScale : 0
        let brandW = brandH * aspect
        let dark = NSColor(white: 0.15, alpha: 1), gray = NSColor(white: 0.48, alpha: 1)
        func line(_ value: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> CTLine? {
            let text = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return CTLineCreateWithAttributedString(NSAttributedString(string: text,
                attributes: [.font: NSFont.systemFont(ofSize: size * infoScale, weight: weight), .foregroundColor: color]))
        }
        var infos: [CTLine] = []
        if style.classicShowCamera, let value = line(metadata.camera, size: w * 0.019, color: dark, weight: .medium) { infos.append(value) }
        if style.classicShowParameters, let value = line(metadata.parameterLine, size: w * 0.015, color: arrangement == .centered ? dark : gray) { infos.append(value) }
        if style.classicShowDate, let value = line(CameraBrand.timestamp(metadata), size: w * 0.012, color: gray) { infos.append(value) }
        if style.classicShowSignature && !style.signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = SignatureTypography.attributedString(style.signature.replacingOccurrences(of: "\n", with: " "),
                size: w * 0.012 * min(2, max(0.5, style.signatureScale)) * infoScale,
                chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont, color: gray)
            infos.append(CTLineCreateWithAttributedString(text))
        }
        func bounds(_ line: CTLine) -> CGRect { CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]) }
        func paint(_ line: CTLine, x: CGFloat, y: CGFloat, centered: Bool) {
            let box = bounds(line)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x - (centered ? box.midX : box.minX), y: y - box.midY)
            CTLineDraw(line, context)
        }
        func paintFitted(_ line: CTLine, x: CGFloat, y: CGFloat, centered: Bool, maxWidth: CGFloat) {
            let fit = min(1, maxWidth / max(1, bounds(line).width))
            context.saveGState(); context.translateBy(x: x, y: y); context.scaleBy(x: fit, y: fit)
            paint(line, x: 0, y: 0, centered: centered)
            context.restoreGState()
        }
        func paintBrand(_ rect: CGRect) {
            if let customLogo { context.draw(customLogo, in: rect) }
            else { brand.draw(in: context, rect: rect, color: style.classicBrandColor, fallback: fallback) }
        }
        context.saveGState()
        context.clip(to: footer)
        let heights = infos.map { bounds($0).height }
        let gap = w * 0.010 * infoScale
        let infoH = heights.reduce(0, +) + gap * CGFloat(max(0, infos.count - 1))
        switch arrangement {
        case .centered:
            let brandGap: CGFloat = brandH > 0 && !infos.isEmpty ? w * 0.014 : 0
            let totalH = brandH + brandGap + infoH
            let fit = min(1, footer.height * 0.80 / max(1, totalH), w * 0.90 / max(1, brandW))
            context.translateBy(x: w / 2, y: footer.midY)
            context.scaleBy(x: fit, y: fit)
            if hasBrand { paintBrand(CGRect(x: -brandW / 2, y: totalH / 2 - brandH, width: brandW, height: brandH)) }
            var top = totalH / 2 - brandH - brandGap
            for (index, value) in infos.enumerated() {
                paintFitted(value, x: 0, y: top - heights[index] / 2, centered: true, maxWidth: w * 0.90 / fit)
                top -= heights[index] + gap
            }
        case .split:
            let padding = w * 0.035
            let brandFit = min(1, footer.height * 0.74 / max(1, brandH), w * 0.28 / max(1, brandW))
            let bw = brandW * brandFit, bh = brandH * brandFit
            if hasBrand { paintBrand(CGRect(x: w - padding - bw, y: footer.midY - bh / 2, width: bw, height: bh)) }
            let available = w - padding * 2 - (hasBrand ? bw + w * 0.04 : 0)
            let fit = min(1, footer.height * 0.78 / max(1, infoH))
            context.translateBy(x: padding, y: footer.midY)
            context.scaleBy(x: fit, y: fit)
            var top = infoH / 2
            for (index, value) in infos.enumerated() {
                paintFitted(value, x: 0, y: top - heights[index] / 2, centered: false, maxWidth: available / fit)
                top -= heights[index] + gap
            }
        case .inline:
            let padding = w * 0.035
            let brandFit = min(1, footer.height * 0.74 / max(1, brandH), w * 0.22 / max(1, brandW))
            let bw = brandW * brandFit, bh = brandH * brandFit
            if hasBrand { paintBrand(CGRect(x: padding, y: footer.midY - bh / 2, width: bw, height: bh)) }
            let naturalW = infos.reduce(CGFloat(0)) { $0 + bounds($1).width } + CGFloat(max(0, infos.count - 1)) * w * 0.035
            let start = padding + (hasBrand ? bw + w * 0.04 : 0)
            let fit = min(1, (w - padding - start) / max(1, naturalW), footer.height * 0.74 / max(1, heights.max() ?? 0))
            if hasBrand && !infos.isEmpty {
                context.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
                context.fill(CGRect(x: padding + bw + w * 0.02, y: footer.midY - w * 0.018, width: max(0.5, w * 0.0007), height: w * 0.036))
            }
            context.translateBy(x: start, y: footer.midY); context.scaleBy(x: fit, y: fit)
            var x: CGFloat = 0
            for value in infos { paint(value, x: x, y: 0, centered: false); x += bounds(value).width + w * 0.035 }
        }
        context.restoreGState()
        guard let image = context.makeImage() else { throw FrameError.rendering }
        return image
    }
}
