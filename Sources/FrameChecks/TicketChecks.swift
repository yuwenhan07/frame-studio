import AppKit
import Vision
import FrameCore

func runTicketChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                     portrait: PhotoDocument, renderer: FrameRenderer) throws {
    var style = FrameStyle(); style.template = .tickets
    let layout = TicketLayout(imageWidth: 600, imageHeight: 400, outputWidth: 1000, style: style)
    check(layout.width == 1000 && layout.height == 902 && abs(layout.photoRect.minX - 198) < 0.001
        && abs(layout.photoRect.minY - 352) < 0.001 && abs(layout.photoRect.width - 604) < 0.001
        && abs(layout.photoRect.height - 402.6667) < 0.001, "Tickets 横图按独立预期留白、加框与底栏，照片不裁切")
    let vertical = TicketLayout(imageWidth: 400, imageHeight: 600, outputWidth: 1000, style: style)
    check(vertical.height == 1405 && abs(vertical.photoRect.height - 906) < 0.001,
          "Tickets 竖图保留 2:3 照片比例与票根底栏")
    check(ExportSize.original.width(for: photo, style: style) == 994, "Tickets 原图尺寸包含画框且保留主照片像素")
    let image = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(sample(image, x: 230, y: 170)[0] > 220 && sample(image, x: 770, y: 170)[1] > 200
        && sample(image, x: 230, y: 530)[2] > 220 && sample(image, x: 770, y: 530)[0] > 220,
        "票券照片四角颜色与方向正确，底栏和贴印不裁切原片")
    check(!layout.outline.contains(CGPoint(x: 500, y: layout.cardRect.maxY - 2))
        && !layout.outline.contains(CGPoint(x: 500, y: layout.cardRect.minY + 2))
        && layout.outline.contains(CGPoint(x: 512, y: layout.cardRect.maxY - 2)),
        "上下细齿孔内凹，齿孔之间保留白纸")
    check(!layout.outline.contains(CGPoint(x: 172, y: 338))
        && !layout.outline.contains(CGPoint(x: 828, y: 338))
        && layout.outline.contains(CGPoint(x: 172, y: 400)), "两侧仅撕线位置留半圆缺口，其余侧边平直")
    let tearRow = (220..<780).map { sample(image, x: $0, y: 564)[0] }
    check(tearRow.filter { $0 > 250 }.count > 50 && tearRow.filter { $0 < 240 }.count > 50,
          "撕线实际由间隔白纸和灰色虚线组成")

    var metadata = PhotoMetadata(); metadata.captureDateTime = "2026:10:18 23:50:00"
    check(TicketDateMode.captureDate.text(metadata: metadata, custom: "") == "18 OCT 2026",
          "票券日期为英文月份，保留相机当地日期")
    metadata.captureDateTime = "2026:02:30 10:00:00"
    check(TicketDateMode.captureDate.text(metadata: metadata, custom: "").isEmpty
          && TicketDateMode.captureDate.text(metadata: PhotoMetadata(), custom: "").isEmpty,
          "票券缺失或非法 EXIF 日期留空")
    check(TicketDateMode.custom.text(metadata: metadata, custom: "  这一程 / 2026  ") == "这一程 / 2026"
          && TicketDateMode.none.text(metadata: metadata, custom: "hidden").isEmpty,
          "票券可自定义或隐藏日期")
    check(TicketBarcode.isValid("TRAVEL-2026/10") && !TicketBarcode.isValid("北京")
          && !TicketBarcode.isValid("") && !TicketBarcode.isValid("A\nB")
          && !TicketBarcode.isValid(String(repeating: "A", count: 49)), "条码输入限制为 48 个以内可打印 ASCII，拒绝无效编码")
    func decoded(_ image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.code128]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
    let barcode = TicketBarcode.image("TRAVEL2026")!
    let context = CGContext(data: nil, width: barcode.width * 4, height: barcode.height * 4,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .none
    context.draw(barcode, in: CGRect(x: 0, y: 0, width: barcode.width * 4, height: barcode.height * 4))
    let standalonePayloads = try decoded(context.makeImage()!)
    check(standalonePayloads.contains("TRAVEL2026"), "独立 Vision 解码器可识读生成的 Code 128 内容")
    style.ticketMark = .barcode; style.ticketBarcodeValue = "TRAVEL2026"
    let barcoded = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1800)
    let canvasPayloads = try decoded(barcoded)
    check(canvasPayloads.contains("TRAVEL2026"), "最终票券画布中的条码可识读，不只是装饰线条")

    func changedBounds(_ first: CGImage, _ second: CGImage) -> CGRect? {
        func bytes(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            data.withUnsafeMutableBytes { ptr in
                let context = CGContext(data: ptr.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return data
        }
        let a = bytes(first), b = bytes(second)
        var x0 = first.width, y0 = first.height, x1 = -1, y1 = -1
        for y in 0..<first.height { for x in 0..<first.width {
            let index = (y * first.width + x) * 4
            if (0..<3).contains(where: { a[index + $0] != b[index + $0] }) {
                x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
            }
        } }
        return x1 < 0 ? nil : CGRect(x: x0, y: first.height - y1 - 1, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
    style.ticketMark = .none
    let blankMark = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    for mark in [TicketMark.stamp, .barcode] {
        style.ticketMark = mark
        let painted = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
        let changed = changedBounds(blankMark, painted)
        check(changed != nil && layout.captionRect.contains(changed!) && changed!.minX >= 512,
              "\(mark.rawValue)只改变右下底栏，保持照片、左侧文字和齿边不变")
    }
    style.ticketBarcodeValue = "不能编码"
    var rejected = false
    do { _ = try renderer.render(photo: photo, metadata: metadata, style: style, width: 600) }
    catch FrameError.invalidBarcode { rejected = true }
    check(rejected, "非法条码内容阻止导出，避免静默导出缺失条码的图片")
    _ = try renderer.render(photo: photo, metadata: metadata, style: style, width: 600, preview: true)
    style.ticketBarcodeValue = ""
    let hidden = try renderer.render(photo: photo, metadata: photo.metadata, style: style, width: 1000)
    check(changedBounds(blankMark, hidden) == nil, "留空条码内容会隐藏条码，其他内容不变")

    style.ticketMark = .none; style.ticketTitle = ""; style.ticketDateMode = .none
    let blankText = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    style.ticketTitle = String(repeating: "北京 Beijing ", count: 30)
    style.ticketSubtitle = String(repeating: "这一程 Travel ", count: 30)
    style.ticketCustomDate = "18 OCT 2026"; style.ticketDateMode = .custom; style.ticketTextScale = 2
    let long = try renderer.render(photo: photo, metadata: metadata, style: style, width: 1000)
    let changed = changedBounds(blankText, long)
    check(changed != nil && layout.captionRect.contains(changed!), "长中英文标题、副标题和日期适配底栏，最大字号不越界")
    let restored = try JSONDecoder().decode(FrameStyle.self, from: JSONEncoder().encode(style))
    check(restored == style, "Tickets 的文字、贴印、日期和尺寸完整保存恢复")
    let legacy = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"postageFrame","postagePlace":"Keep","signature":"Existing"}"#.utf8))
    check(legacy.template == .postageFrame && legacy.postagePlace == "Keep" && legacy.signature == "Existing"
          && legacy.ticketMark == .stamp && legacy.ticketMargin == 0.17, "旧版会话增加 Tickets 默认值，保留原模板和编辑")
    style = FrameStyle(); style.template = .tickets; style.ticketTitle = "Beijing"; style.ticketSubtitle = "北京"
    let batchFolder = folder.appendingPathComponent("ticket-batch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: batchFolder, withIntermediateDirectories: true)
    let report = BatchExporter.run(jobs: [BatchJob(url: photo.url, metadataOverride: metadata), BatchJob(url: portrait.url)],
        folder: batchFolder, style: style, size: .original, format: .png, control: BatchControl())
    check(report.succeeded == 2 && report.failed == 0, "Tickets 横竖照片混合批量导出成功")
    let first = try PhotoDocument(url: report.results[0].outputURL!)
    check(first.width == 994 && first.height == 897, "批量导出按原图像素增加票券和底栏，尺寸符合独立预期")
    metadata.captureDateTime = "2026:10:18 11:20:00"
    for mark in [TicketMark.stamp, .barcode, .none] {
        style.ticketMark = mark
        let output = try renderer.render(photo: portrait, metadata: metadata, style: style, width: 1000)
        try ImageWriter.save(output, to: root.appendingPathComponent("Examples/Tickets-\(mark.rawValue).jpg"), format: .jpeg)
    }
    style.ticketMark = .stamp
    let landscape = try renderer.render(photo: demo, metadata: metadata, style: style, width: 1400)
    try ImageWriter.save(landscape, to: root.appendingPathComponent("Examples/Tickets-横版.jpg"), format: .jpeg)
}
