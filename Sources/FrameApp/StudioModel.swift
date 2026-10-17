import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FrameCore

struct PhotoQueueItem: Identifiable, Codable, Sendable {
    var id = UUID()
    var url: URL
    var demo = false
    var metadata: PhotoMetadata?
    var width: Int?
    var height: Int?
    var exportedTo: URL?
    var exportError: String?
    var paletteOverride: [EditablePaletteSwatch]?
    var colorWalkOverride: PaletteColor?
    var sourceIdentity: PhotoFileIdentity?
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var dropTargeted = false
    @Published var inspectorTab = 0 { didSet { scheduleSessionSave() } }
    @Published var items: [PhotoQueueItem] = [] { didSet { scheduleSessionSave() } }
    @Published private(set) var batchSelectedIDs: Set<UUID> = [] { didSet { scheduleSessionSave() } }
    @Published var selectedID: UUID? { didSet { scheduleSessionSave() } }
    @Published var sessionNotice: String?
    @Published var photo: PhotoDocument?
    @Published var preview: NSImage?
    @Published private(set) var paletteSwatches: [EditablePaletteSwatch] = []
    @Published private var paletteHexDrafts: [UUID: String] = [:]
    @Published private(set) var colorWalkColor: PaletteColor?
    @Published private var colorWalkHexDraft: String?
    private var automaticColorWalkColor: PaletteColor?
    private var savedColorWalkColors: [String: SavedColorWalkColor] = [:]
    private var editingColorWalkPhotoID: UUID?
    var colorWalkHex: String { colorWalkHexDraft ?? colorWalkColor?.hex ?? "" }
    var hasManualColorWalkColor: Bool { items.first(where: { $0.id == selectedID })?.colorWalkOverride != nil }
    var paletteColors: [PaletteColor] { paletteSwatches.map(\.color) }
    var hasManualPalette: Bool {
        items.first(where: { $0.id == selectedID })?.paletteOverride != nil
    }
    private var automaticPalette: [PaletteColor] = []
    private var paletteSettings: (count: Int, order: PaletteOrder)?
    private var savedPalettes: [String: SavedPhotoPalette] = [:]
    private var palettePanelHandler: PaletteColorPanelHandler?
    private var editingPaletteSwatch: (photoID: UUID, swatchID: UUID)?
    @Published var metadata = PhotoMetadata() { didSet { requestPreview(); scheduleSessionSave() } }
    @Published var style = FrameStyle() {
        didSet {
            if let data = try? JSONEncoder().encode(style) { UserDefaults.standard.set(data, forKey: "frameStyle.v1") }
            requestPreview()
            scheduleSessionSave()
        }
    }
    @Published var format: ExportFormat = .jpeg { didSet { scheduleSessionSave() } }
    @Published var exportSize: ExportSize = .ultra { didSet { scheduleSessionSave() } }
    @Published var isLoading = false
    @Published private(set) var isReceivingDrop = false
    @Published private(set) var dropImportCompleted = 0
    @Published private(set) var dropImportTotal = 0
    @Published var isRendering = false
    @Published var isExporting = false { didSet { if isExporting { closePaletteColorPanel() } } }
    @Published var isBatchExporting = false
    @Published var batchCompleted = 0
    @Published var batchTotal = 0
    @Published var batchReport: String?
    @Published var isDemo = false
    @Published var errorMessage: String?
    @Published var status = "准备好，为照片加上落款"
    @Published var logoName: String?
    @Published var lastExport: URL?
    private var batchFolder: URL?
    private var batchControl: BatchControl?
    private var logo: CGImage?
    private var logoURL: URL?
    var hasCustomLogo: Bool { logo != nil }
    private var previewJob: DispatchWorkItem?
    private var previewTicket = 0
    private var loadTicket = 0
    private let renderQueue = DispatchQueue(label: "local.yingkuang.render", qos: .userInitiated)
    private let dropImporter: PhotoDropImporter
    private let sessionStore: StudioSessionStore?
    private var sessionReady = false
    private var didStart = false
    private var sessionSaveJob: DispatchWorkItem?
    private var sessionSaveTicket = 0

    init(sessionStore: StudioSessionStore? = nil) {
        self.sessionStore = sessionStore
        dropImporter = PhotoDropImporter(cacheRoot: sessionStore?.importedPhotos)
        if let data = UserDefaults.standard.data(forKey: "colorWalkColors.v1"),
           let records = try? JSONDecoder().decode([String: SavedColorWalkColor].self, from: data) { savedColorWalkColors = records }
        if let data = UserDefaults.standard.data(forKey: "manualPalettes.v1"),
           let records = try? JSONDecoder().decode([String: SavedPhotoPalette].self, from: data) { savedPalettes = records }
        if let data = UserDefaults.standard.data(forKey: "frameStyle.v1"),
           let saved = try? JSONDecoder().decode(FrameStyle.self, from: data) { style = saved }
    }

    private func scheduleSessionSave() {
        guard sessionReady, sessionStore != nil else { return }
        sessionSaveJob?.cancel()
        sessionSaveTicket += 1
        let ticket = sessionSaveTicket
        let job = DispatchWorkItem { [weak self] in
            guard let self, self.sessionSaveTicket == ticket else { return }
            self.flushSession()
        }
        sessionSaveJob = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: job)
    }

    @discardableResult
    func flushSession() -> Bool {
        guard sessionReady, let sessionStore else { return true }
        sessionSaveJob?.cancel()
        sessionSaveTicket += 1
        var savedItems = items
        if !isLoading, let photo, let index = savedItems.firstIndex(where: { $0.id == selectedID && $0.url == photo.url }) {
            savedItems[index].metadata = metadata
        }
        let state = StudioSession(photos: savedItems, selectedID: selectedID, batchSelectedIDs: batchSelectedIDs,
            style: style, format: format, exportSize: exportSize, inspectorTab: inspectorTab,
            logoURL: logoURL, logoName: logoName, batchFolder: batchFolder)
        do { try sessionStore.save(state); return true }
        catch { sessionNotice = "本次修改尚未保存：\(error.localizedDescription)"; return false }
    }

    private func restoreSession(_ state: StudioSession, recovered: Bool) {
        style = state.style
        format = state.format; exportSize = state.exportSize
        inspectorTab = min(2, max(0, state.inspectorTab))
        items = state.photos
        for index in items.indices {
            if items[index].demo, let demoURL = Bundle.main.url(forResource: "Sample", withExtension: "jpg") { items[index].url = demoURL }
            else if let store = sessionStore {
                let oldURL = items[index].url
                do {
                    let retained = try store.retainImportedPhoto(oldURL)
                    if retained != oldURL {
                        items[index].url = retained
                        items[index].sourceIdentity = PhotoFileIdentity(url: retained)
                        migrateManualColors(items[index])
                    }
                } catch { sessionNotice = "部分照片副本尚未转存：\(error.localizedDescription)" }
            }
        }
        // A changed source must not inherit another image's edits. Missing sources
        // remain in the list so reconnecting a drive can recover them later.
        for index in items.indices { refreshSourceIdentity(at: index) }
        let validIDs = Set(items.map(\.id))
        batchSelectedIDs = state.batchSelectedIDs.intersection(validIDs)
        logoURL = state.logoURL; logoName = state.logoName
        if let url = logoURL {
            do { logo = try PhotoDocument(url: url).preview }
            catch { sessionNotice = "照片列表已恢复，自定义 Logo 暂时无法读取。" }
        }
        batchFolder = state.batchFolder
        let missing = items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.count
        if missing > 0 { sessionNotice = "已恢复照片列表，\(missing) 张原片暂不可用。请连接原磁盘或将文件放回原位置，再点击照片重试。" }
        else if recovered { sessionNotice = "已从上一次有效备份恢复会话。" }
        let available = items.first { FileManager.default.fileExists(atPath: $0.url.path) }
        let preferred = items.first { $0.id == state.selectedID && FileManager.default.fileExists(atPath: $0.url.path) }
        sessionReady = true
        if let item = preferred ?? available { selectPhoto(item.id) }
        else {
            selectedID = items.first(where: { $0.id == state.selectedID })?.id
            status = items.isEmpty ? "准备好，为照片加上落款" : "照片列表已恢复，等待原片可用"
        }
    }

    private func refreshSourceIdentity(at index: Int) {
        guard !items[index].demo else { return }
        guard let current = PhotoFileIdentity(url: items[index].url) else { return }
        if let saved = items[index].sourceIdentity, saved != current {
            items[index].metadata = nil
            items[index].paletteOverride = nil
            items[index].colorWalkOverride = nil
            items[index].width = nil; items[index].height = nil
            items[index].exportedTo = nil; items[index].exportError = nil
        }
        items[index].sourceIdentity = current
    }

    private func migrateManualColors(_ item: PhotoQueueItem) {
        let key = SavedPhotoPalette.key(for: item.url)
        if let swatches = item.paletteOverride { savedPalettes[key] = SavedPhotoPalette(url: item.url, swatches: swatches) }
        if let color = item.colorWalkOverride { savedColorWalkColors[key] = SavedColorWalkColor(url: item.url, color: color) }
        if let data = try? JSONEncoder().encode(savedPalettes) { UserDefaults.standard.set(data, forKey: "manualPalettes.v1") }
        if let data = try? JSONEncoder().encode(savedColorWalkColors) { UserDefaults.standard.set(data, forKey: "colorWalkColors.v1") }
    }

    var dimensions: String {
        guard let photo else { return "—" }
        let width = exportSize.width(for: photo, style: style)
        let layout = FrameLayout(imageWidth: photo.width, imageHeight: photo.height, outputWidth: width, style: style)
        return "\(layout.width) × \(layout.height)"
    }
    var isPortrait: Bool {
        guard let photo else { return false }
        return photo.height > photo.width
    }
    var currentMargin: Double {
        get { isPortrait ? style.portraitMargin : style.margin }
        set {
            if isPortrait { style.portraitMargin = newValue }
            else { style.margin = newValue }
        }
    }

    var batchSelectedCount: Int { batchSelectedIDs.count }

    func isBatchSelected(_ id: UUID) -> Bool { batchSelectedIDs.contains(id) }

    func setBatchSelection(_ id: UUID, selected: Bool) {
        guard !isExporting, items.contains(where: { $0.id == id }) else { return }
        if selected { batchSelectedIDs.insert(id) }
        else { batchSelectedIDs.remove(id) }
    }

    func selectAllForBatch() {
        guard !isExporting else { return }
        batchSelectedIDs = Set(items.map { $0.id })
    }

    func clearBatchSelection() {
        guard !isExporting else { return }
        batchSelectedIDs.removeAll()
    }

    func invertBatchSelection() {
        guard !isExporting else { return }
        batchSelectedIDs = Set(items.map { $0.id }).subtracting(batchSelectedIDs)
    }

    func batchJobsForSelection() -> [BatchJob] {
        rememberCurrentEdits()
        for index in items.indices where batchSelectedIDs.contains(items[index].id) { refreshSourceIdentity(at: index) }
        // Keep list order and never fall back to all photos when nothing is checked.
        return items.filter { batchSelectedIDs.contains($0.id) }
            .map { BatchJob(url: $0.url, metadataOverride: $0.metadata, paletteOverride: $0.paletteOverride?.map(\.color), colorWalkOverride: $0.colorWalkOverride) }
    }

    func setColorWalkHex(_ text: String, photoID: UUID) {
        guard selectedID == photoID, photo != nil, !isLoading, !isExporting else { return }
        colorWalkHexDraft = text
        if let color = PaletteColor(hex: text) { saveColorWalkColor(color) }
    }

    func commitColorWalkHex(photoID: UUID) {
        guard selectedID == photoID else { return }
        if PaletteColor(hex: colorWalkHex) == nil { status = "请输入六位 HEX 色号，例如 #AABBCC" }
        colorWalkHexDraft = nil
    }

    func setColorWalkColor(_ color: NSColor, photoID: UUID) {
        guard selectedID == photoID, photo != nil, !isLoading, !isExporting,
              let rgb = color.usingColorSpace(.sRGB) else { return }
        let value = PaletteColor(red: UInt8((min(1, max(0, rgb.redComponent)) * 255).rounded()),
            green: UInt8((min(1, max(0, rgb.greenComponent)) * 255).rounded()),
            blue: UInt8((min(1, max(0, rgb.blueComponent)) * 255).rounded()))
        colorWalkHexDraft = nil
        saveColorWalkColor(value)
    }

    func chooseColorWalkColor(photoID: UUID) {
        guard selectedID == photoID, !isLoading, !isExporting, let color = colorWalkColor else { return }
        closePaletteColorPanel()
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = color.color
        let handler = PaletteColorPanelHandler { [weak self] color in self?.setColorWalkColor(color, photoID: photoID) }
        palettePanelHandler = handler
        editingColorWalkPhotoID = photoID
        panel.setTarget(handler)
        panel.setAction(#selector(PaletteColorPanelHandler.colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restoreAutomaticColorWalkColor() {
        guard photo != nil, !isLoading, !isExporting else { return }
        closePaletteColorPanel()
        colorWalkHexDraft = nil
        saveColorWalkColor(nil)
    }

    private func saveColorWalkColor(_ color: PaletteColor?) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        items[index].colorWalkOverride = color
        let key = SavedPhotoPalette.key(for: items[index].url)
        if let color, let record = SavedColorWalkColor(url: items[index].url, color: color) { savedColorWalkColors[key] = record }
        else { savedColorWalkColors.removeValue(forKey: key) }
        if let data = try? JSONEncoder().encode(savedColorWalkColors) { UserDefaults.standard.set(data, forKey: "colorWalkColors.v1") }
        colorWalkColor = color ?? automaticColorWalkColor
        requestPreview()
    }

    func resetColorWalkStyle() {
        let defaults = FrameStyle()
        var updated = style
        updated.colorWalkHeader = defaults.colorWalkHeader
        updated.colorWalkTextScale = defaults.colorWalkTextScale
        updated.colorWalkTextPosition = defaults.colorWalkTextPosition
        updated.colorWalkInk = defaults.colorWalkInk
        updated.colorWalkShowStamp = defaults.colorWalkShowStamp
        style = updated
    }

    func paletteHex(for id: UUID) -> String {
        paletteHexDrafts[id] ?? paletteSwatches.first(where: { $0.id == id })?.color.hex ?? ""
    }

    func setPaletteHex(_ text: String, photoID: UUID, swatchID: UUID) {
        guard selectedID == photoID, !isLoading, !isExporting,
              let entry = paletteSwatches.first(where: { $0.id == swatchID }) else { return }
        paletteHexDrafts[swatchID] = text
        if let color = PaletteColor(hex: text, fraction: entry.color.fraction) {
            updatePaletteColor(color, photoID: photoID, swatchID: swatchID)
        }
    }

    func commitPaletteHex(photoID: UUID, swatchID: UUID) {
        guard selectedID == photoID, paletteSwatches.contains(where: { $0.id == swatchID }) else { return }
        let text = paletteHex(for: swatchID)
        if PaletteColor(hex: text) == nil { status = "请输入六位 HEX 色号，例如 #AABBCC" }
        paletteHexDrafts.removeValue(forKey: swatchID)
    }

    func setPaletteColor(_ color: NSColor, photoID: UUID, swatchID: UUID) {
        guard let rgb = color.usingColorSpace(.sRGB),
              let old = paletteSwatches.first(where: { $0.id == swatchID }) else { return }
        let value = PaletteColor(red: UInt8((min(1, max(0, rgb.redComponent)) * 255).rounded()),
            green: UInt8((min(1, max(0, rgb.greenComponent)) * 255).rounded()),
            blue: UInt8((min(1, max(0, rgb.blueComponent)) * 255).rounded()), fraction: old.color.fraction)
        updatePaletteColor(value, photoID: photoID, swatchID: swatchID)
    }

    func choosePaletteColor(photoID: UUID, swatchID: UUID) {
        guard selectedID == photoID, !isLoading, !isExporting,
              let swatch = paletteSwatches.first(where: { $0.id == swatchID }) else { return }
        closePaletteColorPanel()
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = swatch.color.color
        let handler = PaletteColorPanelHandler { [weak self] color in
            self?.setPaletteColor(color, photoID: photoID, swatchID: swatchID)
        }
        palettePanelHandler = handler
        editingPaletteSwatch = (photoID, swatchID)
        panel.setTarget(handler)
        panel.setAction(#selector(PaletteColorPanelHandler.colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePaletteColorPanel() {
        guard editingPaletteSwatch != nil || editingColorWalkPhotoID != nil else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.close()
        palettePanelHandler = nil
        editingPaletteSwatch = nil
        editingColorWalkPhotoID = nil
    }

    private func updatePaletteColor(_ color: PaletteColor, photoID: UUID, swatchID: UUID) {
        guard selectedID == photoID, !isLoading, !isExporting,
              let index = paletteSwatches.firstIndex(where: { $0.id == swatchID }) else { return }
        paletteHexDrafts[swatchID] = color.hex
        guard paletteSwatches[index].color != color else { return }
        var updated = paletteSwatches
        updated[index].color = color
        updated[index].modified = true
        savePaletteOverride(updated)
    }

    func removePaletteColor(photoID: UUID, swatchID: UUID) {
        guard selectedID == photoID, !isLoading, !isExporting,
              paletteSwatches.contains(where: { $0.id == swatchID }) else { return }
        if editingPaletteSwatch?.photoID == photoID && editingPaletteSwatch?.swatchID == swatchID { closePaletteColorPanel() }
        paletteHexDrafts.removeValue(forKey: swatchID)
        savePaletteOverride(paletteSwatches.filter { $0.id != swatchID })
    }

    func restoreAutomaticPalette() {
        guard photo != nil, !isLoading, !isExporting else { return }
        closePaletteColorPanel()
        savePaletteOverride(nil)
    }

    private func savePaletteOverride(_ swatches: [EditablePaletteSwatch]?) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        items[index].paletteOverride = swatches
        let key = SavedPhotoPalette.key(for: items[index].url)
        if let swatches, let saved = SavedPhotoPalette(url: items[index].url, swatches: swatches) { savedPalettes[key] = saved }
        else { savedPalettes.removeValue(forKey: key) }
        if let data = try? JSONEncoder().encode(savedPalettes) { UserDefaults.standard.set(data, forKey: "manualPalettes.v1") }
        if let swatches { paletteSwatches = swatches }
        else {
            paletteSwatches = automaticPalette.map { EditablePaletteSwatch(color: $0) }
            paletteHexDrafts.removeAll()
        }
        requestPreview()
    }

    private static var demoMetadata: PhotoMetadata {
        var metadata = PhotoMetadata()
        metadata.brand = "Nikon"
        metadata.camera = "NIKON Z 6_2"
        metadata.focalLength = "24.0"
        metadata.aperture = "22.0"
        metadata.shutter = "1/15"
        metadata.iso = "200"
        metadata.captureDateTime = "2026:01:01 12:00:00"
        return metadata
    }

    func start(arguments: [String] = CommandLine.arguments) {
        guard !didStart else { return }
        didStart = true
        var restored = false
        if let sessionStore {
            do {
                let result = try sessionStore.load()
                if let session = result.session {
                    restoreSession(session, recovered: result.recovered)
                    restored = true
                }
            } catch {
                sessionNotice = error.localizedDescription
                // Preserve unreadable files before allowing a new session to be saved.
                do { try sessionStore.preserveUnreadableSession() }
                catch { status = "会话保存目录不可用：\(error.localizedDescription)"; return }
                restored = true
            }
        }
        sessionReady = true
        if let i = arguments.firstIndex(of: "--open"), i + 1 < arguments.count {
            importPhotos(arguments[(i + 1)...].map { URL(fileURLWithPath: $0) })
        } else if !restored && items.isEmpty { loadDemo() }
    }
    func choosePhoto() {
        guard !isExporting, !isReceivingDrop else { return }
        let panel = NSOpenPanel()
        panel.title = "选择照片（可多选）"
        panel.prompt = "导入照片"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { importPhotos(panel.urls) }
    }
    func loadDemo() {
        guard let url = Bundle.main.url(forResource: "Sample", withExtension: "jpg") else { return }
        importPhotos([url], demo: true)
    }
    func load(_ url: URL, demo: Bool = false) { importPhotos([url], demo: demo) }

    func canReceiveDrop(_ pasteboard: NSPasteboard) -> Bool {
        !isExporting && !isReceivingDrop && dropImporter.canRead(pasteboard)
    }

    @discardableResult
    func receiveDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard canReceiveDrop(pasteboard) else { return false }
        isReceivingDrop = true
        let accepted = dropImporter.receive(pasteboard, progress: { [weak self] completed, total in
            self?.dropImportCompleted = completed
            self?.dropImportTotal = total
            self?.status = "正在接收拖入照片 · \(completed)/\(total)"
        }, completion: { [weak self] result in
            guard let self else { return }
            self.isReceivingDrop = false
            self.importPhotos(result.urls)
            if !result.failures.isEmpty {
                let prefix = result.urls.isEmpty ? "照片导入失败。" : "已导入 \(result.urls.count) 张，另有 \(result.failures.count) 项失败。"
                self.errorMessage = prefix + "\n" + result.failures.prefix(5).joined(separator: "\n")
                if result.urls.isEmpty { self.status = "照片导入失败，请重试" }
            }
        })
        if !accepted {
            isReceivingDrop = false
            status = "没有可导入的照片"
        }
        return accepted
    }

    func importPhotos(_ urls: [URL], demo: Bool = false) {
        guard !isExporting, !isReceivingDrop, !urls.isEmpty else { return }
        let localURLs = urls.filter(\.isFileURL)
        if localURLs.count != urls.count { errorMessage = FrameError.localFilesOnly.localizedDescription }
        guard !localURLs.isEmpty else { return }
        rememberCurrentEdits()
        var firstID: UUID?
        // Remove the starter demo when the first real files arrive.
        if !demo && items.allSatisfy({ $0.demo }) {
            items.removeAll(); selectedID = nil; batchSelectedIDs.removeAll()
        }
        var imported = items
        var known = Dictionary(imported.map {
            ($0.url.standardizedFileURL.resolvingSymlinksInPath(), $0.id)
        }, uniquingKeysWith: { first, _ in first })
        for originalURL in localURLs {
            var url = originalURL
            do { url = try sessionStore?.retainImportedPhoto(originalURL) ?? originalURL }
            catch { sessionNotice = "照片副本尚未转存：\(error.localizedDescription)" }
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            if let existingID = known[normalized] {
                if firstID == nil { firstID = existingID }
                continue
            }
            var item = PhotoQueueItem(url: url, demo: demo)
            if let saved = savedPalettes[SavedPhotoPalette.key(for: originalURL)], saved.matches(originalURL) {
                item.paletteOverride = saved.swatches
            }
            if let saved = savedColorWalkColors[SavedPhotoPalette.key(for: originalURL)], saved.matches(originalURL) { item.colorWalkOverride = saved.color }
            item.sourceIdentity = PhotoFileIdentity(url: url)
            if url != originalURL { migrateManualColors(item) }
            imported.append(item)
            known[normalized] = item.id
            if firstID == nil { firstID = item.id }
        }
        items = imported
        if let firstID { selectPhoto(firstID) }
    }

    private func rememberCurrentEdits() {
        guard photo != nil, let selectedID, let i = items.firstIndex(where: { $0.id == selectedID }) else { return }
        items[i].metadata = metadata
    }

    func selectPhoto(_ id: UUID) {
        guard !isExporting, let index = items.firstIndex(where: { $0.id == id }) else { return }
        closePaletteColorPanel()
        rememberCurrentEdits()
        refreshSourceIdentity(at: index)
        let item = items[index]
        // Read back after saving current edits, also when selecting the same item again.
        let savedMetadata = items.first(where: { $0.id == id })?.metadata
        selectedID = id
        loadTicket += 1
        let ticket = loadTicket
        isLoading = true
        previewTicket += 1
        previewJob?.cancel()
        isRendering = false
        photo = nil
        preview = nil
        paletteSwatches = []; automaticPalette = []; paletteSettings = nil; paletteHexDrafts.removeAll()
        colorWalkColor = nil; automaticColorWalkColor = nil; colorWalkHexDraft = nil
        status = "正在读取照片…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let access = item.url.startAccessingSecurityScopedResource()
            let result = Result { try PhotoDocument(url: item.url) }
            if access { item.url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadTicket == ticket, self.selectedID == id else { return }
                self.isLoading = false
                switch result {
                case .success(let document):
                    self.photo = document
                    self.isDemo = item.demo
                    self.lastExport = item.exportedTo
                    self.metadata = savedMetadata ?? (item.demo ? Self.demoMetadata : document.metadata)
                    if let i = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[i].width = document.width
                        self.items[i].height = document.height
                        self.items[i].metadata = self.metadata
                        self.items[i].exportError = nil
                    }
                    self.status = item.demo ? "程序绘制示例 · 拍摄参数为演示值" : "已读取照片 · \(document.width) × \(document.height)"
                    self.requestPreview()
                case .failure(let error):
                    if let i = self.items.firstIndex(where: { $0.id == id }) { self.items[i].exportError = error.localizedDescription }
                    self.errorMessage = error.localizedDescription
                    self.status = "照片读取失败"
                }
            }
        }
    }

    func removePhoto(_ id: UUID) {
        removePhotos([id])
    }

    func removeBatchSelectedPhotos() {
        guard !isExporting, !batchSelectedIDs.isEmpty else { return }
        let count = batchSelectedCount
        removePhotos(batchSelectedIDs)
        status = "已从 App 列表移除 \(count) 张 · 原片和导出文件均保留"
    }

    private func removePhotos(_ ids: Set<UUID>) {
        guard !isExporting, items.contains(where: { ids.contains($0.id) }) else { return }
        rememberCurrentEdits()
        let currentIndex = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        let nextIndex = items.prefix(currentIndex).filter { !ids.contains($0.id) }.count
        let removesPreview = selectedID.map { ids.contains($0) } ?? false
        // This is an in-memory list operation. It never deletes or moves any file.
        items.removeAll { ids.contains($0.id) }
        batchSelectedIDs.subtract(ids)
        if removesPreview {
            closePaletteColorPanel()
            selectedID = nil
            loadTicket += 1
            previewTicket += 1
            previewJob?.cancel()
            photo = nil; preview = nil; lastExport = nil
            paletteSwatches = []; automaticPalette = []; paletteSettings = nil; paletteHexDrafts.removeAll()
            colorWalkColor = nil; automaticColorWalkColor = nil; colorWalkHexDraft = nil
            isLoading = false; isRendering = false
            if !items.isEmpty { selectPhoto(items[min(nextIndex, items.count - 1)].id) }
            else {
                isDemo = false
                metadata = PhotoMetadata()
                status = "准备好，为照片加上落款"
            }
        }
    }
    func selectTemplate(_ template: TemplateID) {
        guard !isExporting else { return }
        if style.template != template { closePaletteColorPanel() }
        style.template = template
        inspectorTab = 1
    }
    func resetStyle() {
        let template = style.template
        style = FrameStyle()
        style.template = template
    }
    func resetPaletteStyle() {
        let defaults = FrameStyle()
        var updated = style
        updated.paletteCount = defaults.paletteCount
        updated.paletteMargin = defaults.paletteMargin
        updated.paletteFooter = defaults.paletteFooter
        updated.paletteSwatchSize = defaults.paletteSwatchSize
        updated.paletteShowHex = defaults.paletteShowHex
        updated.paletteShowSignature = defaults.paletteShowSignature
        updated.paletteDiamond = defaults.paletteDiamond
        updated.paletteOrder = defaults.paletteOrder
        style = updated
    }
    func resetPostageStyle() {
        let defaults = FrameStyle()
        var updated = style
        updated.postageMargin = defaults.postageMargin
        updated.postageBorder = defaults.postageBorder
        updated.postagePerforation = defaults.postagePerforation
        updated.postageFooter = defaults.postageFooter
        updated.postageBlur = defaults.postageBlur
        updated.postageBrightness = defaults.postageBrightness
        updated.postageShadow = defaults.postageShadow
        updated.postageTextScale = defaults.postageTextScale
        style = updated
    }
    func resetClassicStyle() {
        let defaults = FrameStyle()
        var updated = style
        updated.classicFooter = defaults.classicFooter
        updated.classicMargin = defaults.classicMargin
        updated.classicBrandScale = defaults.classicBrandScale
        updated.classicInfoScale = defaults.classicInfoScale
        updated.classicBrandColor = defaults.classicBrandColor
        style = updated
    }
    func restoreMetadata() {
        guard let photo else { return }
        metadata = isDemo ? Self.demoMetadata : photo.metadata
        rememberCurrentEdits()
    }
    func chooseLogo(useForClassic: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = "选择品牌 Logo（推荐透明 PNG）"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try setLogo(url)
                if useForClassic { style.classicUseCustomLogo = true }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func setLogo(_ url: URL) throws {
        let document = try PhotoDocument(url: url)
        let savedURL = try sessionStore?.saveLogo(document.preview)
        logo = document.preview
        logoName = url.lastPathComponent
        logoURL = savedURL
        requestPreview()
        scheduleSessionSave()
    }
    func removeLogo() {
        logo = nil; logoURL = nil; logoName = nil
        style.classicUseCustomLogo = false
        requestPreview(); scheduleSessionSave()
    }

    func requestPreview() {
        previewJob?.cancel()
        previewTicket += 1
        let ticket = previewTicket
        guard let photo else { return }
        let metadata = metadata, style = style, logo = logo
        let cachedPalette = paletteSettings?.count == style.paletteCount && paletteSettings?.order == style.paletteOrder
            ? automaticPalette : nil
        let manualPalette = items.first(where: { $0.id == selectedID })?.paletteOverride
        let manualWalk = items.first(where: { $0.id == selectedID })?.colorWalkOverride
        let cachedWalk = automaticColorWalkColor
        isRendering = true
        let job = DispatchWorkItem { [weak self] in
            let result = autoreleasepool { Result {
                let automatic = cachedPalette ?? photo.palette.colors(count: style.paletteCount, order: style.paletteOrder)
                let colors = manualPalette?.map(\.color) ?? automatic
                let walk = cachedWalk ?? (style.template == .colorWalk ? photo.palette.colorWalkColor() : nil)
                let image = try FrameRenderer().render(photo: photo, metadata: metadata, style: style,
                    width: 1500, preview: true, logo: logo, palette: colors, colorWalkColor: manualWalk ?? walk)
                return (image: image, automatic: automatic, walk: walk)
            } }
            DispatchQueue.main.async {
                guard let self, ticket == self.previewTicket else { return }
                self.isRendering = false
                switch result {
                case .success(let output):
                    let image = output.image
                    self.preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    self.automaticPalette = output.automatic
                    self.automaticColorWalkColor = output.walk
                    self.colorWalkColor = manualWalk ?? output.walk
                    if let manualPalette { self.paletteSwatches = manualPalette }
                    else if self.paletteColors != output.automatic {
                        self.paletteSwatches = output.automatic.map { EditablePaletteSwatch(color: $0) }
                        self.paletteHexDrafts.removeAll()
                    }
                    self.paletteSettings = (style.paletteCount, style.paletteOrder)
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
        previewJob = job
        renderQueue.asyncAfter(deadline: .now() + 0.16, execute: job)
    }

    var protectedExportSources: [URL] { items.map(\.url) + (photo.map { [$0.url] } ?? []) }

    func export() {
        guard let photo, !isExporting, !isLoading, !isReceivingDrop else { return }
        rememberCurrentEdits()
        let exportMetadata = metadata, exportStyle = style, exportFormat = format, exportLogo = logo
        let exportPalette = items.first(where: { $0.id == selectedID })?.paletteOverride?.map(\.color)
        let exportWalk = items.first(where: { $0.id == selectedID })?.colorWalkOverride
        let width = exportSize.width(for: photo, style: exportStyle)
        let panel = NSSavePanel()
        panel.title = "导出水印照片"
        panel.prompt = "导出照片"
        panel.allowedContentTypes = [exportFormat.contentType]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(isDemo ? "山间暮色" : photo.name)-映框.\(exportFormat.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let protectedSources = protectedExportSources
        do { try ImageWriter.validateDestination(url, protecting: protectedSources) }
        catch { errorMessage = error.localizedDescription; return }
        isExporting = true
        status = "正在导出 \(dimensions)…"
        let selected = selectedID
        renderQueue.async { [weak self] in
            let result = autoreleasepool { Result {
                let image = try FrameRenderer().render(photo: photo, metadata: exportMetadata, style: exportStyle,
                    width: width, logo: exportLogo, palette: exportPalette, colorWalkColor: exportWalk)
                try ImageWriter.save(image, to: url, format: exportFormat, protecting: protectedSources)
            } }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isExporting = false
                switch result {
                case .success:
                    self.lastExport = url
                    if let i = self.items.firstIndex(where: { $0.id == selected }) { self.items[i].exportedTo = url; self.items[i].exportError = nil }
                    self.status = "已导出 · \(url.lastPathComponent)"
                case .failure(let error): self.errorMessage = error.localizedDescription; self.status = "导出失败"
                }
            }
        }
    }

    func exportBatch() {
        guard !items.isEmpty, !isExporting, !isLoading, !isReceivingDrop else { return }
        let jobs = batchJobsForSelection()
        guard !jobs.isEmpty else {
            inspectorTab = 2
            status = "请在右侧勾选要导出的照片"
            return
        }
        let exportStyle = style, exportFormat = format, size = exportSize, exportLogo = logo
        let panel = NSOpenPanel()
        panel.title = "导出已选 \(jobs.count) 张照片"
        panel.prompt = "导出到此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let control = BatchControl()
        batchControl = control
        batchFolder = folder
        batchCompleted = 0; batchTotal = jobs.count
        isExporting = true; isBatchExporting = true
        status = "准备批量导出 \(jobs.count) 张照片…"
        let access = folder.startAccessingSecurityScopedResource()
        renderQueue.async { [weak self] in
            let report = BatchExporter.run(jobs: jobs, folder: folder, style: exportStyle, size: size,
                format: exportFormat, logo: exportLogo, control: control,
                willStart: { index, url in
                    DispatchQueue.main.async { [weak self] in self?.status = "批量导出 \(index)/\(jobs.count) · \(url.lastPathComponent)" }
                }, didFinish: { result, completed in
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.batchCompleted = completed
                        if let i = self.items.firstIndex(where: { $0.url == result.sourceURL }) {
                            self.items[i].exportError = result.error
                            if let url = result.outputURL { self.items[i].exportedTo = url }
                        }
                        if let current = self.photo, current.url == result.sourceURL { self.lastExport = result.outputURL }
                    }
                })
            if access { folder.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isExporting = false; self.isBatchExporting = false; self.batchControl = nil
                let summary = "成功 \(report.succeeded) 张，失败 \(report.failed) 张" + (report.remaining > 0 ? "，未处理 \(report.remaining) 张" : "")
                self.status = "批量导出结束 · " + summary
                let failures = report.results.filter { $0.error != nil }
                let detail = failures.prefix(8).map { "\($0.sourceURL.lastPathComponent)：\($0.error ?? "")" }.joined(separator: "\n")
                self.batchReport = summary + "\n\n保存位置：\(folder.path)" + (detail.isEmpty ? "" : "\n\n" + detail)
                    + (failures.count > 8 ? "\n其余失败项可在左侧照片列表查看。" : "")
            }
        }
    }
    func cancelBatch() {
        batchControl?.cancel()
        status = "正在停止 · 当前照片处理结束后停止"
    }
    func revealExport() {
        if let lastExport { NSWorkspace.shared.activateFileViewerSelecting([lastExport]) }
    }
    func revealBatchFolder() {
        if let batchFolder { NSWorkspace.shared.open(batchFolder) }
    }
}
