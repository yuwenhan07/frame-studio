import Foundation
import CoreGraphics

public struct BatchJob: Sendable {
    public let url: URL
    public let metadataOverride: PhotoMetadata?
    public let paletteOverride: [PaletteColor]?
    public let colorWalkOverride: PaletteColor?
    public init(url: URL, metadataOverride: PhotoMetadata? = nil, paletteOverride: [PaletteColor]? = nil, colorWalkOverride: PaletteColor? = nil) {
        self.url = url
        self.metadataOverride = metadataOverride
        self.paletteOverride = paletteOverride
        self.colorWalkOverride = colorWalkOverride
    }
}

public struct BatchItemResult: Sendable {
    public let sourceURL: URL
    public let outputURL: URL?
    public let error: String?
}

public struct BatchReport: Sendable {
    public let results: [BatchItemResult]
    public let remaining: Int
    public var succeeded: Int { results.filter { $0.outputURL != nil }.count }
    public var failed: Int { results.filter { $0.error != nil }.count }
}

public final class BatchControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

public enum BatchExporter {
    // Decode, render and release one photograph at a time, even for large batches.
    public static func run(jobs: [BatchJob], folder: URL, style: FrameStyle, size: ExportSize,
                           format: ExportFormat, logo: CGImage? = nil, control: BatchControl,
                           willStart: (Int, URL) -> Void = { _, _ in },
                           didFinish: (BatchItemResult, Int) -> Void = { _, _ in }) -> BatchReport {
        let renderer = FrameRenderer()
        var results: [BatchItemResult] = []
        for job in jobs {
            if control.isCancelled { break }
            willStart(results.count + 1, job.url)
            let result: BatchItemResult = autoreleasepool {
                let access = job.url.startAccessingSecurityScopedResource()
                defer { if access { job.url.stopAccessingSecurityScopedResource() } }
                do {
                    let photo = try PhotoDocument(url: job.url)
                    let image = try renderer.render(photo: photo, metadata: job.metadataOverride ?? photo.metadata,
                        style: style, width: size.width(for: photo, style: style), logo: logo, palette: job.paletteOverride,
                        colorWalkColor: job.colorWalkOverride)
                    let url = try saveUnique(image, source: job.url, folder: folder, format: format)
                    return BatchItemResult(sourceURL: job.url, outputURL: url, error: nil)
                } catch {
                    return BatchItemResult(sourceURL: job.url, outputURL: nil, error: error.localizedDescription)
                }
            }
            results.append(result)
            didFinish(result, results.count)
        }
        return BatchReport(results: results, remaining: jobs.count - results.count)
    }

    private static func saveUnique(_ image: CGImage, source: URL, folder: URL, format: ExportFormat) throws -> URL {
        let manager = FileManager.default
        let temporary = folder.appendingPathComponent(".yingkuang-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        // Finish encoding before publishing the output. moveItem never overwrites a destination.
        try ImageWriter.save(image, to: temporary, format: format)
        let stem = source.deletingPathExtension().lastPathComponent + "-映框"
        var count = 1
        while true {
            let name = stem + (count == 1 ? "" : "-\(count)") + "." + format.fileExtension
            let candidate = folder.appendingPathComponent(name)
            if manager.fileExists(atPath: candidate.path) { count += 1; continue }
            do {
                try manager.moveItem(at: temporary, to: candidate)
                return candidate
            } catch {
                // Also handle a file created by another process between the check and the move.
                if manager.fileExists(atPath: candidate.path) && manager.fileExists(atPath: temporary.path) {
                    count += 1
                } else { throw error }
            }
        }
    }
}
