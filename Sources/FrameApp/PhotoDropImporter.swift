import AppKit
import ImageIO
import UniformTypeIdentifiers

struct PhotoDropResult {
    var urls: [URL] = []
    var failures: [String] = []
}

typealias PhotoPromiseReader = (NSFilePromiseReceiver, URL, OperationQueue, @escaping (URL, Error?) -> Void) -> Void

/// Photos supplies file promises rather than existing file URLs. Keep receivers alive
/// until every promised file is ready, and import only after the transfer finishes.
@MainActor
final class PhotoDropImporter {
    static let draggedTypes: [NSPasteboard.PasteboardType] =
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        + [.fileURL, .png, .tiff]

    private let cacheRoot: URL
    private let receivePromise: PhotoPromiseReader
    private var sessions: [UUID: PhotoDropSession] = [:]

    init(cacheRoot: URL? = nil, receivePromise: @escaping PhotoPromiseReader = { receiver, destination, queue, reader in
        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue, reader: reader)
    }) {
        self.cacheRoot = cacheRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.wenhanyu.frame-studio/Imported Photos", isDirectory: true)
        self.receivePromise = receivePromise
    }

    func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: Self.draggedTypes) != nil
    }

    @discardableResult
    func receive(_ pasteboard: NSPasteboard, progress: @escaping (Int, Int) -> Void,
                 completion: @escaping (PhotoDropResult) -> Void) -> Bool {
        // The class order is significant: a file promise may also offer a preview
        // URL or bitmap. Prefer the original promised file and never import both.
        let objects = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self, NSURL.self, NSImage.self],
            options: [.urlReadingFileURLsOnly: true]) ?? []
        guard !objects.isEmpty else { return false }
        let id = UUID()
        let session = PhotoDropSession(objects: objects,
            destination: cacheRoot.appendingPathComponent(id.uuidString, isDirectory: true), receivePromise: receivePromise, progress: progress) { [weak self] result in
                self?.sessions.removeValue(forKey: id)
                completion(result)
            }
        sessions[id] = session
        session.start()
        return true
    }
}

@MainActor
private final class PhotoDropSession {
    private let objects: [Any]
    private let destination: URL
    private let receivePromise: PhotoPromiseReader
    private let progress: (Int, Int) -> Void
    private let completion: (PhotoDropResult) -> Void
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.yingkuang.receive-photos"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private var total = 0
    private var completed = 0
    private var results: [(Int, Int, Result<URL, Error>)] = []
    private var finished = false

    init(objects: [Any], destination: URL, receivePromise: @escaping PhotoPromiseReader, progress: @escaping (Int, Int) -> Void,
         completion: @escaping (PhotoDropResult) -> Void) {
        self.objects = objects
        self.destination = destination
        self.receivePromise = receivePromise
        self.progress = progress
        self.completion = completion
    }

    func start() {
        total = objects.reduce(0) { $0 + (($1 as? NSFilePromiseReceiver).map { max(1, $0.fileNames.count) } ?? 1) }
        progress(0, total)
        do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700]) }
        catch {
            finished = true
            completion(PhotoDropResult(failures: ["无法准备照片导入目录：\(error.localizedDescription)"]))
            return
        }
        for (index, object) in objects.enumerated() {
            switch object {
            case let receiver as NSFilePromiseReceiver:
                // Every receiver in one drag must use the same destination.
                let names = receiver.fileNames
                receivePromise(receiver, destination, queue) { [self] url, error in
                    let result = Result<URL, Error> {
                        if let error { throw error }
                        return try Self.validate(url)
                    }
                    let subindex = names.firstIndex(of: url.lastPathComponent) ?? 0
                    DispatchQueue.main.async { self.record(result, index: index, subindex: subindex) }
                }
            case let url as URL:
                queue.addOperation { [self] in
                    let result = Result { try Self.validate(url) }
                    DispatchQueue.main.async { self.record(result, index: index) }
                }
            case let image as NSImage:
                // Bitmap-only drags have no original file. Retain the representation
                // in an App-owned file so future exports do not depend on a pasteboard.
                let data = image.tiffRepresentation
                let url = destination.appendingPathComponent("拖入照片-\(index + 1).tiff")
                queue.addOperation { [self] in
                    let result = Result<URL, Error> {
                        guard let data else { throw Self.invalidImage }
                        try data.write(to: url, options: .atomic)
                        return try Self.validate(url)
                    }
                    DispatchQueue.main.async { self.record(result, index: index) }
                }
            default:
                record(.failure(Self.invalidImage), index: index)
            }
        }
    }

    nonisolated private static var invalidImage: NSError {
        NSError(domain: "PhotoDrop", code: 1, userInfo: [NSLocalizedDescriptionKey: "拖入内容不是可读取的照片"])
    }

    nonisolated private static func validate(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw invalidImage }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw NSError(domain: "PhotoDrop", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent)：无法读取图片文件"])
        }
        return url
    }

    private func record(_ result: Result<URL, Error>, index: Int, subindex: Int = 0) {
        guard !finished else { return }
        results.append((index, subindex, result))
        completed += 1
        progress(completed, total)
        guard completed == total else { return }
        finished = true
        var output = PhotoDropResult()
        var seen: Set<URL> = []
        for (_, _, result) in results.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) {
            switch result {
            case .success(let url):
                if seen.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted { output.urls.append(url) }
            case .failure(let error): output.failures.append(error.localizedDescription)
            }
        }
        completion(output)
    }
}
