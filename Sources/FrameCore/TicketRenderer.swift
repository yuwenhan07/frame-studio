import AppKit
import CoreText

extension FrameRenderer {
    func renderTicket(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                      width: Int, context: CGContext, preview: Bool) throws -> CGImage {
        let layout = TicketLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        let w = CGFloat(layout.width), caption = layout.captionRect
        try drawBlurredBackground(photo: photo, canvas: CGRect(x: 0, y: 0, width: layout.width, height: layout.height),
            context: context, blur: min(0.085, max(0, style.ticketBlur)), brightness: min(0.5, max(-0.5, style.ticketBrightness)))
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -w * 0.007), blur: w * 0.025,
            color: NSColor.black.withAlphaComponent(min(1, max(0, style.ticketShadow))).cgColor)
        context.addPath(layout.outline); context.setFillColor(NSColor.white.cgColor); context.fillPath()
        context.restoreGState()
        context.setFillColor(NSColor.white.cgColor); context.fill(layout.photoRect)
        context.draw(preview ? photo.preview : photo.image, in: layout.photoRect)
        context.saveGState()
        context.setStrokeColor(NSColor(white: 0.68, alpha: 0.8).cgColor)
        context.setLineWidth(max(0.6, w * 0.0013))
        context.setLineDash(phase: 0, lengths: [w * 0.006, w * 0.005])
        context.move(to: CGPoint(x: layout.cardRect.minX + layout.sideNotch * 1.5, y: layout.separatorY))
        context.addLine(to: CGPoint(x: layout.cardRect.maxX - layout.sideNotch * 1.5, y: layout.separatorY))
        context.strokePath(); context.restoreGState()

        func line(_ value: String, size: CGFloat, color: NSColor) -> CTLine {
            let text = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return CTLineCreateWithAttributedString(SignatureTypography.attributedString(text, size: size,
                chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont, color: color))
        }
        func bounds(_ value: CTLine) -> CGRect { CTLineGetBoundsWithOptions(value, [.useGlyphPathBounds]) }
        func paint(_ value: CTLine, x: CGFloat, y: CGFloat) {
            let box = bounds(value)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x - box.minX, y: y - box.midY)
            CTLineDraw(value, context)
        }
        let markWidth = style.ticketMark == .none ? 0 : caption.width * 0.48
        let textWidth = caption.width - markWidth - w * 0.012
        let scale = CGFloat(min(2, max(0.5, style.ticketTextScale)))
        let lines = [line(style.ticketTitle, size: w * 0.040 * scale, color: NSColor(white: 0.20, alpha: 1)),
                     line(style.ticketSubtitle, size: w * 0.027 * scale, color: NSColor(white: 0.42, alpha: 1)),
                     line(style.ticketDateMode.text(metadata: metadata, custom: style.ticketCustomDate),
                          size: w * 0.021 * scale, color: NSColor(white: 0.42, alpha: 1))]
            .filter { bounds($0).height > 0 }
        let gap = w * 0.014 * scale
        let total = lines.reduce(CGFloat(0)) { $0 + bounds($1).height } + CGFloat(max(0, lines.count - 1)) * gap
        let fit = min(1, caption.height * 0.84 / max(1, total), textWidth / max(1, lines.map { bounds($0).width }.max() ?? 0))
        context.saveGState(); context.clip(to: caption)
        context.translateBy(x: caption.minX + w * 0.006, y: caption.midY); context.scaleBy(x: fit, y: fit)
        var top = total / 2
        for value in lines {
            let height = bounds(value).height
            paint(value, x: 0, y: top - height / 2); top -= height + gap
        }
        context.restoreGState()

        let markBox = CGRect(x: caption.maxX - markWidth, y: caption.minY, width: markWidth, height: caption.height)
        context.saveGState(); context.clip(to: markBox)
        switch style.ticketMark {
        case .none: break
        case .stamp: drawTravelStamp(context: context, rect: markBox, width: w, style: style)
        case .barcode:
            let content = TicketBarcode.content(style.ticketBarcodeValue)
            if !content.isEmpty {
                guard let barcode = TicketBarcode.image(content) else {
                    context.restoreGState()
                    if !preview { throw FrameError.invalidBarcode }
                    guard let result = context.makeImage() else { throw FrameError.rendering }
                    return result
                }
                let scale = CGFloat(min(1.3, max(0.6, style.ticketMarkScale)))
                let bw = min(markBox.width * 0.96, w * 0.275 * scale)
                let bh = min(markBox.height * 0.48, w * 0.068 * scale)
                let rect = CGRect(x: markBox.maxX - bw, y: markBox.minY + markBox.height * 0.23, width: bw, height: bh)
                context.interpolationQuality = .none
                context.draw(barcode, in: rect)
                let label = CTLineCreateWithAttributedString(NSAttributedString(string: content, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: w * 0.012 * scale, weight: .regular),
                    .foregroundColor: NSColor(white: 0.35, alpha: 1)]))
                let labelBounds = bounds(label), labelFit = min(1, bw / max(1, labelBounds.width))
                context.saveGState()
                context.translateBy(x: rect.midX - labelBounds.width * labelFit / 2, y: rect.minY - w * 0.014)
                context.scaleBy(x: labelFit, y: labelFit); paint(label, x: 0, y: 0)
                context.restoreGState()
            }
        }
        context.restoreGState()
        guard let result = context.makeImage() else { throw FrameError.rendering }
        return result
    }

    private func drawTravelStamp(context: CGContext, rect: CGRect, width: CGFloat, style: FrameStyle) {
        let scale = CGFloat(min(1.3, max(0.6, style.ticketMarkScale)))
        let diameter = min(width * 0.17 * scale, rect.height * 0.94, rect.width / 1.65)
        let r = diameter / 2
        let center = CGPoint(x: rect.maxX - r - width * 0.004, y: rect.midY)
        let ink = NSColor(srgbRed: 0.58, green: 0.65, blue: 0.70, alpha: 0.54)
        context.saveGState(); context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -.pi / 14)
        context.setStrokeColor(ink.cgColor); context.setFillColor(ink.cgColor)
        context.setLineWidth(max(0.5, width * 0.0015))
        context.strokeEllipse(in: CGRect(x: -r, y: -r, width: diameter, height: diameter))
        context.setLineWidth(max(0.4, width * 0.0008))
        context.strokeEllipse(in: CGRect(x: -r * 0.86, y: -r * 0.86, width: diameter * 0.86, height: diameter * 0.86))
        func arcText(_ text: String, top: Bool) {
            let letters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            guard !letters.isEmpty else { return }
            let size = min(diameter * 0.105, diameter * 1.65 / CGFloat(max(1, letters.count)))
            let step = min(0.21, .pi * 0.73 / CGFloat(max(1, letters.count - 1)))
            let middle: CGFloat = top ? .pi / 2 : -.pi / 2
            for (index, character) in letters.enumerated() {
                let delta = (CGFloat(index) - CGFloat(letters.count - 1) / 2) * step
                let angle = middle + (top ? -delta : delta)
                let text = SignatureTypography.attributedString(String(character), size: size,
                    chineseFamily: style.signatureChineseFont, englishFamily: style.signatureEnglishFont, color: ink)
                let line = CTLineCreateWithAttributedString(text)
                let box = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
                context.saveGState()
                context.translateBy(x: cos(angle) * r * 0.71, y: sin(angle) * r * 0.71)
                context.rotate(by: angle + (top ? -.pi / 2 : .pi / 2))
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: -box.midX, y: -box.midY)
                CTLineDraw(line, context); context.restoreGState()
            }
        }
        arcText(style.ticketStampTop, top: true); arcText(style.ticketStampBottom, top: false)
        let plane = CGMutablePath()
        let points: [CGPoint] = [CGPoint(x: -0.55, y: -0.1), CGPoint(x: -0.08, y: -0.1), CGPoint(x: 0.06, y: -0.50),
            CGPoint(x: 0.18, y: -0.50), CGPoint(x: 0.14, y: -0.08), CGPoint(x: 0.60, y: 0),
            CGPoint(x: 0.14, y: 0.08), CGPoint(x: 0.18, y: 0.50), CGPoint(x: 0.06, y: 0.50),
            CGPoint(x: -0.08, y: 0.1), CGPoint(x: -0.55, y: 0.1), CGPoint(x: -0.67, y: 0.28),
            CGPoint(x: -0.75, y: 0.28), CGPoint(x: -0.68, y: 0), CGPoint(x: -0.75, y: -0.28), CGPoint(x: -0.67, y: -0.28)]
        plane.addLines(between: points.map { CGPoint(x: $0.x * r * 0.65, y: $0.y * r * 0.65) }); plane.closeSubpath()
        context.addPath(plane); context.fillPath()
        context.restoreGState()
        context.setStrokeColor(ink.cgColor); context.setLineWidth(max(0.5, width * 0.0014))
        for index in 0..<4 {
            let y = center.y + CGFloat(index - 2) * diameter * 0.09
            let x = max(rect.minX + width * 0.002, center.x - diameter * 1.13)
            context.move(to: CGPoint(x: x, y: y))
            context.addCurve(to: CGPoint(x: center.x - r * 0.10, y: y),
                control1: CGPoint(x: x + diameter * 0.31, y: y - diameter * 0.18),
                control2: CGPoint(x: center.x - r * 0.52, y: y + diameter * 0.18))
            context.strokePath()
        }
    }
}
