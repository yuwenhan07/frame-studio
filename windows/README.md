# 映框 · Windows 预览版

Windows 桌面端的独立实现，使用 Electron 与 Canvas 2D，本机运行，无需账号或网络服务。原来的 SwiftUI/AppKit macOS 代码保持独立。Canvas 模板来自同一作者的映框小程序项目，按当前 macOS 模板风格迁移；字体、模糊和像素细节不保证与 macOS 完全相同。

## 下载与使用

[下载 v0.12.0-windows.1](https://github.com/yuwenhan07/frame-studio/releases/tag/v0.12.0-windows.1)。

- `FrameStudio-0.12.0-windows.1-Windows-x64-Setup.exe`：安装版，默认当前用户安装，可选择目录。
- `FrameStudio-0.12.0-windows.1-Windows-x64-Portable.exe`：免安装启动版；编辑记录仍写入当前用户的 AppData，不是随 U 盘移动的完整便携工作区。

目标平台为 Windows 10/11 x64。本次发布未签署 Windows 代码签名证书，系统可能显示未知发布者或 SmartScreen 提示。只从上面的仓库发布页下载；若组织策略阻止运行，请联系设备管理员。未提供 Windows ARM64 原生包或 Windows 7/8 支持。

点击「导入照片」或按 `Ctrl+O`，也可把文件拖入窗口。支持 JPEG、PNG、WebP、BMP；HEIC、TIFF、RAW 请先转成支持的格式。选择模板，在右侧修改排版与文字。EXIF 自动读取品牌、型号、焦距、光圈、曝光、ISO 与拍摄日期；缺失值留空，可在「这张照片的拍摄信息」修正。日期不从当前时间或文件修改日期推测。

「导出当前」快捷键为 `Ctrl+Shift+E`。勾选照片后可导出已选，取消会在当前照片结束后停止。默认不裁切主照片，Walk Ticket 可主动选择裁切。JPEG/PNG 最长边上限可选 1920、2560、3840、4096，不放大原照片；不能输出完整原始分辨率超过 4096 的大图。条码必须满足最低像素宽度，过小照片会明确报告导出失败。

会话最多 50 张照片、源文件合计 160 MiB；单文件最多 40 MiB、4000 万像素、最长边 16000。达到限制时保留成功项并说明跳过原因；建议完成一批后从列表移除，再处理下一批。

## 模板与编辑

提供柔焦画框、邮票画框、经典画框、Color Walk、圆形色卡、方形色卡、Tickets、Walk Ticket、胶片相框、Gallery、Editorial、Instant、Cinema、Receipt、手撕相纸，共 15 个模板。模板设置会随会话保存；个人落款与字体共用，圆形和方形色卡共用取色与底栏设置。数字滑块旁的值可双击重置。

Color Walk 可选纯色或横向主色条纹；支持逐照片修改颜色、HEX 和清空色卡。切换照片和重启可恢复手动颜色。重新导入或恢复会话时，若检测到原路径文件的大小或修改时间变化，会清除该图旧的手动颜色和拍摄信息修正，重新识别。

支持中文、英文字体分别选择系统黑体、衬线体或等宽体。不打包字体；Windows 使用本机字体回退。暂不提供 macOS 版的全部已安装字体选择、自定义 Logo、macOS「照片」文件承诺导入和 macOS 会话文件迁移。预览与导出共用当前 Windows 渲染逻辑。

## 文件与隐私

单张与批量导出均创建新文件，遇到已有文件追加编号。已导入原片及其符号链接、硬链接别名不能被导出覆盖。移除照片只移除列表记录，不删除磁盘照片或既有导出。

会话位于 `%APPDATA%\FrameStudioWindows\`，保存源照片路径、逐照片编辑、当前模板和输出设置。会话使用临时文件替换，保留上一份有效备份；损坏主文件在后续保存前保留到 `Recovery/`。失联照片保留记录，恢复原路径后重启可重新读取。会话不能跨 macOS/Windows 自动迁移。详见 [隐私说明](PRIVACY.md)。

## 开发与验证

需要 Node.js 22、npm。依赖版本由 `package-lock.json` 固定。

```sh
cd windows
npm ci
npm run verify
npm start
```

在 Windows 上构建：

```sh
npm run pack:win
```

产物在 `windows/release/`。macOS 可运行同一 Electron 应用进行功能检查；正式 Windows 包由 GitHub Actions 的 Windows runner 原生构建，避免在 Mac 上把交叉编译成功当作 Windows 运行验证。

[Windows CI](https://github.com/yuwenhan07/frame-studio/actions/workflows/windows.yml) 包含类型检查、独立预期像素/布局/颜色测试、文件与会话测试，以及实际 Electron UI 流程；打包后对 `win-unpacked/FrameStudio.exe` 重跑 UI 检查。发布说明记录实际完成的检查和限制。构建时生成的测试照片都是程序绘制，不包含用户私有照片。

Windows CI 使用 Windows Server 托管环境，不代表已在每种 Windows 10/11 设备、显卡、DPI、字体组合或安全软件下人工验收。首版以预发布形式交付，并保留原 macOS 正式版下载入口。

## 关键源码

- `electron/main.cjs`、`preload.cjs`：隔离的窗口、受限文件桥接与本地协议。
- `electron/files.cjs`、`session.cjs`：图片验证、EXIF、原片保护、独占创建输出、会话备份。
- `src/core/`、`src/imaging.ts`：15 个模板、主色、方向修正后解码、同源模糊和输出尺寸。
- `src/app.ts`：照片列表、独立编辑、模板设置、导出与恢复。
- `tests/`：功能、像素、文件保护和实际桌面流程检查。

依赖使用 Electron、exifr；构建与测试依赖不进入运行时界面。品牌标志与条码来源记录见 [`licenses/`](licenses/)。
