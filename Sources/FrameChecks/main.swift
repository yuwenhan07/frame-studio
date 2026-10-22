import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
import FrameCore

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    passed += 1
    print("PASS: \(message)")
}

func fixture(width: Int, height: Int) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    let colors: [[UInt8]] = [[240, 30, 20], [20, 220, 40], [20, 50, 240], [245, 220, 20]]
    for y in 0..<height { for x in 0..<width {
        let c = colors[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
        let i = (y * width + x) * 4
        bytes[i] = c[0]; bytes[i + 1] = c[1]; bytes[i + 2] = c[2]
    } }
    let data = Data(bytes) as CFData
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func sample(_ image: CGImage, x: Int, y: Int) -> [Int] {
    let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return pixel.prefix(3).map(Int.init)
}

do {
    let args = CommandLine.arguments
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let folder = root.appendingPathComponent("Examples/checks", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = fixture(width: 600, height: 400)
    let sourceURL = folder.appendingPathComponent("fixture.png")
    try ImageWriter.save(source, to: sourceURL, format: .png)
    let photo = try PhotoDocument(url: sourceURL)
    check(photo.width == 600 && photo.height == 400, "导入保持原始像素")
    check(photo.metadata.parameterLine.isEmpty && photo.metadata.camera.isEmpty && photo.metadata.brand.isEmpty, "缺少 EXIF 时不伪造参数")
    let props: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "NIKON CORPORATION", kCGImagePropertyTIFFModel: "NIKON Z 6_2"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifFocalLength: 24.0, kCGImagePropertyExifFNumber: 22.0,
            kCGImagePropertyExifExposureTime: 1.0 / 15.0, kCGImagePropertyExifISOSpeedRatings: [200]]
    ]
    let metadata = PhotoMetadata.read(props)
    check(metadata.brand == "Nikon" && metadata.camera == "NIKON Z 6_2", "识别 EXIF 品牌与型号")
    check(metadata.parameterLine == "24.0mm  f/22.0  1/15  ISO200", "正确格式化参考图的四项参数")
    check(PhotoMetadata.formatExposure(2.5) == "2.5s" && PhotoMetadata.formatExposure(1.0 / 125) == "1/125", "长短快门格式")
    check([0, -1, Double.nan, .infinity, .leastNonzeroMagnitude, 1e-20].allSatisfy {
        PhotoMetadata.formatExposure($0).isEmpty
    }, "非法或倒数溢出的快门参数留空，不触发整数转换崩溃")
    let remote = URL(string: "https://example.invalid/photo.jpg")!
    do { _ = try PhotoDocument(url: remote); check(false, "远程图片不能进入 ImageIO") }
    catch FrameError.localFilesOnly { check(true, "导入在读取前拒绝远程 URL") }
    do { try ImageWriter.save(source, to: remote, format: .jpeg); check(false, "远程目标不能进入编码器") }
    catch FrameError.localFilesOnly { check(true, "导出在写入前拒绝远程 URL") }
    var style = FrameStyle()
    check(style.signatureChineseFont == "Microsoft YaHei" && style.signatureEnglishFont == "Microsoft YaHei",
          "个人落款中英文字体默认均为微软雅黑")
    let layout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(layout.height == 905 && layout.photoRect.width == 944 && abs(layout.photoRect.height - 629.3333) < 0.001, "横图版式比例来自独立预期值")
    let renderer = FrameRenderer()
    let rendered = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    check(rendered.width == 1000 && rendered.height == 905, "导出画布尺寸与布局一致")
    let red = sample(rendered, x: 160, y: 180)
    let green = sample(rendered, x: 800, y: 180)
    let blue = sample(rendered, x: 160, y: 600)
    check(red[0] > 200 && red[1] < 80 && green[1] > 180 && blue[2] > 200, "主照片方向正确且四角内容完整")
    for format in ExportFormat.allCases {
        let url = folder.appendingPathComponent("render.\(format.fileExtension)")
        try ImageWriter.save(rendered, to: url, format: format)
        let reloaded = try PhotoDocument(url: url)
        check(reloaded.width == 1000 && reloaded.height == 905, "\(format.rawValue) 导出后可重新读取且尺寸正确")
        let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let outputProps = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        check(outputProps[kCGImagePropertyGPSDictionary] == nil, "\(format.rawValue) 输出不携带定位信息")
    }
    let orientedURL = folder.appendingPathComponent("portrait-orientation.jpg")
    let destination = CGImageDestinationCreateWithURL(orientedURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var rotationProps = props
    rotationProps[kCGImagePropertyOrientation] = 6
    rotationProps[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 10.0,
        kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 20.0,
        kCGImagePropertyGPSLongitudeRef: "E"]
    var privateExif = props[kCGImagePropertyExifDictionary] as! [CFString: Any]
    privateExif[kCGImagePropertyExifBodySerialNumber] = "TEST-SERIAL-ONLY"
    privateExif[kCGImagePropertyExifDateTimeOriginal] = "2026:01:01 12:00:00"
    rotationProps[kCGImagePropertyExifDictionary] = privateExif
    CGImageDestinationAddImage(destination, source, rotationProps as CFDictionary)
    check(CGImageDestinationFinalize(destination), "写入带方向与 EXIF 的独立夹具")
    let portrait = try PhotoDocument(url: orientedURL)
    check(portrait.width == 400 && portrait.height == 600, "自动应用 EXIF 90° 旋转")
    check(portrait.metadata.iso == "200" && portrait.metadata.shutter == "1/15", "从真实图像文件读取 EXIF")
    let taggedSource = CGImageSourceCreateWithURL(orientedURL as CFURL, nil)!
    let taggedProps = CGImageSourceCopyPropertiesAtIndex(taggedSource, 0, nil) as! [CFString: Any]
    check(taggedProps[kCGImagePropertyGPSDictionary] != nil,
          "隐私回归夹具确实含有测试 GPS 元数据")
    for format in ExportFormat.allCases {
        let cleanURL = folder.appendingPathComponent("privacy-clean.\(format.fileExtension)")
        try ImageWriter.save(portrait.image, to: cleanURL, format: format)
        let cleanSource = CGImageSourceCreateWithURL(cleanURL as CFURL, nil)!
        let cleanProps = CGImageSourceCopyPropertiesAtIndex(cleanSource, 0, nil) as! [CFString: Any]
        let cleanExif = cleanProps[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        check(cleanProps[kCGImagePropertyGPSDictionary] == nil
              && cleanExif[kCGImagePropertyExifBodySerialNumber] == nil
              && cleanExif[kCGImagePropertyExifDateTimeOriginal] == nil,
              "\(format.rawValue) 不复制源图 GPS、机身序列号与原始拍摄时间")
    }
    let corner = sample(portrait.image, x: 20, y: 20)
    check(corner[2] > 200 && corner[0] < 80, "旋转后的像素方向符合顺时针独立预期")
    let portraitRender = try renderer.render(photo: portrait, metadata: portrait.metadata, style: style, width: 1000)
    check(portraitRender.width == 1000 && portraitRender.height == 1535, "竖图加宽留白后仍保持完整比例")
    let portraitLayout = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style)
    check(portraitLayout.photoRect.minX == 80 && portraitLayout.photoRect.width == 840,
          "竖图左右各留 8%，照片占画布宽度 84%")
    check(ExportSize.original.width(for: portrait, style: style) == 477, "竖图原图尺寸导出按新留白保留照片像素")
    var customMargin = style
    customMargin.portraitMargin = 0.1
    let customPortrait = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: customMargin)
    let unchangedLandscape = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: customMargin)
    check(customPortrait.photoRect.minX == 100 && unchangedLandscape.photoRect == layout.photoRect,
          "竖图手动留白不改变横图构图")
    let square = FrameLayout(imageWidth: 600, imageHeight: 600, outputWidth: 1000, style: customMargin)
    check(square.photoRect.minX == 28, "方图沿用原来的左右留白")
    let legacyData = Data(#"{"margin":0.04,"blur":0.05,"signature":"🐟 / 国家植物园","whiteText":false}"#.utf8)
    let migrated = try JSONDecoder().decode(FrameStyle.self, from: legacyData)
    check(migrated.portraitMargin == 0.08 && migrated.margin == 0.04 && migrated.blur == 0.05
          && migrated.signature == "🐟 / 国家植物园" && migrated.signatureScale == 1 && !migrated.whiteText, "旧版设置迁移保留落款及已有样式")
    let legacyScaled = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"textScale":1.4,"signature":"Saved signature"}"#.utf8))
    check(legacyScaled.signatureScale == 1.4 && legacyScaled.textScale == 1.4,
          "旧版落款继承原文字缩放，升级后大小不变")
    check(legacyScaled.signatureChineseFont == "Microsoft YaHei" && legacyScaled.signatureEnglishFont == "Microsoft YaHei",
          "旧版样式升级默认使用中英文微软雅黑")
    let extremeSaved = try JSONDecoder().decode(FrameStyle.self,
        from: Data(#"{"blur":1e300,"corner":-1e300,"shadow":5,"textScale":1e300,"signatureScale":-2,"paletteCount":999,"colorWalkTextPosition":8}"#.utf8))
    check(extremeSaved.blur == 0.085 && extremeSaved.corner == 0 && extremeSaved.shadow == 1
          && extremeSaved.textScale == 1.5 && extremeSaved.signatureScale == 0.5
          && extremeSaved.paletteCount == 8 && extremeSaved.colorWalkTextPosition == 1,
          "异常会话数值约束到界面范围，避免整数显示和字体绘制溢出")
    customMargin.signatureScale = 1.75
    customMargin.signatureChineseFont = "PingFang SC"
    customMargin.signatureEnglishFont = "Courier"
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(customMargin))
    check(restored == customMargin, "竖图留白、落款字号与中英文字体保存后可完整恢复")
    let mixedText = "国家植物园，Garden 2026 / © 🐟👨‍👩‍👧‍👦 e\u{301} 𠮷"
    let mixed = SignatureTypography.attributedString(mixedText, size: 24,
        chineseFamily: "PingFang SC", englishFamily: "Courier", color: .white)
    func assignedFamily(_ substring: String) -> String? {
        let index = (mixedText as NSString).range(of: substring).location
        return (mixed.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.familyName
    }
    check(["国家植物园", "，", "𠮷"].allSatisfy { assignedFamily($0) == "PingFang SC" }
          && ["Garden", "2026", "/", "©", "e\u{301}"].allSatisfy { assignedFamily($0) == "Courier" },
          "中英混排按字符使用对应字体，覆盖数字、全角标点与扩展汉字")
    check(mixed.string == mixedText && mixed.length == (mixedText as NSString).length,
          "Emoji、家庭组合表情与组合重音字符保持完整")
    let runs = CTLineGetGlyphRuns(CTLineCreateWithAttributedString(mixed)) as! [CTRun]
    let emojiRange = (mixedText as NSString).range(of: "🐟")
    let emojiRuns = runs.filter {
        let range = CTRunGetStringRange($0)
        return NSIntersectionRange(NSRange(location: range.location, length: range.length), emojiRange).length > 0
    }
    check(emojiRuns.contains {
        let attributes = CTRunGetAttributes($0) as NSDictionary
        let font = attributes[kCTFontAttributeName] as! CTFont
        return (CTFontCopyPostScriptName(font) as String).contains("Emoji") && CTRunGetGlyphCount($0) > 0
    }, "Core Text 为落款中的表情使用 Emoji 字体补全")
    let fallback = SignatureTypography.attributedString("中文 English", size: 24,
        chineseFamily: "Unavailable-Font-For-Check", englishFamily: "Unavailable-Font-For-Check", color: .white)
    check((fallback.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == "PingFang SC"
          && fallback.attribute(.font, at: 3, effectiveRange: nil) is NSFont,
          "所选字体缺失时使用可绘制的系统字体")
    var fontStyle = FrameStyle()
    fontStyle.signature = "国家植物园"
    fontStyle.signatureChineseFont = "PingFang SC"
    fontStyle.signatureEnglishFont = "Courier"
    let chinesePixels = try renderer.render(photo: photo, metadata: metadata, style: fontStyle, width: 1000).dataProvider!.data! as Data
    fontStyle.signatureEnglishFont = "Times New Roman"
    let unchangedChinese = try renderer.render(photo: photo, metadata: metadata, style: fontStyle, width: 1000).dataProvider!.data! as Data
    check(chinesePixels == unchangedChinese, "只改英文字体不改变纯中文落款的实际输出")
    fontStyle.signature = "Garden 2026"
    let englishPixels = try renderer.render(photo: photo, metadata: metadata, style: fontStyle, width: 1000).dataProvider!.data! as Data
    fontStyle.signatureEnglishFont = "Courier"
    let changedEnglish = try renderer.render(photo: photo, metadata: metadata, style: fontStyle, width: 1000).dataProvider!.data! as Data
    check(englishPixels != changedEnglish, "英文字体选择改变实际导出像素")
    let batchFolder = folder.appendingPathComponent("batch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
    let existingURL = batchFolder.appendingPathComponent("fixture-映框.png")
    let existingData = Data("KEEP EXISTING USER FILE".utf8)
    try existingData.write(to: existingURL)
    let jobs = [BatchJob(url: sourceURL), BatchJob(url: orientedURL),
                BatchJob(url: root.appendingPathComponent("Package.swift")), BatchJob(url: sourceURL, metadataOverride: metadata)]
    let report = BatchExporter.run(jobs: jobs, folder: batchFolder, style: FrameStyle(),
                                   size: .standard, format: .png, control: BatchControl())
    check(report.succeeded == 3 && report.failed == 1 && report.remaining == 0,
          "混合横竖批量导出逐张处理，坏文件不阻断后续照片")
    let preserved = try Data(contentsOf: existingURL)
    check(preserved == existingData, "批量导出保留已有同名文件的原始内容")
    let exportedURLs = report.results.compactMap { $0.outputURL }
    check(Set(exportedURLs).count == 3 && exportedURLs[0].lastPathComponent == "fixture-映框-2.png"
          && exportedURLs[2].lastPathComponent == "fixture-映框-3.png", "同名照片与已有文件冲突时自动编号")
    let batchPortrait = try PhotoDocument(url: exportedURLs[1])
    check(batchPortrait.width == 477 && batchPortrait.height == 733, "批量竖图自动应用 8% 留白并保留主图像素")
    let failedItems = report.results.filter { $0.error != nil }
    check(failedItems.count == 1 && failedItems[0].sourceURL.lastPathComponent == "Package.swift", "失败结果可追溯到具体输入文件")
    let stopped = BatchControl()
    stopped.cancel()
    let cancelled = BatchExporter.run(jobs: jobs, folder: batchFolder, style: FrameStyle(), size: .standard,
                                      format: .jpeg, control: stopped)
    check(cancelled.results.isEmpty && cancelled.remaining == 4, "批量预取消不生成文件，正确记录未处理数量")
    let midStop = BatchControl()
    let partial = BatchExporter.run(jobs: jobs, folder: batchFolder, style: FrameStyle(), size: .standard,
        format: .jpeg, control: midStop, didFinish: { _, _ in midStop.cancel() })
    check(partial.succeeded == 1 && partial.remaining == 3, "中途取消在当前照片完成后停止")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: batchFolder.path)
    check(!leftovers.contains(where: { $0.hasPrefix(".yingkuang-") }), "批量完成和失败后不残留中间文件")
    try ImageWriter.save(portraitRender, to: folder.appendingPathComponent("portrait.png"), format: .png)
    // A plain portrait crop of our bundled landscape photo makes the spacing change easy to inspect.
    // Do not reuse the user's already-watermarked portrait reference as a fresh source photo.
    let demo = try PhotoDocument(url: root.appendingPathComponent("Assets/Sample.jpg"))
    let cropWidth = Int(Double(demo.height) * 2 / 3)
    let crop = demo.image.cropping(to: CGRect(x: (demo.width - cropWidth) / 2, y: 0, width: cropWidth, height: demo.height))!
    let cropURL = folder.appendingPathComponent("portrait-photo.jpg")
    try ImageWriter.save(crop, to: cropURL, format: .jpeg)
    let portraitDemo = try PhotoDocument(url: cropURL)
    try runPaletteChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runColorWalkChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runColorWalkStripeChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runPostageChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runClassicChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runTicketChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runWalkTicketChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runKeepsakeChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    try runPrintTemplateChecks(root: root, folder: folder, photo: photo, demo: demo, portrait: portraitDemo, renderer: renderer)
    let portraitSample = try renderer.render(photo: portraitDemo, metadata: metadata, style: style, width: 1200)
    try ImageWriter.save(portraitSample, to: root.appendingPathComponent("Examples/竖版留白-预览.jpg"), format: .jpeg)
    let noText = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: style, width: 400)
    check(noText.width == 400, "空品牌、空型号、空参数正常渲染")
    style.signature = "© 映框 / 2026"
    style.textScale = 1.5
    style.corner = 0
    var long = metadata
    long.camera = String(repeating: "Very long 相机型号 ", count: 12)
    let custom = try renderer.render(photo: photo, metadata: long, style: style, width: 600, logo: source)
    try ImageWriter.save(custom, to: folder.appendingPathComponent("custom-logo-long-text.png"), format: .png)
    check(custom.width == 600, "自定义 Logo、长文字、中文落款可渲染")
    do {
        _ = try PhotoDocument(url: root.appendingPathComponent("Package.swift"))
        check(false, "拒绝非图片")
    } catch { check(true, "非图片文件返回可处理错误") }
    if let i = args.firstIndex(of: "--input"), i + 1 < args.count {
        let reference = try PhotoDocument(url: URL(fileURLWithPath: args[i + 1]))
        let sample = try renderer.render(photo: reference, metadata: metadata, style: FrameStyle(), width: 1920)
        try ImageWriter.save(sample, to: root.appendingPathComponent("Examples/柔焦画框-预览.jpg"), format: .jpeg)
        if args.contains("--full") {
            let w = ExportSize.original.width(for: reference, style: FrameStyle())
            let full = try renderer.render(photo: reference, metadata: metadata, style: FrameStyle(), width: w)
            try ImageWriter.save(full, to: root.appendingPathComponent("Examples/柔焦画框-原图尺寸.jpg"), format: .jpeg)
            check(full.width == 6407 && full.height == 5787, "6048×4024 参考图的原图尺寸导出")
        }
    }
    print("\n\(passed) checks passed.")
} catch { fputs("ERROR: \(error)\n", stderr); exit(1) }
