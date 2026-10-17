import AppKit
import FrameCore

@MainActor
final class PaletteColorPanelHandler: NSObject {
    private let onChange: (NSColor) -> Void
    init(onChange: @escaping (NSColor) -> Void) { self.onChange = onChange }
    @objc func colorChanged(_ sender: NSColorPanel) { onChange(sender.color) }
}

struct EditablePaletteSwatch: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var color: PaletteColor
    var modified = false
}

struct SavedPhotoPalette: Codable {
    let fileSize: Int
    let modificationDate: Date?
    let swatches: [EditablePaletteSwatch]

    init?(url: URL, swatches: [EditablePaletteSwatch]) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        fileSize = size
        modificationDate = values.contentModificationDate
        self.swatches = swatches
    }

    func matches(_ url: URL) -> Bool {
        guard let current = SavedPhotoPalette(url: url, swatches: []) else { return false }
        return fileSize == current.fileSize && modificationDate == current.modificationDate
    }

    static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().absoluteString
    }
}

struct SavedColorWalkColor: Codable {
    let fileSize: Int
    let modificationDate: Date?
    let color: PaletteColor

    init?(url: URL, color: PaletteColor) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        fileSize = size
        modificationDate = values.contentModificationDate
        self.color = color
    }

    func matches(_ url: URL) -> Bool {
        guard let current = SavedColorWalkColor(url: url, color: color) else { return false }
        return fileSize == current.fileSize && modificationDate == current.modificationDate
    }
}
