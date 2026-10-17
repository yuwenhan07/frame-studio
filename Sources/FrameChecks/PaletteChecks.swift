import AppKit
import FrameCore

func runPaletteChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                      portrait: PhotoDocument, renderer: FrameRenderer) throws {
    let parsed = PaletteColor(hex: " #aBc123 ")
    check(parsed?.hex == "#ABC123" && parsed?.red == 171 && parsed?.green == 193 && parsed?.blue == 35,
          "手动 HEX 解析后 RGB 与大写色号一致")
    check(["12345", "GGGGGG", "FF112233", "+12345", "-12345", ""].allSatisfy { PaletteColor(hex: $0) == nil },
          "拒绝不完整、非法或带透明度的 HEX 输入")
    let colors = photo.palette.colors(count: 4)
    check(Set(colors.map(\.hex)) == ["#F01E14", "#14DC28", "#1432F0", "#F5DC14"],
          "四个已知色块的主色提取与独立 HEX 预期一致")
    check(colors.allSatisfy { abs($0.fraction - 0.25) < 0.000001 }, "四等分图像的颜色面积各占 25%")
    check(colors.map(\.hex) == ["#1432F0", "#F01E14", "#14DC28", "#F5DC14"], "颜色按明暗稳定排序")
    check(photo.palette.colors(count: 4) == colors, "重复取色完全一致，无随机变化")
    check(photo.palette.colors(count: 8).count == 4, "颜色不足时保留真实数量，不重复填充色块")
    let yellow = fixture(width: 1, height: 1)
    check(PhotoPalette(image: yellow).colors(count: 5).map(\.hex) == ["#F5DC14"], "单色图片只产生一个准确主色")
    let weightedData = Data([UInt8](arrayLiteral: 255,0,0,255, 255,0,0,255, 255,0,0,255, 0,0,255,255)) as CFData
    let weighted = CGImage(width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: weightedData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let weightedColors = PhotoPalette(image: weighted).colors(count: 2, order: .dominance)
    check(weightedColors.map(\.hex) == ["#FF0000", "#0000FF"]
          && abs(weightedColors[0].fraction - 0.75) < 0.000001, "面积排序正确识别 75% 红色与 25% 蓝色")
    let clearData = Data([UInt8](repeating: 0, count: 4)) as CFData
    let clear = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: clearData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    check(PhotoPalette(image: clear).colors(count: 5).first?.hex == "#FFFFFF", "透明图片按实际白底取色")

    var style = FrameStyle()
    style.template = .colorCircles
    style.paletteCount = 4
    let layout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(layout.height == 820 && layout.photoRect == CGRect(x: 20, y: 160, width: 960, height: 640),
          "横版色卡独立预期：2% 白边、16% 底栏、完整照片比例")
    let portraitLayout = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style)
    check(portraitLayout.height == 1620 && portraitLayout.photoRect.height == 1440,
          "竖版色卡不裁切照片，按比例增加画布高度")
    check(ExportSize.original.width(for: photo, style: style) == 625, "色卡原图尺寸导出保留 600 像素主照片")
    let circle = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    for (index, expected) in [[20,50,240], [240,30,20], [20,220,40], [245,220,20]].enumerated() {
        let pixel = sample(circle, x: 140 + 240 * index, y: 722)
        check(zip(pixel, expected).allSatisfy { abs($0 - $1) <= 1 }, "第 \(index + 1) 个色块中心像素与 HEX 色号一致")
    }
    let white = sample(circle, x: 178, y: 722)
    check(white.allSatisfy { $0 > 250 }, "圆形色块外侧保留白底")
    style.template = .colorSquares
    let diamond = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(sample(diamond, x: 178, y: 722)[2] > 230 && sample(diamond, x: 178, y: 722)[0] < 40,
          "菱形色块按 45 度旋转绘制，区别于圆形")
    style.paletteDiamond = false
    let square = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(sample(square, x: 170, y: 697)[0] < 40, "关闭旋转后显示方形色块")
    style.paletteMargin = 0
    let borderless = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(borderless.photoRect.minX == 0 && borderless.photoRect.width == 1000, "无白边模式将照片完整铺到左右边缘")
    style.paletteCount = 2; style.paletteShowHex = false; style.paletteFooter = 0.21
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(restored == style,
          "颜色模板、数量、形状与白边等设置可完整保存恢复")
    let old = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"softFrame","signature":"Saved","margin":0.04}"#.utf8))
    check(old.template == .softFrame && old.margin == 0.04 && old.signature == "Saved" && old.paletteCount == 5,
          "颜色模板新增字段不破坏旧版画框和落款设置")

    let yellowURL = folder.appendingPathComponent("palette-yellow.png")
    try ImageWriter.save(yellow, to: yellowURL, format: .png)
    let batchFolder = folder.appendingPathComponent("palette-batch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
    style = FrameStyle(); style.template = .colorCircles; style.paletteCount = 4
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url), BatchJob(url: yellowURL)], folder: batchFolder,
        style: style, size: .original, format: .png, control: BatchControl())
    check(report.succeeded == 2 && report.failed == 0, "颜色模板复用批量导出，两张照片各自完成")
    let singleColor = try PhotoDocument(url: report.results[1].outputURL!)
    let singlePixel = sample(singleColor.image, x: singleColor.width / 2,
                             y: singleColor.height - Int(Double(singleColor.width) * 0.16 * 0.61))
    check(singlePixel[0] > 230 && singlePixel[1] > 200 && singlePixel[2] < 40,
          "批量中的单色照片独立取色，不复用上一张的颜色")
    let manualColors = [PaletteColor(hex: "#12AB34")!, PaletteColor(hex: "#AABBCC")!]
    let manual = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, palette: manualColors)
    let manualPixel = sample(manual, x: 260, y: 722)
    check(zip(manualPixel, [18,171,52]).allSatisfy { abs($0 - $1) <= 1 },
          "手动色块在实际画布中使用编辑后的 RGB")
    let empty = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, palette: [])
    check(sample(empty, x: 500, y: 722).allSatisfy { $0 > 250 }, "删除全部色块后保留空底栏，不回退为自动颜色")
    let customFolder = folder.appendingPathComponent("palette-manual-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: customFolder, withIntermediateDirectories: true)
    let customReport = BatchExporter.run(jobs: [BatchJob(url: photo.url, paletteOverride: manualColors),
        BatchJob(url: yellowURL), BatchJob(url: photo.url, paletteOverride: [])], folder: customFolder,
        style: style, size: .original, format: .png, control: BatchControl())
    check(customReport.succeeded == 3, "手动、自动、空色卡可混合批量导出")
    let manualFile = try PhotoDocument(url: customReport.results[0].outputURL!)
    let manualFilePixel = sample(manualFile.image, x: 163, y: manualFile.height - 61)
    check(zip(manualFilePixel, [18,171,52]).allSatisfy { abs($0 - $1) <= 1 }, "批量输出保留每张照片自己的手动改色")
    let emptyFile = try PhotoDocument(url: customReport.results[2].outputURL!)
    check(sample(emptyFile.image, x: emptyFile.width / 2, y: emptyFile.height - 61).allSatisfy { $0 > 250 },
          "批量输出保留已删除的色块，不重新识别填回")

    style.signature = "国家植物园 / Garden 2026 🐟"
    style.paletteCount = 2
    let circleExample = try renderer.render(photo: demo, metadata: demo.metadata, style: style, width: 1400)
    try ImageWriter.save(circleExample, to: root.appendingPathComponent("Examples/颜色水印-圆形.jpg"), format: .jpeg)
    style.template = .colorSquares; style.paletteCount = 5
    let squareExample = try renderer.render(photo: demo, metadata: demo.metadata, style: style, width: 1400)
    try ImageWriter.save(squareExample, to: root.appendingPathComponent("Examples/颜色水印-方形.jpg"), format: .jpeg)
    let portraitExample = try renderer.render(photo: portrait, metadata: portrait.metadata, style: style, width: 900)
    try ImageWriter.save(portraitExample, to: root.appendingPathComponent("Examples/颜色水印-竖版.jpg"), format: .jpeg)
    check(portraitExample.height > portraitExample.width, "实际竖版色卡预览正常导出")
}
