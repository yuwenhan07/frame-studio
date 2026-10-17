import AppKit
import ImageIO
import UniformTypeIdentifiers
import FrameCore

func runColorWalkChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                        portrait: PhotoDocument, renderer: FrameRenderer) throws {
    func strip(_ values: [[UInt8]]) -> CGImage {
        let bytes: [UInt8] = values.flatMap { row -> [UInt8] in row + [UInt8(255)] }
        return CGImage(width: values.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: values.count * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    func inkBounds(_ image: CGImage, headerRows: Int) -> (top: Int, bottom: Int)? {
        let bytes = image.dataProvider!.data! as Data
        var top = image.height, bottom = -1
        bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for y in 0..<min(headerRows, image.height) {
                for x in 0..<image.width {
                    let i = y * image.bytesPerRow + x * 4
                    if buffer[i] > 242 && buffer[i + 1] > 242 && buffer[i + 2] > 242 {
                        top = min(top, y); bottom = max(bottom, y)
                    }
                }
            }
        }
        return bottom >= top ? (top, bottom) : nil
    }
    let rose = [UInt8](arrayLiteral: 169,105,107)
    let neutral = [UInt8](arrayLiteral: 120,120,120)
    let blue = [UInt8](arrayLiteral: 74,154,192)
    check(PhotoPalette(image: strip([rose])).colorWalkColor().hex == "#AC7678", "自动玫瑰色按独立 HSL 预期微调，保留柔和色调")
    let shadow = Array(repeating: [UInt8](arrayLiteral: 0,0,0), count: 60) + Array(repeating: rose, count: 35)
        + Array(repeating: [UInt8](arrayLiteral: 0,255,0), count: 5)
    check(PhotoPalette(image: strip(shadow)).colorWalkColor().hex == "#AC7678", "大面积阴影和小面积鲜艳点缀不会盖过主体色调")
    check(PhotoPalette(image: strip(Array(repeating: neutral, count: 75) + Array(repeating: blue, count: 25))).colorWalkColor().hex == "#5C9FBF",
        "有足够彩色内容时从灰色背景中选择代表色")
    check(PhotoPalette(image: strip(Array(repeating: neutral, count: 95) + Array(repeating: blue, count: 5))).colorWalkColor().hex == "#818181",
        "接近黑白的照片保留中性色，不被少量彩色噪声主导")
    check(PhotoPalette(image: strip([[55,95,23]])).colorWalkColor().hex == "#40691F", "暗绿色仅轻微提亮并柔化饱和度，避免鲜亮草绿")
    check(PhotoPalette(image: strip([[0,0,255]])).colorWalkColor().hex == "#1E1EF3", "高饱和蓝色保留蓝调并适度收敛鲜艳感")
    check(PhotoPalette(image: strip([[0,0,0]])).colorWalkColor().hex == "#090909"
        && PhotoPalette(image: strip([[255,255,255]])).colorWalkColor().hex == "#FFFFFF", "黑白边界提亮结果有限且保持中性，白色不溢出")
    check(PhotoPalette(image: strip([rose])).colors(count: 1).first?.hex == "#A9696B", "提亮仅作用于 Color Walk，原始色卡取色保持不变")
    check(demo.palette.colorWalkColor() == demo.palette.colorWalkColor(), "代表色反复计算结果稳定")
    var style = FrameStyle()
    style.template = .colorWalk
    check(style.colorWalkStamp == "Stay alive · keep trying" && style.colorWalkShowStamp, "默认显示指定文字盖章")
    let layout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(layout.height == 1252 && layout.photoRect.minX == 0 && layout.photoRect.minY == 0
        && abs(layout.photoRect.height - 666.6666667) < 0.001 && layout.photoRect.width == 1000,
        "横版独立布局预期：58.5% 色面、照片满宽且比例完整")
    let upright = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style)
    check(upright.height == 2085 && upright.photoRect.height == 1500, "竖版照片保持原比例，色面放在上方")
    check(ExportSize.original.width(for: photo, style: style) == 600, "Color Walk 原图尺寸保留主照片像素")
    let override = PaletteColor(hex: "#A9696B")!
    style.colorWalkShowStamp = false
    let plain = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, colorWalkColor: override)
    check(sample(plain, x: 20, y: 20) == [169,105,107], "手动主色绘制为准确的 sRGB 色面")
    let topLeft = sample(plain, x: 50, y: 635)
    let topRight = sample(plain, x: 950, y: 635)
    let bottomLeft = sample(plain, x: 50, y: 1200)
    let bottomRight = sample(plain, x: 950, y: 1200)
    check(topLeft[0] > 220 && topLeft[1] < 60 && topRight[1] > 200
        && bottomLeft[2] > 220 && bottomRight[0] > 220 && bottomRight[1] > 200,
        "四角独立像素验证：照片方向正确且没有裁切")
    style.colorWalkShowStamp = true
    var metadata = PhotoMetadata()
    metadata.captureDateTime = "2026:10:11 11:20:00"
    check(ColorWalkDetail.captureTime.text(metadata: metadata, custom: "") == "11:20 AM"
        && ColorWalkDetail.captureDate.text(metadata: metadata, custom: "") == "OCT 11, 2026", "拍摄时间和日期格式化保留相机当地时间")
    check(ColorWalkDetail.captureTime.text(metadata: PhotoMetadata(), custom: "").isEmpty,
        "缺少 EXIF 日期时不会伪造时间")
    var invalid = metadata; invalid.captureDateTime = "not a date"
    check(ColorWalkDetail.captureDate.text(metadata: invalid, custom: "").isEmpty
        && ColorWalkDetail.custom.text(metadata: metadata, custom: "  中国·天津  ") == "中国·天津", "非法日期留空，自定义第二行可独立编辑")
    let exifURL = folder.appendingPathComponent("colorwalk-exif.jpg")
    let destination = CGImageDestinationCreateWithURL(exifURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, photo.image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:11 11:20:00"]] as CFDictionary)
    check(CGImageDestinationFinalize(destination), "创建真实拍摄时间 EXIF 夹具")
    let exifPhoto = try PhotoDocument(url: exifURL)
    check(exifPhoto.metadata.captureDateTime == "2026:10:11 11:20:00", "从图片文件读取原始拍摄时间")
    let stamped = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000, colorWalkColor: override)
    check((stamped.dataProvider!.data! as Data) != (plain.dataProvider!.data! as Data), "默认盖章实际绘制到输出画布")
    check(sample(stamped, x: 50, y: 635) == topLeft && sample(stamped, x: 950, y: 1200) == bottomRight,
        "文字盖章只绘制在色面中，不遮挡照片")
    var positioned = style
    positioned.colorWalkTextPosition = 0
    let upper = try renderer.render(photo: photo, metadata: metadata, style: positioned, width: 1000, colorWalkColor: override)
    positioned.colorWalkTextPosition = 1
    let lower = try renderer.render(photo: photo, metadata: metadata, style: positioned, width: 1000, colorWalkColor: override)
    let upperInk = inkBounds(upper, headerRows: 585)!, defaultInk = inkBounds(stamped, headerRows: 585)!
    let lowerInk = inkBounds(lower, headerRows: 585)!
    check(upperInk.top < defaultInk.top && defaultInk.top < lowerInk.top,
        "位置滑块左侧上移、右侧下移：实际文字像素符合方向")
    check(abs((lowerInk.bottom - lowerInk.top) - (upperInk.bottom - upperInk.top)) <= 2,
        "上下移动保持两行文字的整体高度和间距")
    check(upperInk.top >= 20 && lowerInk.bottom <= 565
        && sample(lower, x: 50, y: 635) == topLeft, "位置两端保留安全边距，文字不会进入照片")
    style.colorWalkInk = .automatic
    check(ColorWalkInk.automatic.color(on: PaletteColor(hex: "#FFFFFF")!) == .black
        && ColorWalkInk.automatic.color(on: PaletteColor(hex: "#000000")!) == .white, "自动对比模式根据背景选择深浅文字")
    style.colorWalkStamp = String(repeating: "国家植物园 Color Walk ", count: 20)
    style.colorWalkTextScale = 2
    style.colorWalkHeader = 0.25
    style.colorWalkTextPosition = 0.85
    let long = try renderer.render(photo: photo, metadata: metadata, style: style, width: 800, colorWalkColor: override)
    check(long.width == 800 && long.height == 734, "长中英文字和最小色面下可缩放适配")
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(restored == style, "Color Walk 文字、颜色模式和版式保存后可完整恢复")
    let old = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"colorCircles","paletteCount":4,"signature":"Keep"}"#.utf8))
    check(old.template == .colorCircles && old.paletteCount == 4 && old.signature == "Keep"
        && old.colorWalkStamp == "Stay alive · keep trying" && old.colorWalkTextPosition == 0.50,
        "旧版样式升级保留原有模板及默认文字位置")

    let blueURL = folder.appendingPathComponent("colorwalk-blue.png")
    try ImageWriter.save(strip([blue]), to: blueURL, format: .png)
    let batch = folder.appendingPathComponent("colorwalk-batch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
    style = FrameStyle(); style.template = .colorWalk
    style.colorWalkTextPosition = 0.85
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url, colorWalkOverride: override), BatchJob(url: blueURL),
        BatchJob(url: portrait.url, colorWalkOverride: PaletteColor(hex: "#123456"))], folder: batch,
        style: style, size: .original, format: .png, control: BatchControl())
    check(report.succeeded == 3 && report.failed == 0, "Color Walk 可混合批量导出手动色、自动色与竖图")
    let images = try report.results.map { try PhotoDocument(url: $0.outputURL!).image }
    check(sample(images[0], x: 5, y: 5) == [169,105,107] && sample(images[1], x: 5, y: 5) == [92,159,191]
        && sample(images[2], x: 5, y: 5) == [18,52,86], "批量自动色提亮一次，手动颜色保持准确 RGB")
    let batchInk = inkBounds(images[0], headerRows: 351)!
    check((batchInk.top + batchInk.bottom) / 2 > 245, "实际批量导出使用调整后的文字位置")
    style.colorWalkTextPosition = FrameStyle().colorWalkTextPosition
    style.colorWalkDetail = .captureTime
    let example = try renderer.render(photo: demo, metadata: metadata, style: style, width: 1200)
    try ImageWriter.save(example, to: root.appendingPathComponent("Examples/Color-Walk-预览.jpg"), format: .jpeg)
    let portraitExample = try renderer.render(photo: portrait, metadata: metadata, style: style, width: 800)
    try ImageWriter.save(portraitExample, to: root.appendingPathComponent("Examples/Color-Walk-竖版.jpg"), format: .jpeg)
    print("Color Walk 示例自动主色：\(demo.palette.colorWalkColor().hex)")
}
