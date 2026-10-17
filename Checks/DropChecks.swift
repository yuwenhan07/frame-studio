import AppKit
import FrameCore
import UniformTypeIdentifiers

private final class PromiseFixture: NSObject, NSFilePromiseProviderDelegate {
    let name: String
    let bytes: Data?
    let delay: TimeInterval
    let queue = OperationQueue()
    init(_ name: String, bytes: Data?, delay: TimeInterval = 0) {
        self.name = name; self.bytes = bytes; self.delay = delay
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        queue.addOperation {
            if self.delay > 0 { Thread.sleep(forTimeInterval: self.delay) }
            do {
                guard let bytes = self.bytes else { throw NSError(domain: "PromiseFixture", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "模拟照片传输失败"]) }
                try bytes.write(to: url)
                completionHandler(nil)
            } catch { completionHandler(error) }
        }
    }
}

@main
@MainActor
struct DropChecks {
    static var passed = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "DropChecks", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
        passed += 1
        print("PASS: \(message)")
    }

    static func read(_ reader: PhotoDropImporter, _ pasteboard: NSPasteboard) async throws -> (PhotoDropResult, [(Int, Int)]) {
        var result: PhotoDropResult?
        var progress: [(Int, Int)] = []
        try check(reader.receive(pasteboard, progress: { progress.append(($0, $1)) }, completion: { result = $0 }), "拖入内容被接收")
        for _ in 0..<500 {
            if let result { return (result, progress) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "DropChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "等待拖入文件超时"])
    }

    static func main() async {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("yingkuang-drop-checks-\(UUID().uuidString)")
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally(); try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let original = root.appendingPathComponent("原片.png")
            let second = root.appendingPathComponent("第二张.png")
            let invalid = root.appendingPathComponent("无效照片.png")
            let context = CGContext(data: nil, width: 90, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 90, height: 60))
            try ImageWriter.save(context.makeImage()!, to: original, format: .png)
            let bytes = try Data(contentsOf: original)
            try bytes.write(to: second)
            try Data("not an image".utf8).write(to: invalid)
            let reader = PhotoDropImporter(cacheRoot: root.appendingPathComponent("cache"))

            pb.clearContents(); pb.setString("普通文字", forType: .string)
            try check(!reader.canRead(pb), "普通文字不会成为照片拖拽")

            pb.clearContents(); pb.writeObjects([second as NSURL, original as NSURL, invalid as NSURL])
            let (files, fileProgress) = try await read(reader, pb)
            try check(files.urls == [second, original], "Finder 多文件顺序保留，坏图片被排除")
            try check(files.failures.count == 1, "混合导入保留成功项并报告失败项")
            try check(fileProgress.first?.0 == 0 && fileProgress.last?.0 == 3 && fileProgress.last?.1 == 3, "进度从零推进至所有文件完成")

            pb.clearContents(); pb.writeObjects([original as NSURL, original as NSURL])
            let (duplicates, _) = try await read(reader, pb)
            try check(duplicates.urls == [original], "同一文件的重复路径只导入一次")

            pb.clearContents(); pb.setData(bytes, forType: .png)
            let (bitmap, _) = try await read(reader, pb)
            try check(bitmap.urls.count == 1 && bitmap.failures.isEmpty, "无路径的位图拖拽可导入")
            try check(try PhotoDocument(url: bitmap.urls[0]).width == 90, "位图被保存为后续可读取的 App 文件")

            let firstPromise = PromiseFixture("延迟照片.png", bytes: bytes, delay: 0.2)
            let secondPromise = PromiseFixture("快速照片.png", bytes: bytes)
            let failedPromise = PromiseFixture("失败照片.png", bytes: nil)
            let fixtures = [firstPromise, secondPromise, failedPromise]
            let providers = fixtures.map { NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: $0) }
            // AppKit only fulfills native promises inside a real drag operation.
            // Inject the transfer boundary for deterministic delayed/error checks;
            // the production NSFilePromiseReceiver path is also exercised via Photos UI.
            var fixtureIndex = 0
            let promiseReader = PhotoDropImporter(cacheRoot: root.appendingPathComponent("cache"), receivePromise: { _, destination, _, callback in
                let fixture = fixtures[fixtureIndex]
                let provider = providers[fixtureIndex]
                fixtureIndex += 1
                fixture.filePromiseProvider(provider, writePromiseTo: destination.appendingPathComponent(fixture.name), completionHandler: {
                    callback(destination.appendingPathComponent(fixture.name), $0)
                })
            })
            pb.clearContents(); pb.writeObjects(providers)
            try check(reader.canRead(pb), "接收与照片 App 一样的文件承诺类型")
            let (promises, promiseProgress) = try await read(promiseReader, pb)
            try check(promises.urls.map(\.lastPathComponent) == ["延迟照片.png", "快速照片.png"], "异步传输乱序完成后仍保留拖入顺序")
            try check(promises.failures.count == 1, "异步传输失败时保留其他成功照片")
            try check(promiseProgress.last?.0 == 3, "承诺文件进度等待成功和失败项全部结束")
            try check(try promises.urls.allSatisfy { try Data(contentsOf: $0) == bytes }, "承诺文件保留原始字节，未重新压缩")
            try check(promises.urls.allSatisfy { $0.deletingLastPathComponent() == promises.urls[0].deletingLastPathComponent() }, "同次拖拽的文件承诺使用同一接收目录")

            // A new model receives the same native drag path used by the App.
            let model = StudioModel()
            pb.clearContents(); pb.writeObjects([original as NSURL, second as NSURL])
            try check(model.receiveDrop(pb), "App 模型接收批量拖入")
            try check(model.isReceivingDrop && !model.canReceiveDrop(pb), "接收过程中阻止重复拖入")
            for _ in 0..<300 {
                if !model.isReceivingDrop && !model.isLoading { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try check(model.items.map(\.url) == [original, second] && model.photo?.width == 90, "传输结束后列表和预览正常加载")
            model.removePhoto(model.items[0].id)
            try check(try Data(contentsOf: original) == bytes, "列表移除不修改或删除源文件")
            model.isExporting = true
            try check(!model.receiveDrop(pb), "导出时不会启动新的文件传输")
            print("拖拽导入检查完成：\(passed) 项通过")
            withExtendedLifetime(providers) {}
            withExtendedLifetime([firstPromise, secondPromise, failedPromise]) {}
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
