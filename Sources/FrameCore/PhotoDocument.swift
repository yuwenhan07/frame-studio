import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum FrameError: LocalizedError {
    case unreadable, oversized, rendering, encoding, localFilesOnly, originalProtected
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取这张图片。请尝试 JPEG、PNG、HEIC 或 TIFF 文件。"
        case .oversized: return "图片尺寸过大，请将图片或导出尺寸控制在 8,000 万像素以内。"
        case .rendering: return "图片渲染失败，请尝试较小的导出尺寸。"
        case .encoding: return "图片保存失败，请检查保存位置是否可写。"
        case .localFilesOnly: return "只支持 Mac 上的本地图片文件。"
        case .originalProtected: return "请选择一个新的文件名，保留列表中所有导入的原始照片。"
        }
    }
}

public struct PhotoMetadata: Codable, Equatable, Sendable {
    public var brand = ""
    public var camera = ""
    public var focalLength = ""
    public var aperture = ""
    public var shutter = ""
    public var iso = ""
    public var lens = ""
    public var captureDateTime: String?
    public init() {}

    public static func read(_ properties: [CFString: Any]) -> PhotoMetadata {
        var result = PhotoMetadata()
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let make = (tiff[kCGImagePropertyTIFFMake] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = make.lowercased()
        if lower.contains("nikon") { result.brand = "Nikon" }
        else if lower.contains("canon") { result.brand = "Canon" }
        else if lower.contains("sony") { result.brand = "SONY" }
        else if lower.contains("fujifilm") { result.brand = "FUJIFILM" }
        else if lower.contains("olympus") { result.brand = "OLYMPUS" }
        else if lower.contains("panasonic") { result.brand = "LUMIX" }
        else if lower.contains("apple") { result.brand = "Apple" }
        else { result.brand = make }
        result.camera = (tiff[kCGImagePropertyTIFFModel] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = exif[kCGImagePropertyExifFocalLength] as? NSNumber {
            result.focalLength = String(format: "%.1f", value.doubleValue)
        }
        if let value = exif[kCGImagePropertyExifFNumber] as? NSNumber {
            result.aperture = String(format: "%.1f", value.doubleValue)
        }
        if let value = exif[kCGImagePropertyExifExposureTime] as? NSNumber {
            result.shutter = formatExposure(value.doubleValue)
        }
        if let values = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let value = values.first {
            result.iso = value.stringValue
        }
        result.lens = exif[kCGImagePropertyExifLensModel] as? String ?? ""
        result.captureDateTime = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        return result
    }

    public static func formatExposure(_ seconds: Double) -> String {
        guard seconds > 0, seconds.isFinite else { return "" }
        if seconds < 1 {
            let reciprocal = (1 / seconds).rounded()
            guard reciprocal.isFinite, reciprocal < Double(Int.max) else { return "" }
            return "1/\(Int(reciprocal))"
        }
        return seconds == seconds.rounded() ? String(format: "%.0fs", seconds) : String(format: "%.1fs", seconds)
    }

    public var parameterLine: String {
        [unit(focalLength, prefix: "", suffix: "mm"),
         unit(aperture, prefix: "f/", suffix: ""), shutter,
         unit(iso, prefix: "ISO", suffix: "")].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    private func unit(_ value: String, prefix: String, suffix: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var text = trimmed
        if !prefix.isEmpty && !text.lowercased().hasPrefix(prefix.lowercased()) { text = prefix + text }
        if !suffix.isEmpty && !text.lowercased().hasSuffix(suffix.lowercased()) { text += suffix }
        return text
    }
}

// All properties are immutable; CGImage is shared read-only between the UI and render queues.
public final class PhotoDocument: @unchecked Sendable {
    public let url: URL
    public let image: CGImage
    public let preview: CGImage
    public let metadata: PhotoMetadata
    public let palette: PhotoPalette
    public var width: Int { image.width }
    public var height: Int { image.height }
    public var name: String { url.deletingPathExtension().lastPathComponent }

    public init(url: URL) throws {
        guard url.isFileURL else { throw FrameError.localFilesOnly }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw FrameError.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard w > 0, h > 0 else { throw FrameError.unreadable }
        guard Double(w) * Double(h) <= 80_000_000 else { throw FrameError.oversized }
        // ImageIO applies EXIF rotations and mirrors, including portrait phone photos.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw FrameError.unreadable }
        var previewOptions = options
        previewOptions[kCGImageSourceThumbnailMaxPixelSize] = 1800
        self.url = url
        self.image = image
        self.preview = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary) ?? image
        self.metadata = PhotoMetadata.read(properties)
        self.palette = PhotoPalette(image: self.preview)
    }
}

public enum ExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case jpeg = "JPEG", png = "PNG"
    public var id: String { rawValue }
    public var fileExtension: String { self == .jpeg ? "jpg" : "png" }
    public var contentType: UTType { self == .jpeg ? .jpeg : .png }
}

public enum ImageWriter {
    public static func validateDestination(_ url: URL, protecting sources: [URL]) throws {
        guard url.isFileURL else { throw FrameError.localFilesOnly }
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        guard !sources.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == destination }) else {
            throw FrameError.originalProtected
        }
    }

    public static func save(_ image: CGImage, to url: URL, format: ExportFormat, quality: Double = 0.96,
                            protecting sources: [URL] = []) throws {
        try validateDestination(url, protecting: sources)
        // Encode fully before an atomic write; a failed export cannot truncate an existing file.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.contentType.identifier as CFString, 1, nil) else { throw FrameError.encoding }
        let settings: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, settings as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FrameError.encoding }
        try (data as Data).write(to: url, options: .atomic)
    }
}
