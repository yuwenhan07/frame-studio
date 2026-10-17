import Foundation
import AppKit
import FrameCore

struct PhotoFileIdentity: Codable, Equatable, Sendable {
    let size: Int
    let modified: Date?
    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        self.size = size
        modified = values.contentModificationDate
    }
}

struct StudioSession: Codable {
    var version = 1
    var photos: [PhotoQueueItem]
    var selectedID: UUID?
    var batchSelectedIDs: Set<UUID>
    var style: FrameStyle
    var format: ExportFormat
    var exportSize: ExportSize
    var inspectorTab: Int
    var logoURL: URL?
    var logoName: String?
    var batchFolder: URL?
}

final class StudioSessionStore {
    let root: URL
    let legacyImportRoot: URL
    var sessionURL: URL { root.appendingPathComponent("Session.json") }
    var backupURL: URL { root.appendingPathComponent("Session.previous.json") }
    var importedPhotos: URL { root.appendingPathComponent("Imported Photos", isDirectory: true) }

    init(root: URL, legacyImportRoot: URL? = nil) {
        self.root = root
        self.legacyImportRoot = legacyImportRoot ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.wenhanyu.frame-studio/Imported Photos", isDirectory: true)
    }

    static func standard() -> StudioSessionStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.wenhanyu.frame-studio", isDirectory: true)
        return StudioSessionStore(root: folder)
    }

    func load() throws -> (session: StudioSession?, recovered: Bool) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: sessionURL.path) || manager.fileExists(atPath: backupURL.path) else { return (nil, false) }
        if let state = try? decode(Data(contentsOf: sessionURL)) { return (state, false) }
        if let state = try? decode(Data(contentsOf: backupURL)) {
            try preserveUnreadableSession()
            return (state, true)
        }
        throw NSError(domain: "StudioSession", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "上次会话文件无法读取，已保留文件以便恢复。"])
    }

    private func decode(_ data: Data) throws -> StudioSession {
        let session = try JSONDecoder().decode(StudioSession.self, from: data)
        guard session.version == 1 else {
            throw NSError(domain: "StudioSession", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "会话来自不同版本，请使用对应版本打开。"])
        }
        guard session.photos.allSatisfy({ $0.url.isFileURL && $0.exportedTo?.isFileURL != false }),
              session.logoURL?.isFileURL != false, session.batchFolder?.isFileURL != false,
              Set(session.photos.map(\.id)).count == session.photos.count,
              Set(session.photos.map { SavedPhotoPalette.key(for: $0.url) }).count == session.photos.count else {
            throw NSError(domain: "StudioSession", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "会话中的照片记录不完整。"])
        }
        return session
    }

    func preserveUnreadableSession() throws {
        let folder = root.appendingPathComponent("Recovery/\(UUID().uuidString)", isDirectory: true)
        try privateDirectory(folder)
        for url in [sessionURL, backupURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
        }
    }

    func save(_ session: StudioSession) throws {
        try privateDirectory(root)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(session)
        let previous = try? Data(contentsOf: sessionURL)
        if previous == data {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionURL.path)
            return
        }
        // Keep a valid previous checkpoint, then atomically replace the main file.
        if let previous, (try? decode(previous)) != nil {
            try previous.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }
        try data.write(to: sessionURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionURL.path)
    }

    /// Retain only App-owned Photos transfer files. Finder originals remain in place.
    func retainImportedPhoto(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw FrameError.localFilesOnly }
        let source = url.standardizedFileURL.resolvingSymlinksInPath()
        let cache = legacyImportRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard source.path.hasPrefix(cache.path + "/") else { return url }
        var folder = importedPhotos.appendingPathComponent(source.deletingLastPathComponent().lastPathComponent, isDirectory: true)
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            if let identity = PhotoFileIdentity(url: source), identity == PhotoFileIdentity(url: destination) { return destination }
            folder = importedPhotos.appendingPathComponent(UUID().uuidString, isDirectory: true)
            destination = folder.appendingPathComponent(source.lastPathComponent)
        }
        try privateDirectory(folder)
        let temporary = folder.appendingPathComponent(".copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    func saveLogo(_ image: CGImage) throws -> URL {
        let folder = root.appendingPathComponent("Logos", isDirectory: true)
        try privateDirectory(folder)
        let url = folder.appendingPathComponent(UUID().uuidString + ".png")
        try ImageWriter.save(image, to: url, format: .png)
        return url
    }

    private func privateDirectory(_ folder: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }
}
