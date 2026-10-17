import AppKit
import FrameCore

func runPostageChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                      portrait: PhotoDocument, renderer: FrameRenderer) throws {
    var style = FrameStyle()
    style.template = .postageFrame
    let layout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(layout.height == 755 && abs(layout.photoRect.minX - 132) < 0.001
        && abs(layout.photoRect.width - 736) < 0.001 && abs(layout.photoRect.height - 490.6667) < 0.001,
        "邮票横版独立预期：10.5% 外留白、2.7% 白边与完整原图")
    let vertical = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style)
    check(vertical.height == 1368 && vertical.photoRect.width == 736 && vertical.photoRect.height == 1104,
        "竖版邮票照片完整显示，四边保持相同宽度")
    check(ExportSize.original.width(for: photo, style: style) == 816, "邮票原图尺寸另加白边与外留白，保留主照片像素")
    let plain = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(sample(plain, x: 200, y: 200)[0] > 220 && sample(plain, x: 800, y: 200)[1] > 200
        && sample(plain, x: 200, y: 550)[2] > 220 && sample(plain, x: 800, y: 550)[0] > 220,
        "邮票主图四角像素方向正确且没有裁切")

    let solidContext = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    solidContext.setFillColor(NSColor(srgbRed: 40.0/255, green: 90.0/255, blue: 140.0/255, alpha: 1).cgColor)
    solidContext.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
    let solidURL = folder.appendingPathComponent("postage-solid.png")
    try ImageWriter.save(solidContext.makeImage()!, to: solidURL, format: .png)
    let solid = try PhotoDocument(url: solidURL)
    style.postageShadow = 0
    let perforated = try renderer.render(photo: solid, metadata: solid.metadata, style: style, width: 1000)
    func isBlue(_ p: [Int]) -> Bool { abs(p[0] - 40) <= 1 && abs(p[1] - 90) <= 1 && abs(p[2] - 140) <= 1 }
    check(isBlue(sample(perforated, x: 180, y: 108)) && isBlue(sample(perforated, x: 180, y: 647))
        && isBlue(sample(perforated, x: 108, y: 578)) && isBlue(sample(perforated, x: 892, y: 578)),
        "独立像素确认四条边的圆形齿孔露出同源背景")
    check(sample(perforated, x: 153, y: 111) == [255,255,255]
        && sample(perforated, x: 124, y: 350) == [255,255,255]
        && isBlue(sample(perforated, x: 108, y: 108)), "齿孔之间保留白色纸边，四角为内凹切口")
    let shape = PostageLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(!shape.outline.contains(CGPoint(x: 108, y: 108)) && shape.outline.contains(CGPoint(x: 125, y: 350)),
        "连续邮票轮廓包含完整纸面，阴影沿真实齿孔绘制")

    style.postageVariant = .caption
    let captionLayout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(captionLayout.height == 855 && captionLayout.photoRect.minY == 232
        && captionLayout.photoRect.width == layout.photoRect.width, "底部落款增加独立白栏，保留原照片比例和大小")
    var metadata = photo.metadata
    metadata.captureDateTime = "2026:10:11 23:50:00"
    check(PostageDateMode.captureDate.text(metadata: metadata, custom: "") == "2026/10/11",
        "邮票日期保留相机当地日期，不转换时区")
    check(PostageDateMode.captureDate.text(metadata: PhotoMetadata(), custom: "") == ""
        && PostageDateMode.custom.text(metadata: metadata, custom: "  2026.10.12  ") == "2026.10.12"
        && PostageDateMode.none.text(metadata: metadata, custom: "") == "", "缺少拍摄日期留空，自定义与隐藏日期可独立选择")
    metadata.captureDateTime = "2026:02:30 10:00:00"
    check(PostageDateMode.captureDate.text(metadata: metadata, custom: "") == "", "无效拍摄日期不会变成伪造的有效日期")
    metadata.captureDateTime = "2026:10:11 13:50:19"
    style.postageDateMode = .none
    let blank = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    style.postageDateMode = .captureDate
    style.postagePlace = "Beijing 北京"
    let caption = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    func differences(_ a: CGImage, _ b: CGImage) -> (count: Int, left: Int, top: Int, right: Int, bottom: Int) {
        func rgba(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { ptr in
                let ctx = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        let aa = rgba(a), bb = rgba(b)
        var count = 0, left = a.width, top = a.height, right = 0, bottom = 0
        for y in 0..<a.height { for x in 0..<a.width {
            let i = (y * a.width + x) * 4
            if (0..<3).contains(where: { aa[i+$0] != bb[i+$0] }) {
                count += 1; left = min(left, x); top = min(top, y); right = max(right, x); bottom = max(bottom, y)
            }
        } }
        return (count,left,top,right,bottom)
    }
    let bounds = differences(blank, caption)
    check(bounds.count > 100 && bounds.left > 350 && bounds.right <= 850 && bounds.top >= 623 && bounds.bottom < 723,
        "中英文地点和日期实际绘制在右下白栏，不遮挡照片或齿孔")
    style.postagePlace = String(repeating: "北京 Beijing ", count: 25)
    style.postageTextScale = 2
    let long = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    let longBounds = differences(blank, long)
    check(longBounds.count > 0 && longBounds.left >= 132 && longBounds.right < 868
        && longBounds.top >= 623 && longBounds.bottom < 723, "超长地点与最大字号自动适配落款底栏")
    for variant in PostageVariant.allCases {
        style.postageVariant = variant
        style.postageBorder = 0.014; style.postagePerforation = 0.022; style.postageMargin = 0.19
        let extreme = PostageLayout(imageWidth: 10000, imageHeight: 100, outputWidth: 64, style: style)
        check(extreme.outline.contains(CGPoint(x: extreme.cardRect.midX, y: extreme.cardRect.midY)),
            "\(variant.rawValue)极端全景与小尺寸下齿孔不穿过主图")
    }
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(restored == style, "邮票样式、地点日期和滑块保存后完整恢复")
    let old = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"softFrame","signature":"Keep","colorWalkTextPosition":0.5}"#.utf8))
    check(old.template == .softFrame && old.signature == "Keep" && old.postageVariant == .plain
        && old.colorWalkTextPosition == 0.5, "邮票模板升级保留已有样式和旧会话默认值")

    style = FrameStyle(); style.template = .postageFrame; style.postageVariant = .caption; style.postagePlace = "Beijing"
    let batchFolder = folder.appendingPathComponent("postage-batch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url, metadataOverride: metadata), BatchJob(url: portrait.url)],
        folder: batchFolder, style: style, size: .original, format: .png, control: BatchControl())
    check(report.succeeded == 2 && report.failed == 0, "邮票横竖混合批量导出成功，按照片分别读取日期")
    let first = try PhotoDocument(url: report.results[0].outputURL!)
    check(first.width == 816 && first.height == 698, "批量邮票实际导出包含白栏的独立预期尺寸")
    for variant in PostageVariant.allCases {
        style.postageVariant = variant
        let image = try renderer.render(photo: demo, metadata: metadata, style: style, width: 1400)
        try ImageWriter.save(image, to: root.appendingPathComponent("Examples/邮票画框-\(variant.rawValue).jpg"), format: .jpeg)
    }
    let portraitImage = try renderer.render(photo: portrait, metadata: metadata, style: style, width: 900)
    try ImageWriter.save(portraitImage, to: root.appendingPathComponent("Examples/邮票画框-竖版.jpg"), format: .jpeg)
}
