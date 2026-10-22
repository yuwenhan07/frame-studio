import AppKit
import FrameCore

func runPrintTemplateChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                            portrait: PhotoDocument, renderer: FrameRenderer) throws {
    let expected: [(TemplateID, Int, Int, Int, Int, Int)] = [
        (.film35, 750, 100, 120, 900, 620), (.gallery, 794, 130, 130, 870, 610),
        (.editorial, 944, 90, 260, 910, 790), (.instant, 847, 130, 130, 870, 610)
    ]
    for (id, height, left, top, right, bottom) in expected {
        var style = FrameStyle(); style.template = id
        let layout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
        check(layout.width == 1000 && layout.height == height, "\(id.title) 横版尺寸符合独立预期")
        let image = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
        let tl = sample(image, x: left, y: top), tr = sample(image, x: right, y: top)
        let bl = sample(image, x: left, y: bottom), br = sample(image, x: right, y: bottom)
        check(tl == [240,30,20] && tr == [20,220,40] && bl == [20,50,240] && br == [245,220,20],
              "\(id.title) 原照片四角与方向完整，边框不遮挡照片")
        let preview = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, preview: true)
        check((image.dataProvider!.data! as Data) == (preview.dataProvider!.data! as Data),
              "\(id.title) 相同来源的预览与导出像素一致")
        let originalWidth = ExportSize.original.width(for: photo, style: style)
        let originalLayout = FrameLayout(imageWidth: 600, imageHeight: 400, outputWidth: originalWidth, style: style)
        check(originalLayout.photoRect.width >= 600 && originalLayout.photoRect.height >= 400,
              "\(id.title) 原图尺寸导出保留主照片像素，额外增加画框")
        let blank = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: style, width: 1000)
        style.film35.dateMode = .none; style.gallery.dateMode = .none
        style.editorial.dateMode = .none; style.instant.dateMode = .none
        let hidden = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: style, width: 1000)
        check((blank.dataProvider!.data! as Data) == (hidden.dataProvider!.data! as Data),
              "\(id.title) 缺失日期留空，不使用当前日期或文件时间")

        let long = String(repeating: "漫步 Walk · 🐟 ", count: 40)
        style.signature = long; style.signatureScale = 2
        style.film35.label = long; style.film35.number = long; style.film35.textScale = 1.6
        style.gallery.title = long; style.gallery.subtitle = long; style.gallery.textScale = 1.6
        style.editorial.title = long; style.editorial.subtitle = long; style.editorial.notes = long
        style.editorial.edition = long; style.editorial.textScale = 1.6
        style.instant.caption = long; style.instant.textScale = 1.6
        let textImage = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
        var samePhoto = true
        let a = image.dataProvider!.data! as Data, b = textImage.dataProvider!.data! as Data
        for y in stride(from: top, through: bottom, by: 17) { for x in stride(from: left, through: right, by: 19) {
            let i = y * image.bytesPerRow + x * 4
            if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] { samePhoto = false }
        } }
        check(samePhoto, "\(id.title) 最大字号与长中英文文字不会越入照片")
        style.gallery.titleFont = "Missing-Test-Font"; style.editorial.titleFont = "Missing-Test-Font"
        style.instant.captionFont = "Missing-Test-Font"
        _ = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 64)
        check(true, "\(id.title) 缺失字体、超长文字与最小画布可正常渲染")
    }

    for id in [TemplateID.film35, .gallery, .editorial, .instant] {
        var style = FrameStyle(); style.template = id; style.signature = "Signature"
        style.signatureScale = 0.5
        let small = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
        style.signatureScale = 2
        let large = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
        let a = small.dataProvider!.data! as Data, b = large.dataProvider!.data! as Data
        let start = (small.height - 230) * small.bytesPerRow
        check(a[start...].elementsEqual(b[start...]) == false
            && sample(small, x: 450, y: 400) == sample(large, x: 450, y: 400),
            "\(id.title) 个人落款字号实际改变底栏签名，主照片保持一致")
    }

    let portraitHeights: [(TemplateID, Int)] = [(.film35,1475), (.gallery,1420), (.editorial,1685), (.instant,1505)]
    for (id, expectedHeight) in portraitHeights {
        var s = FrameStyle(); s.template = id
        let l = FrameLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: s)
        check(l.height == expectedHeight && abs(l.photoRect.width / l.photoRect.height - 2.0 / 3) < 0.000001,
              "\(id.title) 竖版画布符合独立预期且不裁切")
        let ultra = FrameLayout(imageWidth: 1, imageHeight: 10000, outputWidth: 1000, style: s)
        check(ultra.height > 1_000_000, "\(id.title) 极端长图仍保持原比例，交由公共像素上限拒绝")
    }
    var s = FrameStyle(); s.template = .film35
    let holes = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    s.film35.showSprockets = false
    let noHoles = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    let lightPixels = (60..<940).filter { sample(holes,x:$0,y:15)[0] > 180 }.count
    let noLight = (60..<940).filter { sample(noHoles,x:$0,y:15)[0] > 180 }.count
    check(lightPixels > 250 && noLight == 0, "胶片齿孔开关改变真实输出，清爽版保留纯黑片边")
    s.template = .gallery
    let ivory = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    check(sample(ivory,x:4,y:4) == [247,243,234], "画廊默认暖白纸色与设计值一致")
    s.gallery.paper = .charcoal
    let dark = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    check(sample(dark,x:4,y:4) == [41,42,41] && s.gallery.paper.ink.usingColorSpace(.sRGB)!.redComponent > 0.9,
          "炭黑纸面切换浅色字，保持正文可读")
    s.template = .instant; s.instant.shadow = 0
    let flat = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    s.instant.shadow = 0.35
    let raised = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    check(sample(flat,x:55,y:400)[0] > sample(raised,x:55,y:400)[0]
          && sample(raised,x:400,y:300) == sample(flat,x:400,y:300), "Instant 阴影在相纸外产生层次，不改变主照片")
    s.template = .editorial; s.editorial.accent = .custom; s.editorial.accentHex = "#1455B8"
    let accent = try renderer.render(photo: photo, metadata: photo.metadata, style: s, width: 1000)
    let chip = sample(accent,x:100,y:225)
    check(chip[2] > chip[0] + 100, "杂志自定义强调色实际用于照片上方细线")

    s.film35.label = "FILM / KEEP"; s.film35.margin = 0.09; s.film35.showSprockets = false
    s.gallery.title = "山间"; s.gallery.paper = .charcoal; s.gallery.margin = 0.14
    s.editorial.title = "TIANJIN"; s.editorial.header = 0.29; s.editorial.notes = "Journey"
    s.instant.caption = "留住此刻"; s.instant.footer = 0.22; s.instant.paper = .ivory
    let decoded = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(s))
    check(decoded == s, "四种模板的独立版式、颜色、文案与字体完整编码恢复")
    let legacy = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"colorWalk","colorWalkStamp":"Keep","paletteCount":6}"#.utf8))
    check(legacy.film35 == Film35Style() && legacy.gallery == GalleryStyle() && legacy.editorial == EditorialStyle()
          && legacy.instant == InstantStyle() && legacy.colorWalkStamp == "Keep" && legacy.paletteCount == 6,
          "旧会话增加四种默认模板，保留已有模板与颜色设置")
    let bounds = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"film35":{"margin":9,"rail":0},"gallery":{"footer":100},"editorial":{"accentHex":"invalid","header":0},"instant":{"border":-1,"shadow":1e100}}"#.utf8))
    check(bounds.film35.margin == 0.12 && bounds.film35.rail == 0.065 && bounds.gallery.footer == 0.26
          && bounds.editorial.accentHex == "#8B7565" && bounds.editorial.header == 0.17
          && bounds.instant.border == 0.025 && bounds.instant.shadow == 0.35,
          "损坏的四模板尺寸、颜色与阴影约束到安全范围")
    check(s.gallery.resetLayout().title == "山间" && s.gallery.resetLayout().paper == .charcoal
          && s.film35.resetLayout().label == "FILM / KEEP" && !s.film35.resetLayout().showSprockets
          && s.editorial.resetLayout().title == "TIANJIN" && s.instant.resetLayout().caption == "留住此刻",
          "重置版式保留文案、纸面与内容开关")

    let redURL = folder.appendingPathComponent("editorial-red.png"), blueURL = folder.appendingPathComponent("editorial-blue.png")
    for (url, hex) in [(redURL,"#B44A3A"),(blueURL,"#3C6EBA")] {
        let c = CGContext(data:nil,width:890,height:594,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(PaletteColor(hex:hex)!.color.cgColor); c.fill(CGRect(x:0,y:0,width:890,height:594))
        try ImageWriter.save(c.makeImage()!,to:url,format:.png)
    }
    for id in [TemplateID.film35,.gallery,.editorial,.instant] {
        var style = FrameStyle(); style.template = id
        let directory = folder.appendingPathComponent("print-batch-\(id.rawValue)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let jobs = id == .editorial ? [BatchJob(url:redURL),BatchJob(url:blueURL)] : [BatchJob(url:photo.url),BatchJob(url:portrait.url)]
        let report = BatchExporter.run(jobs:jobs,folder:directory,style:style,size:.original,format:.png,control:BatchControl())
        check(report.succeeded == 2 && report.failed == 0, "\(id.title) 单张与横竖混合批量共用渲染器")
        if id == .editorial {
            let outputs = try report.results.map { try PhotoDocument(url:$0.outputURL!).image }
            let red = sample(outputs[0],x:100,y:224), blue = sample(outputs[1],x:100,y:224)
            check(red[0] > red[2] + 30 && blue[2] > blue[0] + 30, "杂志批量强调色来自各张照片，不套用当前预览颜色")
        }
    }
    var metadata = PhotoMetadata(); metadata.captureDateTime = "2026:10:22 09:20:00"
    for id in [TemplateID.film35,.gallery,.editorial,.instant] {
        var style = FrameStyle(); style.template = id; style.signature = "Frame Studio"
        style.gallery.title = "Between light and silence"; style.gallery.subtitle = "山间 · 光影随行"
        style.editorial.title = "WANDER"; style.editorial.notes = "A LITTLE WALK, A LITTLE JOY"
        for (source,suffix) in [(demo,"横版"),(portrait,"竖版")] {
            let image = try renderer.render(photo:source,metadata:metadata,style:style,width:1400)
            try ImageWriter.save(image,to:root.appendingPathComponent("Examples/\(id.title)-\(suffix).jpg"),format:.jpeg)
        }
    }
}
