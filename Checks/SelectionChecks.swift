import AppKit
import FrameCore

@main
@MainActor
struct SelectionChecks {
    static var passed = 0

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "SelectionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        passed += 1
        print("PASS: \(message)")
    }

    static func waitForPhoto(_ model: StudioModel, _ url: URL) async throws {
        for _ in 0..<150 {
            if !model.isLoading {
                guard model.photo?.url == url else {
                    throw NSError(domain: "SelectionChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "照片加载结果不符合预期"])
                }
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "SelectionChecks", code: 3, userInfo: [NSLocalizedDescriptionKey: "照片加载超时"])
    }

    static func waitForPreview(_ model: StudioModel) async throws {
        for _ in 0..<200 {
            if !model.isRendering && model.preview != nil { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "SelectionChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "预览渲染超时"])
    }

    static func fixture(_ url: URL, width: Int, height: Int, color: NSColor = .systemOrange, otherColor: NSColor? = nil) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let otherColor {
            context.setFillColor(otherColor.cgColor)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        try ImageWriter.save(context.makeImage()!, to: url, format: .png)
    }

    static func main() async {
        let savedStyle = UserDefaults.standard.data(forKey: "frameStyle.v1")
        let savedPalettes = UserDefaults.standard.data(forKey: "manualPalettes.v1")
        let savedWalk = UserDefaults.standard.data(forKey: "colorWalkColors.v1")
        defer {
            UserDefaults.standard.set(savedStyle, forKey: "frameStyle.v1")
            UserDefaults.standard.set(savedPalettes, forKey: "manualPalettes.v1")
            UserDefaults.standard.set(savedWalk, forKey: "colorWalkColors.v1")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yingkuang-selection-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let a = root.appendingPathComponent("a-landscape.png")
            let b = root.appendingPathComponent("b-portrait.png")
            let c = root.appendingPathComponent("c-square.png")
            try fixture(a, width: 80, height: 60, otherColor: .systemGreen)
            try fixture(b, width: 60, height: 90)
            try fixture(c, width: 70, height: 70, color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            let originals = try [a, b, c].map { ($0, try Data(contentsOf: $0)) }
            let model = StudioModel()
            model.importPhotos([a, b, c])
            try await waitForPhoto(model, a)
            let ids = model.items.map { $0.id }
            let remote = URL(string: "https://example.invalid/photo.jpg")!
            model.importPhotos([remote])
            try check(model.items.map(\.id) == ids && model.photo?.url == a && model.errorMessage != nil,
                      "远程 URL 不替换当前列表或预览，并明确报告不支持")
            model.errorMessage = nil
            let alias = root.appendingPathComponent("b-alias.png")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
            for destination in [a, b, alias] {
                do {
                    try ImageWriter.save(model.photo!.image, to: destination, format: .png,
                                         protecting: model.protectedExportSources)
                    try check(false, "不能覆盖任何已导入原片")
                } catch FrameError.originalProtected {
                    try check(true, "单张导出保护当前原片、其他列表原片及符号链接别名：\(destination.lastPathComponent)")
                }
            }
            let allowed = root.appendingPathComponent("new-export.png")
            try ImageWriter.save(model.photo!.image, to: allowed, format: .png, protecting: model.protectedExportSources)
            try check(FileManager.default.fileExists(atPath: allowed.path)
                      && originals.allSatisfy { (try? Data(contentsOf: $0.0)) == $0.1 },
                      "新目标可导出，拒绝覆盖的三张原片逐字节保持不变")
            try check(ids.count == 3 && model.batchSelectedCount == 0, "导入后批量选择为空，避免误操作全部照片")
            model.exportBatch()
            try check(model.inspectorTab == 2 && !model.isExporting, "空选择只打开右侧选择区，不导出全部")
            model.setBatchSelection(ids[1], selected: true)
            model.setBatchSelection(ids[2], selected: true)
            try check(model.selectedID == ids[0] && model.photo?.url == a, "批量勾选不改变当前预览")
            model.selectPhoto(ids[1])
            try await waitForPhoto(model, b)
            model.metadata.iso = "640"
            model.selectPhoto(ids[0])
            try await waitForPhoto(model, a)
            let jobs = model.batchJobsForSelection()
            try check(jobs.map { $0.url } == [b, c], "部分选择只生成已选照片的任务，并保留列表顺序")
            try check(jobs[0].metadataOverride?.iso == "640", "已选照片保留各自的手动拍摄参数")
            model.selectTemplate(.colorCircles)
            try check(model.inspectorTab == 1 && model.batchSelectedIDs == [ids[1], ids[2]] && model.photo?.url == a,
                      "切换颜色模板打开样式面板，保持照片和批量勾选")
            model.style.paletteCount = 2
            try await waitForPreview(model)
            model.selectPhoto(ids[2])
            try await waitForPhoto(model, c)
            try await waitForPreview(model)
            try check(model.paletteColors.map { $0.hex } == ["#0000FF"], "切换照片后预览色卡来自新照片，不残留旧缓存")
            model.style.signature = "保留 / Keep"
            model.style.signatureEnglishFont = "Courier"
            model.resetPaletteStyle()
            try check(model.style.paletteCount == 5 && model.style.signature == "保留 / Keep"
                      && model.style.signatureEnglishFont == "Courier", "恢复色卡样式保留个人落款和字体选择")
            model.selectPhoto(ids[0])
            try await waitForPhoto(model, a)
            try await waitForPreview(model)
            let firstSwatch = model.paletteSwatches[0].id
            let secondSwatch = model.paletteSwatches[1].id
            model.setPaletteHex("#123456", photoID: ids[0], swatchID: firstSwatch)
            try check(model.paletteColors[0].hex == "#123456" && model.paletteHex(for: firstSwatch) == "#123456"
                      && model.hasManualPalette, "逐个修改 HEX 后色块与色号同步进入手动模式")
            model.setPaletteHex("GGGGGG", photoID: ids[0], swatchID: firstSwatch)
            try check(model.paletteColors[0].hex == "#123456", "无效 HEX 草稿不污染已生效颜色")
            model.commitPaletteHex(photoID: ids[0], swatchID: firstSwatch)
            try check(model.paletteHex(for: firstSwatch) == "#123456", "提交无效 HEX 后恢复最后有效色号")
            model.setPaletteColor(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1), photoID: ids[0], swatchID: firstSwatch)
            try check(model.paletteColors[0].hex == "#FF00FF", "选色器的 sRGB 颜色同步生成 HEX")
            model.setPaletteHex("#123456", photoID: ids[0], swatchID: firstSwatch)
            model.removePaletteColor(photoID: ids[0], swatchID: secondSwatch)
            try check(model.paletteSwatches.count == 1 && model.paletteSwatches[0].id == firstSwatch,
                      "删除单个色块后保留其他色块的颜色和稳定 ID")
            model.setPaletteHex("#FFFFFF", photoID: ids[0], swatchID: secondSwatch)
            try check(model.paletteColors.map { $0.hex } == ["#123456"], "失效选色器回调不会修改删除后移位的色块")
            model.selectPhoto(ids[1])
            try await waitForPhoto(model, b)
            try await waitForPreview(model)
            let bSwatch = model.paletteSwatches[0].id
            try check(!model.hasManualPalette && model.paletteColors[0].hex != "#123456", "切换照片不沿用上一张的手动颜色")
            model.setPaletteHex("#ABCDEF", photoID: ids[1], swatchID: bSwatch)
            model.setPaletteHex("#FFFFFF", photoID: ids[0], swatchID: firstSwatch)
            try check(model.paletteColors[0].hex == "#ABCDEF", "旧照片的选色器回调不能改动当前照片")
            model.selectAllForBatch()
            let manualJobs = model.batchJobsForSelection()
            try check(manualJobs[0].paletteOverride?.map { $0.hex } == ["#123456"]
                      && manualJobs[1].paletteOverride?.map { $0.hex } == ["#ABCDEF"]
                      && manualJobs[2].paletteOverride == nil, "批量任务分别冻结两张手动色卡和一张自动色卡")
            model.selectPhoto(ids[0])
            try await waitForPhoto(model, a)
            try await waitForPreview(model)
            try check(model.paletteColors.map { $0.hex } == ["#123456"], "切回照片后保留改色与删除结果")
            model.setPaletteHex("#112233", photoID: ids[0], swatchID: firstSwatch)
            try check(manualJobs[0].paletteOverride?.first?.hex == "#123456", "导出任务快照不被后续编辑改变")
            let reopened = StudioModel()
            reopened.importPhotos([a])
            try await waitForPhoto(reopened, a)
            try await waitForPreview(reopened)
            try check(reopened.paletteColors.map { $0.hex } == ["#112233"], "新会话重新导入原片后恢复手动色卡")
            model.removePaletteColor(photoID: ids[0], swatchID: firstSwatch)
            try await waitForPreview(model)
            try check(model.paletteColors.isEmpty && model.hasManualPalette
                      && model.batchJobsForSelection()[0].paletteOverride == [], "全部删除保留显式空色卡，预览和批量任务均不补回颜色")
            let reopenedEmpty = StudioModel()
            reopenedEmpty.importPhotos([a])
            try await waitForPhoto(reopenedEmpty, a)
            try await waitForPreview(reopenedEmpty)
            try check(reopenedEmpty.hasManualPalette && reopenedEmpty.paletteColors.isEmpty, "空色卡跨会话恢复后仍保持为空")
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: a.path)
            let changedSource = StudioModel()
            changedSource.importPhotos([a])
            try await waitForPhoto(changedSource, a)
            try await waitForPreview(changedSource)
            try check(!changedSource.hasManualPalette && changedSource.paletteColors.count == 2,
                      "同路径原片发生变化后重新取色，不套用旧文件记录")
            model.restoreAutomaticPalette()
            try await waitForPreview(model)
            try check(!model.hasManualPalette && model.paletteColors.count == 2, "恢复自动取色清除手动颜色和删除记录")
            model.clearBatchSelection()
            model.setBatchSelection(ids[1], selected: true)
            model.setBatchSelection(ids[2], selected: true)
            let output = root.appendingPathComponent("exports")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let report = BatchExporter.run(jobs: jobs, folder: output, style: FrameStyle(), size: .standard,
                                           format: .png, control: BatchControl())
            let outputs = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
            try check(report.succeeded == 2 && outputs == ["b-portrait-映框.png", "c-square-映框.png"],
                      "实际导出目录只包含已勾选的两张照片")
            model.invertBatchSelection()
            try check(model.batchSelectedIDs == [ids[0]], "反选得到精确的剩余照片")
            model.selectAllForBatch()
            try check(model.batchSelectedCount == 3, "全选覆盖当前列表")
            model.clearBatchSelection()
            try check(model.batchJobsForSelection().isEmpty, "取消全选后没有导出任务")
            model.setBatchSelection(UUID(), selected: true)
            try check(model.batchSelectedCount == 0, "忽略不在列表中的选择 ID")
            model.setBatchSelection(ids[1], selected: true)
            model.setBatchSelection(ids[2], selected: true)
            model.removeBatchSelectedPhotos()
            try check(model.items.map { $0.url } == [a] && model.selectedID == ids[0], "移除已选只移除勾选项，保留未勾选预览")
            try check(model.batchSelectedCount == 0 && model.photo?.url == a, "移除后清理勾选，保留有效画布")
            try check(try originals.allSatisfy { try Data(contentsOf: $0.0) == $0.1 }, "移除 App 条目后所有原片逐字节保持不变")
            try check(try FileManager.default.contentsOfDirectory(atPath: output.path).sorted() == outputs,
                      "移除 App 条目不删除已导出的文件")
            model.importPhotos([b, c])
            try await waitForPhoto(model, b)
            let current = model.items.first { $0.url == b }!.id
            let first = model.items.first { $0.url == a }!.id
            model.setBatchSelection(first, selected: true)
            model.setBatchSelection(current, selected: true)
            model.removeBatchSelectedPhotos()
            try await waitForPhoto(model, c)
            try check(model.items.map { $0.url } == [c] && model.photo?.url == c, "移除当前预览后切换到相邻保留照片")
            model.importPhotos([a])
            // Remove everything while the newly selected image is still loading.
            model.selectAllForBatch()
            model.removeBatchSelectedPhotos()
            try await Task.sleep(nanoseconds: 200_000_000)
            try check(model.items.isEmpty && model.photo == nil && model.preview == nil && model.selectedID == nil,
                      "全选移除后清空画布，旧异步读取不会把图片加回来")
            try check(model.batchSelectedCount == 0 && !model.isLoading, "空列表没有残留勾选或加载状态")
            try check(model.paletteColors.isEmpty, "全部移除后清空旧照片色卡")
            try check(try originals.allSatisfy { try Data(contentsOf: $0.0) == $0.1 }, "全选移除后磁盘原片仍完整保留")
            let walk = StudioModel()
            walk.importPhotos([a, c])
            walk.selectTemplate(.colorWalk)
            try await waitForPhoto(walk, a)
            try await waitForPreview(walk)
            let walkA = walk.items[0].id, walkC = walk.items[1].id
            try check(walk.colorWalkColor != nil && !walk.hasManualColorWalkColor && walk.inspectorTab == 1,
                "选择 Color Walk 后加载自动主色并打开编辑区")
            let autoWalk = walk.colorWalkColor
            walk.setColorWalkHex("#A9696B", photoID: walkA)
            try await waitForPreview(walk)
            try check(walk.colorWalkColor?.hex == "#A9696B" && walk.hasManualColorWalkColor, "Color Walk 手动 HEX 同步到预览")
            walk.setColorWalkHex("#XX", photoID: walkA)
            walk.commitColorWalkHex(photoID: walkA)
            try check(walk.colorWalkHex == "#A9696B", "非法主色草稿不会改变已生效的颜色")
            walk.selectAllForBatch()
            let walkJobs = walk.batchJobsForSelection()
            try check(walkJobs[0].colorWalkOverride?.hex == "#A9696B" && walkJobs[1].colorWalkOverride == nil,
                "批量任务分别冻结手动主色与自动主色")
            walk.selectPhoto(walkC)
            try await waitForPhoto(walk, c)
            try await waitForPreview(walk)
            try check(walk.colorWalkColor?.hex == "#1E1EF3" && !walk.hasManualColorWalkColor, "切换照片独立识别并柔化 Color Walk 自动主色")
            walk.setColorWalkColor(.red, photoID: walkA)
            try check(walk.colorWalkColor?.hex == "#1E1EF3", "旧照片选色器回调不会污染当前照片")
            walk.setColorWalkColor(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), photoID: walkC)
            try check(walk.colorWalkHex == "#00FF00", "系统选色器同步更新 Color Walk HEX")
            let reopenedWalk = StudioModel()
            reopenedWalk.importPhotos([a])
            reopenedWalk.selectTemplate(.colorWalk)
            try await waitForPhoto(reopenedWalk, a)
            try await waitForPreview(reopenedWalk)
            try check(reopenedWalk.colorWalkColor?.hex == "#A9696B", "Color Walk 手动主色按照片跨会话恢复")
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: a.path)
            let changedWalk = StudioModel()
            changedWalk.importPhotos([a]); changedWalk.selectTemplate(.colorWalk)
            try await waitForPhoto(changedWalk, a)
            try await waitForPreview(changedWalk)
            try check(!changedWalk.hasManualColorWalkColor, "原片变化后不沿用旧主色")
            reopenedWalk.restoreAutomaticColorWalkColor()
            try await waitForPreview(reopenedWalk)
            try check(reopenedWalk.colorWalkColor == autoWalk && !reopenedWalk.hasManualColorWalkColor, "恢复自动主色清除当前照片的手动颜色")
            walk.style.colorWalkStamp = "保留文字"
            walk.style.colorWalkHeader = 0.9
            walk.style.colorWalkTextPosition = 0.88
            walk.resetColorWalkStyle()
            try check(walk.style.colorWalkHeader == 0.585 && walk.style.colorWalkTextPosition == 0.50
                && walk.style.colorWalkStamp == "保留文字", "恢复默认版式重置位置并保留自定义盖章文字")
            walk.selectTemplate(.colorCircles)
            try await waitForPreview(walk)
            try check(!walk.hasManualPalette && walk.paletteColors.first?.hex == "#0000FF", "Color Walk 改色不污染圆形色卡")
            walk.selectAllForBatch(); walk.removeBatchSelectedPhotos()
            try check(walk.colorWalkColor == nil && walk.colorWalkHex.isEmpty, "清空列表后不残留 Color Walk 颜色")
            print("\n\(passed) selection checks passed.")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
