import AppKit

/// Vector paper edges stay deterministic between preview and export, at any output scale.
public enum PaperEdge {
    public static func torn(rect: CGRect, depth: CGFloat, step: CGFloat) -> CGPath {
        TornPaperEdge.path(points: TornPaperEdge.points(rect: rect, depth: depth, step: step))
    }
    public static func receipt(rect: CGRect, tooth: CGFloat) -> CGPath {
        let p = CGMutablePath(), n = max(2, Int(rect.width / max(1, tooth)))
        let slot = rect.width / CGFloat(n)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tooth * 0.45))
        for i in stride(from: n - 1, through: 0, by: -1) {
            p.addLine(to: CGPoint(x: rect.minX + (CGFloat(i) + 0.5) * slot, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + CGFloat(i) * slot, y: rect.minY + tooth * 0.45))
        }
        p.closeSubpath(); return p
    }
}

extension FrameRenderer {
    func renderKeepsake(photo: PhotoDocument, metadata: PhotoMetadata, style: FrameStyle,
                        width: Int, context: CGContext, preview: Bool) throws -> CGImage {
        let l = KeepsakeLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        let w = CGFloat(l.width), r = l.photoRect, f = l.footerRect, h = l.headerRect
        let text = PrintText(context: context, style: style)
        func fill(_ rect: CGRect, _ color: NSColor) { context.setFillColor(color.cgColor); context.fill(rect) }
        let canvas = CGRect(x: 0, y: 0, width: l.width, height: l.height)
        switch style.template {
        case .cinema: fill(canvas, PaletteColor(hex: "#141514")!.color)
        case .receipt:
            fill(canvas, PaletteColor(hex: "#DCDAD3")!.color)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -w * 0.004), blur: w * 0.014, color: NSColor.black.withAlphaComponent(0.12).cgColor)
            context.addPath(PaperEdge.receipt(rect: l.cardRect, tooth: w * 0.014))
            context.setFillColor(style.receipt.paper.color.cgColor); context.fillPath(); context.restoreGState()
        case .tornPaper:
            let paper = style.tornPaper
            fill(canvas, PaletteColor(hex: "#6A655D")!.color)
            let depth = w * min(0.008, max(0.001, paper.roughness)) * 4
            let points = TornPaperEdge.points(rect: l.cardRect, depth: depth, step: w * 0.0028)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -w * 0.006), blur: w * 0.014,
                color: NSColor.black.withAlphaComponent(min(0.35, max(0, paper.shadow))).cgColor)
            context.addPath(TornPaperEdge.path(points: points))
            context.setFillColor(paper.paper.color.cgColor); context.fillPath(); context.restoreGState()
            TornPaperEdge.fibers(in: context, points: points, width: w, seed: 2187)
        default: break
        }
        if style.template == .tornPaper {
            let depth = w * min(0.008, max(0.001, style.tornPaper.roughness)) * 4
            let outer = TornPaperEdge.points(rect: l.cardRect, depth: depth, step: w * 0.0028)
            let photoEdge = TornPaperEdge.points(rect: r, depth: depth * 0.68, step: w * 0.0025, seed: 3419)
            context.saveGState()
            context.addPath(TornPaperEdge.path(points: outer)); context.clip()
            context.addPath(TornPaperEdge.path(points: photoEdge)); context.clip()
            fill(r, .white); context.draw(preview ? photo.preview : photo.image, in: r)
            context.restoreGState()
            context.saveGState(); context.addPath(TornPaperEdge.path(points: outer)); context.clip()
            TornPaperEdge.fibers(in: context, points: photoEdge, width: w, seed: 8791)
            context.restoreGState()
        } else {
            fill(r, .white); context.draw(preview ? photo.preview : photo.image, in: r)
        }
        switch style.template {
        case .cinema:
            let s = style.cinema, ink = s.ink.color, scale = CGFloat(min(1.6, max(0.65, s.textScale)))
            text.line(s.scene, rect: CGRect(x: w * 0.04, y: h.minY + h.height * 0.28, width: w * 0.65, height: h.height * 0.42),
                size: w * 0.010 * scale, ink: ink.withAlphaComponent(0.52), mono: true, tracking: w * 0.0015)
            // Reserve a separate signature row before moving the subtitle group to either endpoint.
            let hasSignature = s.showSignature && !style.signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let safeBottom = max(f.height * 0.12, hasSignature ? w * 0.035 : 0)
            let available = f.height * 0.88 - safeBottom
            let groupH = min(f.height * 0.47, available)
            let center = f.minY + safeBottom + groupH / 2
                + (available - groupH) * CGFloat(1 - min(1, max(0, s.position)))
            let groupY = center - groupH / 2
            text.line(s.subtitle, rect: CGRect(x: w * 0.065, y: groupY + groupH * 0.48, width: w * 0.87, height: groupH * 0.48),
                size: w * 0.026 * scale, ink: ink, align: 0.5)
            text.line(s.translation, rect: CGRect(x: w * 0.065, y: groupY, width: w * 0.87, height: groupH * 0.35),
                size: w * 0.015 * scale, ink: ink.withAlphaComponent(0.78), align: 0.5)
            if s.showSignature {
                text.line(style.signature, rect: CGRect(x: w * 0.70, y: w * 0.008, width: w * 0.26, height: w * 0.019),
                    size: w * 0.009 * CGFloat(style.signatureScale), ink: ink.withAlphaComponent(0.5), align: 1)
            }
        case .receipt:
            let s = style.receipt, ink = s.paper.ink, scale = CGFloat(min(1.6, max(0.65, s.textScale)))
            let secondary = ink.withAlphaComponent(0.62)
            text.line(s.title, rect: CGRect(x: h.minX, y: h.minY + h.height * 0.54, width: h.width, height: h.height * 0.28),
                size: w * 0.028 * scale, ink: ink, mono: true, align: 0.5, tracking: w * 0.001)
            text.line(s.place, rect: CGRect(x: h.minX, y: h.minY + h.height * 0.22, width: h.width, height: h.height * 0.17),
                size: w * 0.013 * scale, ink: secondary, align: 0.5)
            receiptRule(context, from: CGPoint(x: f.minX,y: f.maxY - w * 0.025), to: CGPoint(x: f.maxX,y: f.maxY - w * 0.025), w: w, ink: secondary)
            var rows = [("NO.", s.number)]
            let date = s.dateMode.text(metadata: metadata, custom: s.customDate)
            if !date.isEmpty { rows.append(("DATE", date)) }
            if !metadata.camera.isEmpty { rows.append(("CAMERA", metadata.camera)) }
            if s.showParameters && !metadata.parameterLine.isEmpty { rows.append(("EXPOSURE", metadata.parameterLine)) }
            let rowH = min(w * 0.029, f.height * 0.43 / CGFloat(max(1, rows.count)))
            for (i, row) in rows.enumerated() {
                let y = f.maxY - w * 0.048 - CGFloat(i + 1) * rowH
                text.line(row.0, rect: CGRect(x: f.minX,y: y,width: f.width * 0.21,height: rowH * 0.76), size: w * 0.011 * scale,ink:secondary,mono:true)
                text.line(row.1, rect: CGRect(x: f.minX + f.width * 0.24,y:y,width:f.width * 0.76,height:rowH * 0.76),size:w * 0.012 * scale,ink:ink,mono:true,align:1)
            }
            receiptRule(context, from: CGPoint(x:f.minX,y:f.minY+f.height * 0.29),to:CGPoint(x:f.maxX,y:f.minY+f.height * 0.29),w:w,ink:secondary)
            text.line(s.note, rect:CGRect(x:f.minX,y:f.minY+f.height * 0.14,width:f.width,height:f.height * 0.09),size:w * 0.0105 * scale,ink:secondary,mono:true,align:0.5)
            if s.showSignature {
                text.line(style.signature, rect:CGRect(x:f.minX,y:f.minY+f.height * 0.045,width:f.width,height:f.height * 0.075),
                    size:w * 0.012 * scale * CGFloat(style.signatureScale),ink:ink,align:0.5)
            }
        case .tornPaper:
            guard style.tornPaper.showCaptionArea else { break }
            let s = style.tornPaper, ink = s.paper.ink, scale = CGFloat(min(1.6, max(0.65, s.textScale)))
            text.line(s.caption, rect:CGRect(x:f.minX,y:f.minY+f.height * 0.52,width:f.width,height:f.height * 0.29),
                size:w * 0.025 * scale,ink:ink,font:s.captionFont)
            text.line(s.dateMode.text(metadata:metadata,custom:s.customDate),
                rect:CGRect(x:f.minX,y:f.minY+f.height * 0.20,width:f.width * 0.57,height:f.height * 0.16),
                size:w * 0.010 * scale,ink:ink.withAlphaComponent(0.55),mono:true)
            if s.showSignature {
                text.line(style.signature,rect:CGRect(x:f.minX+f.width * 0.63,y:f.minY+f.height * 0.18,width:f.width * 0.37,height:f.height * 0.21),
                    size:w * 0.013 * scale * CGFloat(style.signatureScale),ink:ink,align:1)
            }
        default: break
        }
        guard let image = context.makeImage() else { throw FrameError.rendering }; return image
    }

    private func receiptRule(_ context: CGContext, from: CGPoint, to: CGPoint, w: CGFloat, ink: NSColor) {
        context.saveGState(); context.setStrokeColor(ink.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(max(0.3,w * 0.0007)); context.setLineDash(phase:0,lengths:[w * 0.003,w * 0.003])
        context.move(to:from); context.addLine(to:to); context.strokePath(); context.restoreGState()
    }

}
