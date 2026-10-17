import AppKit
import FrameCore

func runClassicChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                      portrait: PhotoDocument, renderer: FrameRenderer) throws {
    var style = FrameStyle(); style.template = .classicFrame
    let layout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(layout.width == 1000 && layout.height == 787 && layout.photoRect.minX == 0
        && layout.photoRect.minY == 120 && layout.photoRect.width == 1000
        && abs(layout.photoRect.height - 666.6667) < 0.001, "经典横版独立预期：满宽照片与 12% 白色底栏")
    let vertical = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style)
    check(vertical.height == 1620 && vertical.photoRect.height == 1500, "经典竖版不裁切，完整照片下方另加底栏")
    check(ExportSize.original.width(for: photo, style: style) == 600, "经典原图尺寸保留原图宽度，不缩小主照片")
    var bordered = style; bordered.classicMargin = 0.03
    let border = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: bordered)
    check(border.height == 777 && border.photoRect.minX == 30 && border.photoRect.width == 940,
        "经典可调白边同时增加两侧与顶部留白，照片比例不变")
    let main = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(sample(main, x: 50, y: 80)[0] > 220 && sample(main, x: 950, y: 80)[1] > 200
        && sample(main, x: 50, y: 600)[2] > 220 && sample(main, x: 950, y: 600)[0] > 220,
        "经典主图四角完整，旋转方向与原片一致")

    let cases: [(String, CameraBrand)] = [("NIKON CORPORATION", .nikon), ("Canon Inc.", .canon), ("SONY", .sony),
        ("FUJIFILM", .fujifilm), ("LEICA CAMERA AG", .leica), ("Hasselblad", .hasselblad),
        ("富士", .fujifilm), ("徕卡", .leica), ("哈苏", .hasselblad), ("Panasonic", .lumix),
        ("OM Digital Solutions", .omSystem), ("OLYMPUS", .olympus), ("RICOH IMAGING COMPANY, LTD.", .ricoh),
        ("PENTAX", .pentax), ("DJI", .dji), ("Insta360", .insta360), ("INSTA360", .insta360),
        ("insta 360", .insta360), ("影石创新", .insta360), ("Arashi Vision", .insta360)]
    for (make, expected) in cases {
        var meta = PhotoMetadata(); meta.brand = make
        check(CameraBrand.detect(meta) == expected, "经典品牌识别：\(make)")
    }
    var metadata = PhotoMetadata(); metadata.brand = "Nikon"; metadata.camera = "Canon EOS R5"
    check(CameraBrand.detect(metadata) == .nikon && CameraBrand.canon.resolved(metadata: metadata) == .canon,
        "自动识别优先读取品牌字段，手动选择可覆盖且不修改原参数")
    metadata.brand = ""; metadata.camera = "LEICA Q3"
    check(CameraBrand.detect(metadata) == .leica && CameraBrand.detect(PhotoMetadata()) == .custom,
        "品牌缺失时可从含品牌名称的型号识别，全空信息不伪造品牌")
    metadata.camera = "Insta360 X5"
    check(CameraBrand.detect(metadata) == .insta360, "品牌字段为空时可从 Insta360 型号识别影石")
    metadata.brand = "My Camera"
    check(CameraBrand.detect(metadata) == .custom, "未知品牌保留自定义文字，不被相机型号覆盖")
    metadata.captureDateTime = "2026:10:11 13:50:19"
    check(CameraBrand.timestamp(metadata) == "2026.10.11 13:50:19"
        && CameraBrand.timestamp(PhotoMetadata()).isEmpty, "经典日期来自 EXIF 相机当地时间，缺失时留空")

    func bytes(_ image: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        result.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return result
    }
    func footerStats(_ image: CGImage, rows: Int) -> (ink: Int, red: Int, left: Int, right: Int) {
        let data = bytes(image)
        var ink = 0, red = 0, left = image.width, right = 0
        for y in (image.height - rows)..<image.height { for x in 0..<image.width {
            let i = (y * image.width + x) * 4
            let r = Int(data[i]), g = Int(data[i+1]), b = Int(data[i+2])
            if min(r,g,b) < 220 { ink += 1; left = min(left,x); right = max(right,x) }
            if r > 140 && r > g + 70 && r > b + 70 { red += 1 }
        } }
        return (ink,red,left,right)
    }
    style.classicShowParameters = false
    var brandImages: [CameraBrand: CGImage] = [:]
    for brand: CameraBrand in [.nikon,.canon,.sony,.fujifilm,.leica,.hasselblad,.dji,.insta360] {
        check(brand.hasVectorMark, "\(brand.label) 使用内置矢量标志")
        style.classicBrand = brand
        let image = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
        let stats = footerStats(image, rows: 120)
        check(stats.ink > 100 && stats.left > 250 && stats.right < 750, "\(brand.label) 实际标志清晰绘制在白栏中央")
        brandImages[brand] = image
    }
    check(footerStats(brandImages[.nikon]!, rows: 120).red == 0 && footerStats(brandImages[.canon]!, rows: 120).red > 200
        && footerStats(brandImages[.leica]!, rows: 120).red > 500 && footerStats(brandImages[.fujifilm]!, rows: 120).red > 10,
        "Nikon 黑色字标、Canon 红色字标、徕卡红点与富士红色细节分别保留")
    style.classicBrand = .leica; style.classicBrandColor = false
    let mono = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    check(footerStats(mono, rows: 120).red == 0 && sample(mono, x: 500, y: 705) == [0,0,0],
        "关闭品牌色后徕卡圆标变为黑色，白色内部字样保留")
    style.classicBrandColor = true; style.classicBrand = .automatic
    let empty = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: style, width: 1000)
    check(footerStats(empty, rows: 120).ink == 0, "无品牌与参数时显示干净白栏，不默认套用 Nikon")
    style.classicBrand = .custom
    let customText = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    check(footerStats(customText, rows: 120).ink > 100, "未知或自定义品牌文字可以正常绘制")

    style.classicBrand = .leica
    style.classicArrangement = .split
    let split = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    style.classicArrangement = .inline
    let inline = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    check(footerStats(split, rows: 120).left > 850 && footerStats(inline, rows: 120).right < 150,
        "左文右标将品牌放右侧，横向信息将品牌放左侧")
    style.classicArrangement = .centered; style.classicBrand = .nikon
    let ignoredLogo = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000, logo: photo.image)
    check(bytes(ignoredLogo) == bytes(brandImages[.nikon]!), "旧模板上传的 Logo 不会自动替换经典品牌标志")
    style.classicUseCustomLogo = true
    let withLogo = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000, logo: photo.image)
    check(bytes(withLogo) != bytes(ignoredLogo), "启用自定义 Logo 后实际使用上传图像")
    style.classicUseCustomLogo = false
    metadata.camera = String(repeating: "Camera 相机型号 ", count: 30)
    metadata.brand = "Nikon"; metadata.focalLength = "70"; metadata.aperture = "2.8"; metadata.shutter = "1/250"; metadata.iso = "200"
    style.classicShowCamera = true; style.classicShowParameters = true; style.classicShowDate = true
    style.classicShowSignature = true; style.signature = String(repeating: "署名 Signature 🐟 ", count: 15)
    style.classicInfoScale = 2; style.classicBrandScale = 2; style.classicFooter = 0.06
    for arrangement in ClassicArrangement.allCases {
        style.classicArrangement = arrangement
        let long = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
        var blankStyle = style
        blankStyle.classicBrand = .automatic; blankStyle.classicShowCamera = false; blankStyle.classicShowParameters = false
        blankStyle.classicShowDate = false; blankStyle.classicShowSignature = false
        let blank = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: blankStyle, width: 1000)
        let a = bytes(long), b = bytes(blank)
        let photoBytes = (long.height - 60) * long.width * 4
        check(a[..<photoBytes] == b[..<photoBytes] && footerStats(long, rows: 60).ink > 100,
            "\(arrangement.rawValue) 最小底栏与长中英文信息可适配且不遮挡照片")
    }
    let saved = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(saved == style, "经典品牌、版式、开关、白边和字号保存后完整恢复")
    let old = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"postageFrame","postagePlace":"Beijing","colorWalkTextPosition":0.5}"#.utf8))
    check(old.template == .postageFrame && old.postagePlace == "Beijing" && old.classicBrand == .automatic
        && old.colorWalkTextPosition == 0.5, "经典模板升级保留邮票、Color Walk 等旧样式设置")

    style = FrameStyle(); style.template = .classicFrame; style.classicShowParameters = false
    var nikon = PhotoMetadata(); nikon.brand = "Nikon"
    var canon = PhotoMetadata(); canon.brand = "Canon"
    var leica = PhotoMetadata(); leica.brand = "Leica"
    var insta = PhotoMetadata(); insta.brand = "Arashi Vision"; insta.camera = "Insta360 X5"
    let out = folder.appendingPathComponent("classic-batch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url, metadataOverride: nikon),
        BatchJob(url: photo.url, metadataOverride: canon), BatchJob(url: portrait.url, metadataOverride: leica),
        BatchJob(url: photo.url, metadataOverride: insta)],
        folder: out, style: style, size: .original, format: .png, control: BatchControl())
    check(report.succeeded == 4 && report.failed == 0, "经典混合品牌、Insta360 与横竖照片可批量导出")
    let images = try report.results.map { try PhotoDocument(url: $0.outputURL!).image }
    check(images[0].width == 600 && images[0].height == 472 && footerStats(images[0], rows: 72).red == 0
        && footerStats(images[1], rows: 72).red > 50 && footerStats(images[2], rows: Int(Double(images[2].width) * 0.12)).red > 100,
        "批量逐张使用 Nikon、Canon、Leica，不复用当前照片的品牌")
    style.classicBrand = .insta360
    let manualInsta = try renderer.render(photo: photo, metadata: insta, style: style, width: 600)
    check(bytes(images[3]) == bytes(manualInsta), "批量自动识别 Arashi Vision，实际输出与手动选择 Insta360 一致")
    let savedInsta = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(savedInsta.classicBrand == .insta360, "Insta360 品牌选择保存后可以恢复")

    metadata = PhotoMetadata(); metadata.focalLength = "28"; metadata.aperture = "4"; metadata.shutter = "1/100"; metadata.iso = "200"
    metadata.captureDateTime = "2026:10:11 13:50:19"
    let cameras: [(CameraBrand,String)] = [(.nikon,"NIKON Z 6_2"),(.canon,"Canon EOS R5"),(.sony,"ILCE-7M4"),
        (.fujifilm,"X-T5"),(.leica,"LEICA Q3"),(.hasselblad,"X2D 100C"),(.insta360,"Insta360 X5")]
    for (brand,camera) in cameras {
        style = FrameStyle(); style.template = .classicFrame; style.classicBrand = brand
        metadata.brand = brand.label; metadata.camera = camera
        if brand == .leica { style.classicArrangement = .split; style.classicShowCamera = true; style.classicFooter = 0.085 }
        if brand == .canon { style.classicArrangement = .inline; style.classicShowCamera = true; style.classicShowDate = true; style.classicFooter = 0.085 }
        if brand == .fujifilm { style.classicShowParameters = false; style.classicFooter = 0.085 }
        let image = try renderer.render(photo: demo, metadata: metadata, style: style, width: 1400)
        try ImageWriter.save(image, to: root.appendingPathComponent("Examples/经典画框-\(brand.label).jpg"), format: .jpeg)
    }
    style.classicBrand = .leica; style.classicArrangement = .split; style.classicShowCamera = true
    let portraitImage = try renderer.render(photo: portrait, metadata: metadata, style: style, width: 800)
    try ImageWriter.save(portraitImage, to: root.appendingPathComponent("Examples/经典画框-竖版.jpg"), format: .jpeg)
}
