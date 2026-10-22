import AppKit
import FrameCore

func runWalkTicketChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                         portrait: PhotoDocument, renderer: FrameRenderer) throws {
    var style = FrameStyle(); style.template = .walkTicket
    let l = WalkTicketLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style.walkTicket)
    check(l.width == 1000 && l.height == 536 && abs(l.card.minX - 90) < 0.001 && abs(l.card.minY - 63) < 0.001
          && abs(l.card.width - 820) < 0.001 && abs(l.card.height - 410) < 0.001
          && abs(l.photoRect.width - 250.1) < 0.001 && abs(l.photoRect.height - 166.7333) < 0.001,
          "漫步票根为独立预期的横向画布，横图完整适配左侧窗口")
    let vertical = WalkTicketLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style.walkTicket)
    check(vertical.height == 536 && abs(vertical.photoRect.height - 344.4) < 0.001
          && abs(vertical.photoRect.width - 229.6) < 0.001, "竖图保持 2:3 比例，票根画布尺寸不变")
    check(ExportSize.original.width(for: photo, style: style) == 2400,
          "漫步票根原图尺寸根据照片实际占宽计算，完整显示模式保留照片像素")
    check(!l.outline.contains(CGPoint(x: 696.8, y: 470)) && !l.outline.contains(CGPoint(x: 696.8, y: 66))
          && l.outline.contains(CGPoint(x: 665, y: 470)) && !l.outline.contains(CGPoint(x: 91, y: 64)),
          "票根上下撕线口内凹，外边缘有圆角，缺口两侧保留票面")
    let painted = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(sample(painted, x: 185, y: 226)[0] > 220 && sample(painted, x: 310, y: 226)[1] > 190
          && sample(painted, x: 185, y: 310)[2] > 220 && sample(painted, x: 310, y: 310)[0] > 220,
          "漫步票根完整显示原照片四角，方向正确")
    let tear = (110..<425).map { sample(painted, x: 697, y: $0)[0] }
    check(tear.filter { $0 > 110 }.count > 10 && tear.filter { $0 < 90 }.count > 10,
          "撕线实际像素为间隔圆点，缺口处不覆盖背景")

    let blue = PaletteColor(hex: "#1234DE")!
    let manual = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, palette: [blue])
    let chip = sample(manual, x: 426, y: 371)
    check(abs(chip[0] - 18) < 3 && abs(chip[1] - 52) < 3 && abs(chip[2] - 222) < 3,
          "票根色块使用传入的手动色卡，颜色与 HEX 对应")
    let empty = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, palette: [])
    style.walkTicket.showPalette = false
    let hidden = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000, palette: [])
    check((empty.dataProvider!.data! as Data) == (hidden.dataProvider!.data! as Data),
          "手动删空色卡不会重新取色，中间色块与右侧色带均隐藏")
    style.walkTicket.showPalette = true
    check(style.activePaletteCount == 4 && style.paletteCount == 5, "漫步票根默认四色，不改变原色卡模板的数量")

    var textStyle = style
    textStyle.walkTicket.title = ""; textStyle.walkTicket.subtitle = ""
    textStyle.walkTicket.heading = ""; textStyle.walkTicket.dateMode = .none; textStyle.walkTicket.notes = ""
    let noText = try renderer.render(photo: photo, metadata: photo.metadata, style: textStyle, width: 1000)
    textStyle.walkTicket.title = String(repeating: "城市 WALK ", count: 40)
    textStyle.walkTicket.subtitle = String(repeating: "慢慢走 · Take a walk ", count: 35)
    textStyle.walkTicket.heading = "「漫步日志」"
    textStyle.walkTicket.notes = String(repeating: "手填备注 ", count: 40)
    textStyle.walkTicket.dateMode = .custom; textStyle.walkTicket.customDate = "22 OCT 2026"
    textStyle.walkTicket.textScale = 2
    let longText = try renderer.render(photo: photo, metadata: photo.metadata, style: textStyle, width: 1000)
    var changedOutside = false, changedInside = false
    let a = noText.dataProvider!.data! as Data, b = longText.dataProvider!.data! as Data
    let row = noText.bytesPerRow
    for y in 0..<536 { for x in 0..<1000 {
        let i = y * row + x * 4
        if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] {
            if x < 400 || x > 670 || y < 80 || y > 335 { changedOutside = true }
            else { changedInside = true }
        }
    } }
    check(changedInside && !changedOutside, "最大字号与长中英文仅在中央文字区变化，不越入照片、色卡或右侧票根")

    let decoration = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    style.walkTicket.showBarcode = false
    let noDecoration = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    let da = decoration.dataProvider!.data! as Data, db = noDecoration.dataProvider!.data! as Data
    var decorationPixels = 0, outsideDecoration = 0, brightest = 0
    for y in 0..<536 { for x in 0..<1000 {
        let i = y * decoration.bytesPerRow + x * 4
        if x >= 794 && x <= 868 && y >= 257 && y <= 446 { brightest = max(brightest, Int(da[i])) }
        if da[i] != db[i] || da[i + 1] != db[i + 1] || da[i + 2] != db[i + 2] {
            if x >= 792 && x <= 870 && y >= 254 && y <= 447 { decorationPixels += 1 }
            else { outsideDecoration += 1 }
        }
    } }
    check(decorationPixels > 300 && outsideDecoration == 0 && brightest < 220,
          "装饰线条仅改变右侧区域，与文字同色且没有白色条码底板")
    let oldBarcode = try JSONDecoder().decode(WalkTicketStyle.self, from: Data(#"{"barcode":"旧的任意内容","showBarcode":true}"#.utf8))
    check(oldBarcode.showBarcode, "旧条码内容被忽略，装饰开关仍可恢复，不再要求可编码文本")

    style.walkTicket = WalkTicketStyle(); style.walkTicket.theme = .orange
    style.walkTicket.title = "Journey"; style.walkTicket.notes = "手动文字"
    style.walkTicket.photoMode = .fill; style.walkTicket.showHex = true; style.walkTicket.paletteCount = 8
    style.walkTicket.margin = 0.16; style.walkTicket.aspect = 0.64
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(restored == style, "漫步票根颜色、文案、照片模式、色卡与尺寸完整保存恢复")
    let legacy = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"tickets","ticketTitle":"Keep","paletteCount":6}"#.utf8))
    check(legacy.template == .tickets && legacy.ticketTitle == "Keep" && legacy.paletteCount == 6
          && legacy.walkTicket == WalkTicketStyle(), "旧会话增加漫步票根默认设置，保留原模板、票券文案和色卡")
    let bounded = try JSONDecoder().decode(WalkTicketStyle.self,
        from: Data(#"{"margin":9,"aspect":0,"textScale":1e200,"paletteCount":200,"customHex":"broken","shadow":-1}"#.utf8))
    check(bounded.margin == 0.16 && bounded.aspect == 0.44 && bounded.textScale == 2
          && bounded.paletteCount == 8 && bounded.customHex == "#494644" && bounded.shadow == 0,
          "损坏的漫步票根尺寸、颜色和数量被约束到安全范围")
    let fill = WalkTicketLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style.walkTicket)
    check(fill.photoRect == fill.photoSlot, "填满裁切模式显式使用完整照片窗口")

    style = FrameStyle(); style.template = .walkTicket
    let batchFolder = folder.appendingPathComponent("walkticket-batch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url, paletteOverride: [blue]), BatchJob(url: portrait.url, paletteOverride: [])],
        folder: batchFolder, style: style, size: .standard, format: .png, control: BatchControl())
    check(report.succeeded == 2 && report.failed == 0, "漫步票根横竖混合批量导出，使用各张照片的色卡覆盖")
    let first = try PhotoDocument(url: report.results[0].outputURL!)
    check(first.width == 1920 && first.height == 1030, "批量票根导出尺寸符合独立预期的横向画布")

    var metadata = PhotoMetadata(); metadata.captureDateTime = "2026:10:22 09:20:00"
    style.walkTicket.title = "BEIJING"; style.walkTicket.subtitle = "北京 · 漫步日志"
    style.walkTicket.notes = "A LITTLE WALK, A LITTLE JOY"
    for theme in [WalkTicketTheme.charcoal, .cream, .orange, .brown] {
        style.walkTicket.theme = theme
        let image = try renderer.render(photo: portrait, metadata: metadata, style: style, width: 1800)
        try ImageWriter.save(image, to: root.appendingPathComponent("Examples/漫步票根-\(theme.rawValue).jpg"), format: .jpeg)
    }
    style.walkTicket.theme = .charcoal
    let landscape = try renderer.render(photo: demo, metadata: metadata, style: style, width: 1800)
    try ImageWriter.save(landscape, to: root.appendingPathComponent("Examples/漫步票根-横版照片.jpg"), format: .jpeg)
}
