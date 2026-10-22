import AppKit
import FrameCore

func runColorWalkStripeChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                              portrait: PhotoDocument, renderer: FrameRenderer) throws {
    var style = FrameStyle(); style.template = .colorWalk
    style.colorWalkBackground = .horizontalStripes; style.colorWalkStripeCount = 3
    style.colorWalkHeader = 0.6; style.colorWalkShowStamp = false
    let colors = [PaletteColor(hex: "#204060", fraction: 0.8)!, PaletteColor(hex: "#90A0B0", fraction: 0.15)!,
                  PaletteColor(hex: "#E1BB88", fraction: 0.05)!]
    let image = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, palette: colors)
    check(image.width == 900 && image.height == 1140, "横向主色条纹沿用 Color Walk 的完整照片与色面布局")
    check(sample(image, x: 10, y: 0) == [32,64,96] && sample(image, x: 890, y: 179) == [32,64,96]
        && sample(image, x: 10, y: 180) == [144,160,176] && sample(image, x: 890, y: 359) == [144,160,176]
        && sample(image, x: 10, y: 360) == [225,187,136] && sample(image, x: 890, y: 539) == [225,187,136],
        "三个颜色按列表从上到下等高横贯色面，面积占比不影响条纹高度")
    check(sample(image, x: 50, y: 600)[0] > 220 && sample(image, x: 850, y: 600)[1] > 200
        && sample(image, x: 50, y: 1080)[2] > 220, "条纹不覆盖照片，照片方向与四角内容保持完整")
    let one = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, palette: [colors[1]])
    check(sample(one, x: 10, y: 0) == [144,160,176] && sample(one, x: 890, y: 539) == [144,160,176],
        "只剩一个颜色时自然铺满色面，不虚构其他条纹")
    let empty = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, palette: [])
    check(sample(empty, x: 10, y: 0) == [255,255,255] && sample(empty, x: 890, y: 539) == [255,255,255],
        "手动删空所有条纹后色面留白，不重新取色或套回纯色主色")
    var fractional = style; fractional.colorWalkHeader = 0.587
    let odd = try renderer.render(photo: photo, metadata: photo.metadata, style: fractional, width: 901, palette: colors)
    let rows = (0..<529).map { sample(odd, x: 5, y: $0) }
    check(rows.allSatisfy { [[32,64,96],[144,160,176],[225,187,136]].contains($0) },
        "奇数像素宽度与非整数色面高度没有白色接缝或中间杂色")
    let preview = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, preview: true, palette: colors)
    check((preview.dataProvider!.data! as Data) == (image.dataProvider!.data! as Data),
        "相同像素来源下预览与导出的横向条纹完全一致")
    style.colorWalkBackground = .solid
    let solid = PaletteColor(hex: "#456789")!
    let before = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, colorWalkColor: solid)
    let withPalette = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, palette: colors, colorWalkColor: solid)
    check((before.dataProvider!.data! as Data) == (withPalette.dataProvider!.data! as Data)
        && sample(withPalette, x: 10, y: 0) == [69,103,137], "切回纯色后仍使用独立主色，多色色卡不改变纯色输出")
    check(style.activePaletteCount == 5, "纯色模式保留既有色卡数量设置")

    style.colorWalkBackground = .horizontalStripes; style.colorWalkStripeCount = 2
    style.colorWalkShowStamp = true; style.colorWalkInk = .automatic
    style.colorWalkDetail = .custom; style.colorWalkCustomDetail = "KEEP TRYING"
    let contrasted = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900,
        palette: [PaletteColor(hex: "#FFFFFF")!, PaletteColor(hex: "#000000")!])
    var upperDarkInk = 0, lowerLightInk = 0
    let bytes = contrasted.dataProvider!.data! as Data
    for y in 180..<370 { for x in 50..<850 {
        let i = y * contrasted.bytesPerRow + x * 4
        if y < 270 && bytes[i] < 80 && bytes[i + 1] < 80 && bytes[i + 2] < 80 { upperDarkInk += 1 }
        if y >= 270 && bytes[i] > 220 && bytes[i + 1] > 220 && bytes[i + 2] > 220 { lowerLightInk += 1 }
    } }
    check(upperDarkInk > 50 && lowerLightInk > 50,
        "盖章跨越黑白条纹时，自动对比分别绘制深色与浅色文字")
    style.colorWalkTextPosition = 1; style.colorWalkTextScale = 2
    style.colorWalkStamp = String(repeating: "漫步 COLOR WALK ", count: 30)
    let positioned = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 900, palette: colors)
    check(sample(positioned, x: 50, y: 600) == sample(image, x: 50, y: 600), "条纹模式的长文字与位置极值仍不进入照片")
    style.colorWalkStripeCount = 7
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(restored == style && restored.activePaletteCount == 7, "背景模式、独立条纹数量与盖章设置完整编码恢复")
    let legacy = try JSONDecoder().decode(FrameStyle.self,
        from: Data(#"{"template":"colorWalk","colorWalkStamp":"Keep","paletteCount":6}"#.utf8))
    check(legacy.colorWalkBackground == .solid && legacy.colorWalkStripeCount == 4 && legacy.colorWalkStamp == "Keep"
        && legacy.activePaletteCount == 6, "旧版 Color Walk 默认恢复纯色，不改变已有文字与色卡数量")
    let bounded = try JSONDecoder().decode(FrameStyle.self,
        from: Data(#"{"colorWalkStripeCount":200}"#.utf8))
    check(bounded.colorWalkStripeCount == 8, "损坏的条纹数量限制在安全范围")

    let uniformURL = folder.appendingPathComponent("stripes-uniform.png")
    let context = CGContext(data: nil, width: 80, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(PaletteColor(hex: "#203040")!.color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 80, height: 50))
    try ImageWriter.save(context.makeImage()!, to: uniformURL, format: .png)
    style = FrameStyle(); style.template = .colorWalk; style.colorWalkBackground = .horizontalStripes
    style.colorWalkHeader = 0.6; style.colorWalkStripeCount = 3; style.colorWalkShowStamp = false
    let batchFolder = folder.appendingPathComponent("stripe-batch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url, paletteOverride: colors, colorWalkOverride: solid),
        BatchJob(url: uniformURL), BatchJob(url: photo.url, paletteOverride: []), BatchJob(url: portrait.url, paletteOverride: [colors[1]])],
        folder: batchFolder, style: style, size: .original, format: .png, control: BatchControl())
    check(report.succeeded == 4 && report.failed == 0, "横竖条纹批量导出支持手动多色、独立自动色、删空色卡和单色")
    let images = try report.results.map { try PhotoDocument(url: $0.outputURL!).image }
    check(sample(images[0], x: 5, y: 10) == [32,64,96] && sample(images[0], x: 5, y: 130) == [144,160,176]
        && sample(images[0], x: 5, y: 250) == [225,187,136] && sample(images[1], x: 5, y: 5) == [32,48,64]
        && sample(images[2], x: 5, y: 5) == [255,255,255] && sample(images[3], x: 5, y: 5) == [144,160,176],
        "批量按各照片取色，不使用当前预览或纯色主色覆盖，删空色卡仍保持留白")

    style = FrameStyle(); style.template = .colorWalk; style.colorWalkBackground = .horizontalStripes
    style.colorWalkInk = .automatic; style.colorWalkDetail = .custom; style.colorWalkCustomDetail = "A LITTLE WALK, A LITTLE JOY"
    var metadata = PhotoMetadata(); metadata.captureDateTime = "2026:10:22 09:20:00"
    let example = try renderer.render(photo: demo, metadata: metadata, style: style, width: 1400)
    try ImageWriter.save(example, to: root.appendingPathComponent("Examples/Color-Walk-横向条纹.jpg"), format: .jpeg)
    let upright = try renderer.render(photo: portrait, metadata: metadata, style: style, width: 900)
    try ImageWriter.save(upright, to: root.appendingPathComponent("Examples/Color-Walk-条纹竖版.jpg"), format: .jpeg)
}
