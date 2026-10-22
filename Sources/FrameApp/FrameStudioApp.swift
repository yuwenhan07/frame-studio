import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = StudioModel(sessionStore: .standard())
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()
        showWindow()
        model.start()
    }

    private func showWindow() {
        if window == nil {
            let root = StudioView(model: model)
                .frame(minWidth: 1060, minHeight: 730)
                .preferredColorScheme(.light)
                .tint(Color(red: 0.77, green: 0.38, blue: 0.23))
                .ignoresSafeArea()
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 880),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            panel.title = "映框 · 摄影水印"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 1060, height: 730)
            panel.contentView = PhotoDropHostingView(rootView: root, model: model)
            panel.center()
            panel.setFrameAutosaveName("FrameStudio.main")
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        showWindow()
        model.start()
        model.importPhotos(urls)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !model.flushSession() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "未能保存本次修改"
        alert.informativeText = (model.sessionNotice ?? "请检查本机存储是否可写。") + "\n返回映框后可重新尝试，或保留上次保存的会话并退出。"
        alert.addButton(withTitle: "返回映框")
        alert.addButton(withTitle: "仍然退出")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installMenu() {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let result = NSMenu(title: title)
            item.submenu = result
            bar.addItem(item)
            return result
        }
        func add(_ title: String, _ action: Selector, _ key: String, to menu: NSMenu, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            menu.addItem(item)
        }
        let app = menu("映框")
        add("关于映框", #selector(about), "", to: app, target: self)
        app.addItem(.separator())
        add("隐藏映框", #selector(NSApplication.hide(_:)), "h", to: app)
        app.addItem(.separator())
        add("退出映框", #selector(NSApplication.terminate(_:)), "q", to: app)
        let file = menu("文件")
        add("导入照片（可多选）…", #selector(openPhoto), "o", to: file, target: self)
        add("打开示例照片", #selector(openDemo), "", to: file, target: self)
        file.addItem(.separator())
        add("导出水印照片…", #selector(exportPhoto), "E", to: file, target: self)
        file.items.last?.keyEquivalentModifierMask = [.command, .shift]
        add("批量导出已选照片…", #selector(exportBatch), "e", to: file, target: self)
        file.items.last?.keyEquivalentModifierMask = [.command, .option]
        file.addItem(.separator())
        add("关闭窗口", #selector(NSWindow.performClose(_:)), "w", to: file)
        let edit = menu("编辑")
        add("撤销", Selector(("undo:")), "z", to: edit)
        add("重做", Selector(("redo:")), "Z", to: edit)
        edit.addItem(.separator())
        add("剪切", #selector(NSText.cut(_:)), "x", to: edit)
        add("复制", #selector(NSText.copy(_:)), "c", to: edit)
        add("粘贴", #selector(NSText.paste(_:)), "v", to: edit)
        add("全选", #selector(NSText.selectAll(_:)), "a", to: edit)
        let windows = menu("窗口")
        add("最小化", #selector(NSWindow.performMiniaturize(_:)), "m", to: windows)
        add("缩放", #selector(NSWindow.performZoom(_:)), "", to: windows)
        NSApp.windowsMenu = windows
        let help = menu("帮助")
        add("使用说明", #selector(about), "", to: help, target: self)
        NSApp.helpMenu = help
        NSApp.mainMenu = bar
    }

    @objc private func openPhoto() { model.choosePhoto() }
    @objc private func openDemo() { model.loadDemo() }
    @objc private func exportPhoto() { model.export() }
    @objc private func exportBatch() { model.exportBatch() }
    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "映框 · 摄影水印"
        alert.informativeText = "1. 拖入多张照片，或按 ⌘O 多选导入。\n2. 左侧选择柔焦画框、圆形色卡、方形色卡、Color Walk、邮票画框、经典画框、Tickets 票券、漫步票根、胶片相框、画廊留白、旅行杂志、Instant 即影即有、电影字幕、记忆小票或撕边相纸。\n3. 色卡自动提取每张照片的主色，可调整数量、排序、白边、底栏和色块大小；方形可切换为菱形。\n4. Color Walk 可选纯色色面或横向主色条纹，条纹支持独立数量、排序和逐个改色、删除；默认盖章 Stay alive · keep trying，可调整文案、日期、时间、色面高度、字号和上下位置。\n5. 邮票画框可切换纯画框与底部落款，调整白边、齿孔、留白与阴影；地点可手填，日期可自动读取、自定义或隐藏。\n6. 经典画框使用白色底栏，可选择品牌居中、左文右标或横向信息，自动逐张识别品牌；支持手动选择、品牌色和自定义 Logo。\n7. Tickets 票券包含上下齿边、撕线、标题与日期，右下角可选择旅行邮戳、Code 128 条形码或隐藏。\n8. 漫步票根以横向圆角票面呈现照片、城市标题、主色色卡、撕线和同色装饰条码；条码只作装饰，可隐藏，可调整配色和版式。\n9. 新增的胶片、画廊、杂志和 Instant 均保留完整照片，提供独立文案、日期、字体与版式；杂志强调色可逐张自动提取，Instant 可调整相纸阴影。\n电影字幕提供双行字幕与上下位置调整；记忆小票提供票纸、编号和日常注记；撕边相纸可调整自然边缘与轻阴影。\n10.「水印信息」可设置个人落款、字号，以及独立的中英文字体（默认微软雅黑）。双击滑块旁的数字可恢复该项默认值。\n11. 右侧「批量选择」可勾选、全选、取消全选或反选。「导出已选」只导出勾选项；「移除已选」只清理 App 列表。\n\n⇧⌘E 导出当前照片，⌥⌘E 导出已选照片。批量共用模板和落款，各张照片分别取色或读取拍摄参数。重名文件自动编号，原片和已有导出文件均保留。\n\n照片、编辑和导出设置会在本机自动保存，退出后重新打开可继续上次会话。\n\n所有处理均在本机完成。柔焦画框可编辑相机参数与 Logo，竖版默认两侧各留 8%。无 EXIF 的参数留空。"
        alert.runModal()
    }
}

@main
struct FrameStudioMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
