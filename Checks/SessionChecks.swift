import AppKit
import FrameCore

@main
@MainActor
struct SessionChecks {
    static var passed = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw NSError(domain: "SessionChecks", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
        passed += 1
        print("PASS: \(message)")
    }

    static func fixture(_ url: URL, width: Int = 90, height: Int = 60, color: NSColor = .systemOrange) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        try ImageWriter.save(context.makeImage()!, to: url, format: .png)
    }

    static func loaded(_ model: StudioModel, _ url: URL) async throws {
        for _ in 0..<300 {
            if !model.isLoading && !model.isRendering && model.photo?.url == url && model.preview != nil { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "SessionChecks", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "恢复照片超时：\(url.lastPathComponent)"])
    }

    static func store(_ root: URL) -> StudioSessionStore {
        StudioSessionStore(root: root.appendingPathComponent("state"), legacyImportRoot: root.appendingPathComponent("legacy"))
    }

    static func probe(_ root: URL) async throws {
        let model = StudioModel(sessionStore: store(root))
        model.start(arguments: [])
        let b = root.appendingPathComponent("finder/b.png")
        try await loaded(model, b)
        try check(model.items.count == 2 && model.metadata.camera == "B edited", "独立进程恢复列表与当前照片编辑")
        try check(model.style.colorWalkTextPosition == 0.67 && model.style.signature == "会话 / Session 🐟"
            && model.format == .png && model.exportSize == .standard, "独立进程恢复样式和导出设置")
        try check(model.style.colorWalkBackground == .horizontalStripes && model.style.colorWalkStripeCount == 6,
            "独立进程恢复 Color Walk 条纹模式和独立取色数量")
        try check(model.style.postageVariant == .caption
            && model.style.postagePlace == "Beijing 北京" && model.style.postageDateMode == .custom
            && model.style.postageCustomDate == "2026/10/11" && model.style.postageMargin == 0.14,
            "独立进程恢复邮票模板、地点、自定义日期和画框调整")
        try check(model.style.template == .classicFrame && model.style.classicBrand == .hasselblad
            && model.style.classicArrangement == .split && model.style.classicFooter == 0.14 && model.style.classicShowDate,
            "独立进程恢复经典模板、品牌、布局、底栏和信息开关")
        try check(model.style.ticketTitle == "Journey" && model.style.ticketSubtitle == "旅途"
            && model.style.ticketMark == .barcode && model.style.ticketBarcodeValue == "TICKET-2026"
            && model.style.ticketStampTop == "TRAVEL CLUB" && model.style.ticketFooter == 0.23,
            "独立进程恢复 Tickets 文案、条码、邮戳文字与底栏设置")
        try check(model.style.walkTicket.title == "BEIJING" && model.style.walkTicket.theme == .orange
            && model.style.walkTicket.notes == "手填备注" && model.style.walkTicket.paletteCount == 3
            && model.style.walkTicket.photoMode == .fill && model.style.walkTicket.margin == 0.13,
            "独立进程恢复漫步票根文案、配色、色卡与照片模式")
        try check(model.style.film35.label == "LOCAL 35" && model.style.film35.margin == 0.09
            && !model.style.film35.showSprockets, "独立进程恢复胶片标签、齿孔和版式")
        try check(model.style.gallery.title == "静" && model.style.gallery.paper == .charcoal
            && model.style.gallery.footer == 0.22, "独立进程恢复画廊文案、纸色和留白")
        try check(model.style.editorial.title == "TIANJIN" && model.style.editorial.accent == .custom
            && model.style.editorial.accentHex == "#305070", "独立进程恢复杂志标题与自定义强调色")
        try check(model.style.instant.caption == "留住此刻" && model.style.instant.captionFont == "Comic Sans MS"
            && model.style.instant.border == 0.06, "独立进程恢复 Instant 文案、字体和相纸边框")
        try check(model.style.cinema.subtitle == "记住今天" && model.style.cinema.bottom == 0.25
            && model.style.receipt.place == "LOCAL" && model.style.receipt.margin == 0.16
            && model.style.tornPaper.caption == "Quiet" && model.style.tornPaper.roughness == 0.006
            && model.style.tornPaper.showCaptionArea && model.style.tornPaper.border == 0.04,
            "独立进程恢复 Cinema、Receipt 和 Paper 的文案与版式")
        try check(model.items[0].paletteOverride?.isEmpty == true && model.items[0].colorWalkOverride?.hex == "#4A7B2C"
            && model.batchSelectedCount == 1 && model.hasCustomLogo, "独立进程恢复删空色卡、主色、批量勾选和 Logo")
        try check(model.flushSession(), "独立进程可继续保存恢复后的会话")
    }

    static func main() async {
        if let i = CommandLine.arguments.firstIndex(of: "--probe"), i + 1 < CommandLine.arguments.count {
            do { try await probe(URL(fileURLWithPath: CommandLine.arguments[i + 1])); exit(0) }
            catch { fputs("PROBE FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yingkuang-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let fm = FileManager.default
            let sessionStore = store(root)
            let a = root.appendingPathComponent("legacy/transfer-a/a.png")
            let b = root.appendingPathComponent("finder/b.png")
            try fixture(a)
            try fixture(b, width: 60, height: 90, color: .blue)
            let aBytes = try Data(contentsOf: a), bBytes = try Data(contentsOf: b)
            let first = StudioModel(sessionStore: sessionStore)
            first.start(arguments: [])
            first.importPhotos([a, b])
            let retainedA = first.items[0].url
            try await loaded(first, retainedA)
            let aID = first.items[0].id, bID = first.items[1].id
            try check(retainedA.path.hasPrefix(sessionStore.importedPhotos.path + "/") && retainedA != a
                && first.items[1].url == b, "仅把 App 缓存副本转存长期目录，Finder 原片留在原位")
            try check(try Data(contentsOf: a) == aBytes && Data(contentsOf: retainedA) == aBytes, "转存逐字节保留副本与来源")
            first.importPhotos([a])
            try await loaded(first, retainedA)
            try check(first.items.count == 2, "重新拖入同一缓存照片不会重复转存或添加")
            first.selectTemplate(.colorCircles)
            try await loaded(first, retainedA)
            first.removePaletteColor(photoID: aID, swatchID: first.paletteSwatches[0].id)
            first.setColorWalkHex("#4A7B2C", photoID: aID)
            first.metadata.camera = "A edited"
            first.metadata.iso = "800"
            first.selectPhoto(bID)
            try await loaded(first, b)
            first.setPaletteHex("#112233", photoID: bID, swatchID: first.paletteSwatches[0].id)
            first.setColorWalkHex("#334455", photoID: bID)
            first.metadata.camera = "B edited"
            first.metadata.focalLength = "85.0"
            first.style.signature = "会话 / Session 🐟"
            first.style.colorWalkTextPosition = 0.67
            first.style.colorWalkHeader = 0.39
            first.style.colorWalkBackground = .horizontalStripes
            first.style.colorWalkStripeCount = 6
            first.style.postageVariant = .caption
            first.style.postagePlace = "Beijing 北京"
            first.style.postageDateMode = .custom
            first.style.postageCustomDate = "2026/10/11"
            first.style.postageMargin = 0.14
            first.style.ticketTitle = "Journey"; first.style.ticketSubtitle = "旅途"
            first.style.ticketMark = .barcode; first.style.ticketBarcodeValue = "TICKET-2026"
            first.style.ticketStampTop = "TRAVEL CLUB"; first.style.ticketFooter = 0.23
            first.style.walkTicket.title = "BEIJING"; first.style.walkTicket.theme = .orange
            first.style.walkTicket.notes = "手填备注"; first.style.walkTicket.paletteCount = 3
            first.style.walkTicket.photoMode = .fill; first.style.walkTicket.margin = 0.13
            first.style.film35.label = "LOCAL 35"; first.style.film35.margin = 0.09; first.style.film35.showSprockets = false
            first.style.gallery.title = "静"; first.style.gallery.paper = .charcoal; first.style.gallery.footer = 0.22
            first.style.editorial.title = "TIANJIN"; first.style.editorial.accent = .custom; first.style.editorial.accentHex = "#305070"
            first.style.instant.caption = "留住此刻"; first.style.instant.captionFont = "Comic Sans MS"; first.style.instant.border = 0.06
            first.style.classicBrand = .hasselblad
            first.style.classicArrangement = .split
            first.style.classicFooter = 0.14
            first.style.classicShowDate = true
            first.selectTemplate(.classicFrame)
            first.inspectorTab = 1
            first.format = .png; first.exportSize = .standard
            first.setBatchSelection(aID, selected: true)
            try first.setLogo(a)
            let exported = root.appendingPathComponent("exported.png")
            try fixture(exported)
            first.style.cinema.subtitle = "记住今天"; first.style.cinema.bottom = 0.25
            first.style.receipt.place = "LOCAL"; first.style.receipt.margin = 0.16
            first.style.tornPaper.caption = "Quiet"; first.style.tornPaper.roughness = 0.006
            first.style.tornPaper.showCaptionArea = true; first.style.tornPaper.border = 0.04
            first.items[1].exportedTo = exported
            try await loaded(first, b)
            try check(first.flushSession(), "退出前立即保存当前照片，无需切换照片")
            let saved = try sessionStore.load().session!
            try check(saved.photos.map(\.id) == [aID, bID] && saved.selectedID == bID
                && saved.photos[1].metadata?.camera == "B edited", "保存稳定 ID、顺序、当前照片和最后一次参数修改")

            let subprocess = Process()
            subprocess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            subprocess.arguments = ["--probe", root.path]
            let output = Pipe()
            subprocess.standardOutput = output; subprocess.standardError = output
            try subprocess.run()
            subprocess.waitUntilExit()
            let probeOutput = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try check(subprocess.terminationStatus == 0, "真正重新启动一个进程后完整恢复会话：\(probeOutput.trimmingCharacters(in: .whitespacesAndNewlines))")

            let retiredRoot = root.appendingPathComponent("retired-template")
            try FileManager.default.createDirectory(at: retiredRoot, withIntermediateDirectories: true)
            var retiredJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: sessionStore.sessionURL)) as! [String: Any]
            var retiredStyle = retiredJSON["style"] as! [String: Any]
            retiredStyle["template"] = "contactSheet"; retiredStyle["contactSheet"] = ["showFilenames": true]
            retiredJSON["style"] = retiredStyle
            let retiredStore = StudioSessionStore(root: retiredRoot)
            try JSONSerialization.data(withJSONObject: retiredJSON).write(to: retiredStore.sessionURL)
            let migrated = StudioModel(sessionStore: retiredStore); migrated.start(arguments: [])
            try await loaded(migrated, b)
            try check(migrated.style.template == .film35 && migrated.items.map(\.id) == [aID, bID]
                && migrated.batchSelectedCount == 1 && migrated.style.film35.label == "LOCAL 35"
                && migrated.metadata.camera == "B edited" && migrated.style.signature == "会话 / Session 🐟",
                "移除接触印样后真实会话恢复原照片、选择、文案与参数，并切回胶片相框")

            let restored = StudioModel(sessionStore: sessionStore)
            restored.start(arguments: [])
            try await loaded(restored, b)
            try check(restored.items.map(\.id) == [aID, bID] && restored.selectedID == bID
                && restored.metadata.focalLength == "85.0", "模型重建后不回到示例图，保留当前预览与参数")
            try check(restored.colorWalkHex == "#334455" && restored.items[0].paletteOverride?.isEmpty == true
                && restored.items[1].paletteOverride?.first?.color.hex == "#112233", "每张照片的手动主色与色卡删除结果分别恢复")
            try check(restored.hasCustomLogo && restored.logoName == "a.png" && restored.lastExport == exported,
                "自定义 Logo 副本和导出记录可恢复")
            restored.resetClassicStyle()
            try check(restored.style.classicFooter == FrameStyle().classicFooter && restored.style.classicBrand == .hasselblad
                && restored.style.classicArrangement == .split && restored.style.classicShowDate
                && restored.style.postagePlace == "Beijing 北京" && restored.style.signature == "会话 / Session 🐟",
                "重置经典版式保留品牌、内容开关、落款与其他模板的编辑")
            restored.resetTicketStyle()
            try check(restored.style.ticketFooter == FrameStyle().ticketFooter && restored.style.ticketTitle == "Journey"
                && restored.style.ticketMark == .barcode && restored.style.ticketBarcodeValue == "TICKET-2026"
                && restored.style.ticketStampTop == "TRAVEL CLUB" && restored.style.postagePlace == "Beijing 北京",
                "重置 Tickets 版式保留文案、贴印模式、条码、邮戳和其他模板")
            restored.selectTemplate(.tickets)
            try await loaded(restored, b)
            try check(restored.inspectorTab == 1 && restored.batchSelectedCount == 1
                && restored.photo?.url == b, "切换 Tickets 打开样式区并保留当前照片和勾选")
            restored.resetWalkTicketStyle()
            try check(restored.style.walkTicket.margin == WalkTicketStyle().margin
                && restored.style.walkTicket.title == "BEIJING" && restored.style.walkTicket.notes == "手填备注"
                && restored.style.walkTicket.theme == .orange && restored.style.walkTicket.paletteCount == 3
                && restored.style.walkTicket.photoMode == .fill && restored.style.ticketTitle == "Journey",
                "重置漫步票根版式保留内容、主题、照片模式、色卡与其他模板")
            restored.selectTemplate(.walkTicket)
            try await loaded(restored, b)
            try check(restored.inspectorTab == 1 && restored.batchSelectedCount == 1 && restored.photo?.url == b
                && restored.paletteColors.count == 1 && restored.paletteColors[0].hex == "#112233",
                "切换漫步票根保留当前照片、勾选与按照片记录的手动色卡")
            restored.selectTemplate(.colorWalk)
            try await loaded(restored, b)
            restored.selectColorWalkBackground(.solid)
            try await loaded(restored, b)
            try check(restored.colorWalkHex == "#334455" && restored.paletteColors.first?.hex == "#112233",
                "切换纯色背景保留独立主色和每张照片的手动条纹色卡")
            restored.selectColorWalkBackground(.horizontalStripes)
            try await loaded(restored, b)
            try check(restored.style.activePaletteCount == 6 && restored.paletteColors.count == 1
                && restored.paletteColors.first?.hex == "#112233" && restored.colorWalkHex == "#334455",
                "切回条纹使用手动色卡，不覆盖纯色主色或补回已删颜色")
            restored.style.colorWalkStamp = "测试盖章"
            restored.resetColorWalkStyle()
            try check(restored.style.colorWalkHeader == FrameStyle().colorWalkHeader
                && restored.style.colorWalkBackground == .horizontalStripes && restored.style.colorWalkStripeCount == 6
                && restored.style.colorWalkStamp == "测试盖章" && restored.colorWalkHex == "#334455"
                && restored.paletteColors.first?.hex == "#112233" && restored.batchSelectedCount == 1,
                "重置 Color Walk 版式保留背景模式、数量、盖章、手动颜色与勾选")
            for id in [TemplateID.film35, .gallery, .editorial, .instant, .cinema, .receipt, .tornPaper] {
                restored.selectTemplate(id)
                try await loaded(restored, b)
                try check(restored.inspectorTab == 1 && restored.selectedID == bID && restored.batchSelectedCount == 1
                    && restored.preview != nil && restored.errorMessage == nil,
                    "切换 \(id.title) 接入实际预览并保留照片与批量勾选")
                let before = restored.style
                restored.resetPrintStyle()
                switch id {
                case .film35:
                    try check(restored.style.film35.margin == 0.065 && restored.style.film35.label == "LOCAL 35"
                        && !restored.style.film35.showSprockets && restored.style.gallery == before.gallery,
                        "重置胶片版式保留标签、齿孔开关与其他模板")
                case .gallery:
                    try check(restored.style.gallery.footer == 0.16 && restored.style.gallery.title == "静"
                        && restored.style.gallery.paper == .charcoal && restored.style.editorial == before.editorial,
                        "重置画廊版式保留作品名、纸色与其他模板")
                case .editorial:
                    try check(restored.style.editorial.header == 0.23 && restored.style.editorial.title == "TIANJIN"
                        && restored.style.editorial.accentHex == "#305070" && restored.style.instant == before.instant,
                        "重置杂志版式保留标题、强调色与其他模板")
                case .instant:
                    try check(restored.style.instant.border == 0.04 && restored.style.instant.caption == "留住此刻"
                        && restored.style.instant.captionFont == "Comic Sans MS" && restored.style.film35 == before.film35,
                        "重置 Instant 版式保留短句、字体与其他模板")
                case .cinema:
                    try check(restored.style.cinema.bottom == 0.17 && restored.style.cinema.subtitle == "记住今天"
                        && restored.style.receipt == before.receipt, "字幕重置仅恢复版式，保留文案与小票设置")
                case .receipt:
                    try check(restored.style.receipt.margin == 0.10 && restored.style.receipt.place == "LOCAL"
                        && restored.style.tornPaper == before.tornPaper, "小票重置保留地点与其他模板")
                case .tornPaper:
                    try check(restored.style.tornPaper.roughness == 0.0035 && restored.style.tornPaper.caption == "Quiet"
                        && restored.style.tornPaper.showCaptionArea && restored.style.tornPaper.border == 0.009
                        && restored.style.cinema == before.cinema, "撕边重置保留短句与其他模板设置")
                default: break
                }
                try await loaded(restored, b)
            }
            restored.style.classicUseCustomLogo = true
            restored.removeLogo()
            try check(!restored.hasCustomLogo && !restored.style.classicUseCustomLogo,
                "移除自定义 Logo 后恢复内置经典品牌标志")
            restored.start(arguments: [])
            try check(restored.items.count == 2 && restored.selectedID == bID, "重复启动回调不会重复导入或重置状态")
            restored.style.colorWalkTextPosition = 0.72
            restored.metadata.iso = "1600"
            restored.format = .jpeg; restored.inspectorTab = 2
            try await Task.sleep(nanoseconds: 800_000_000)
            let autosaved = try sessionStore.load().session!
            try check(autosaved.style.colorWalkTextPosition == 0.72 && autosaved.photos[1].metadata?.iso == "1600"
                && autosaved.format == .jpeg && autosaved.inspectorTab == 2, "无需退出也会自动保存最新编辑、导出设置和右侧面板")

            try fm.removeItem(at: a)
            restored.selectPhoto(aID)
            try await loaded(restored, retainedA)
            try check(restored.metadata.camera == "A edited" && restored.metadata.iso == "800",
                "旧缓存被清理后仍能读取长期保存的照片和逐图编辑")
            restored.selectPhoto(bID)
            try await loaded(restored, b)
            try check(restored.flushSession(), "保存缺失文件验证前的当前会话")
            let offlineB = b.appendingPathExtension("offline")
            try fm.moveItem(at: b, to: offlineB)
            let offline = StudioModel(sessionStore: sessionStore)
            offline.start(arguments: [])
            try await loaded(offline, retainedA)
            try check(offline.items.count == 2 && offline.items[1].metadata?.iso == "1600"
                && offline.sessionNotice != nil && offline.errorMessage == nil,
                "原片暂不可用时保留列表和编辑，预览可用照片并提示")
            try fm.moveItem(at: offlineB, to: b)
            offline.selectPhoto(bID)
            try await loaded(offline, b)
            try check(offline.metadata.camera == "B edited" && offline.metadata.iso == "1600", "原片重新可用后可继续恢复原来的编辑")
            try check(try Data(contentsOf: b) == bBytes, "整个保存和恢复过程没有修改 Finder 原片")
            try check(offline.flushSession(), "保存替换原片验证前的会话")
            try fixture(b, width: 80, height: 50, color: .red)
            let changed = StudioModel(sessionStore: sessionStore)
            changed.start(arguments: [])
            try await loaded(changed, b)
            try check(changed.metadata.camera.isEmpty && changed.metadata.iso.isEmpty && !changed.hasManualColorWalkColor
                && !changed.hasManualPalette && changed.photo?.width == 80, "同路径换成另一张照片时不套用旧参数与旧颜色")
            changed.selectAllForBatch(); changed.removeBatchSelectedPhotos()
            try check(changed.flushSession(), "主动清空照片列表也会保存")
            let empty = StudioModel(sessionStore: sessionStore)
            empty.start(arguments: [])
            try check(empty.items.isEmpty && empty.photo == nil && empty.style.colorWalkTextPosition == 0.72,
                "空列表重开仍为空，样式保留且不重新添加示例图")

            let validBackup = try Data(contentsOf: sessionStore.backupURL)
            let rootMode = try fm.attributesOfItem(atPath: sessionStore.root.path)[.posixPermissions] as? NSNumber
            let sessionMode = try fm.attributesOfItem(atPath: sessionStore.sessionURL.path)[.posixPermissions] as? NSNumber
            let backupMode = try fm.attributesOfItem(atPath: sessionStore.backupURL.path)[.posixPermissions] as? NSNumber
            try check(rootMode?.intValue == 0o700 && sessionMode?.intValue == 0o600 && backupMode?.intValue == 0o600,
                      "会话目录与主备份权限限制为当前用户读写")
            let currentState = try JSONSerialization.jsonObject(with: validBackup) as! [String: Any]
            for field in ["batchFolder", "exportedTo"] {
                var tampered = currentState
                if field == "batchFolder" { tampered[field] = "https://example.invalid/" }
                else {
                    var photos = tampered["photos"] as! [[String: Any]]
                    photos[0][field] = "https://example.invalid/photo.jpg"
                    tampered["photos"] = photos
                }
                let isolated = StudioSessionStore(root: root.appendingPathComponent("invalid-\(field)"))
                try fm.createDirectory(at: isolated.root, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: tampered).write(to: isolated.sessionURL)
                var rejected = false
                do { _ = try isolated.load() }
                catch { rejected = (error as NSError).domain == "StudioSession" }
                try check(rejected, "会话拒绝远程 \(field) 路径")
            }
            try Data("broken checkpoint".utf8).write(to: sessionStore.sessionURL)
            let fallback = try sessionStore.load()
            try check(fallback.recovered && fallback.session != nil && Data(contentsOf: sessionStore.backupURL) == validBackup,
                "主会话损坏后从有效备份恢复，不覆盖备份")
            try check(try fm.contentsOfDirectory(atPath: sessionStore.root.appendingPathComponent("Recovery").path).count > 0,
                "损坏会话另存至恢复目录，保留原始数据")
            let bad = root.appendingPathComponent("bad-state")
            try fm.createDirectory(at: bad, withIntermediateDirectories: true)
            let badStore = StudioSessionStore(root: bad)
            let broken = Data("invalid session".utf8)
            try broken.write(to: badStore.sessionURL)
            var unreadable = false
            do { _ = try badStore.load() }
            catch { unreadable = (error as NSError).domain == "StudioSession" }
            try check(try unreadable && Data(contentsOf: badStore.sessionURL) == broken, "恢复失败仍保留原文件")
            let fileRoot = root.appendingPathComponent("not-a-folder")
            try Data("KEEP".utf8).write(to: fileRoot)
            let blocked = StudioModel(sessionStore: StudioSessionStore(root: fileRoot))
            blocked.start(arguments: [])
            try check(!blocked.flushSession() && blocked.sessionNotice != nil, "无法保存时明确报告失败，退出前可阻止丢失修改")
            print("\n\(passed) session checks passed.")
        } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
