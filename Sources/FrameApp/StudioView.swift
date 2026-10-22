import SwiftUI
import UniformTypeIdentifiers
import FrameCore

private let ink = Color(red: 0.18, green: 0.20, blue: 0.19)
private let accent = Color(red: 0.77, green: 0.38, blue: 0.23)
private let muted = Color(red: 0.53, green: 0.54, blue: 0.51)
private let paper = Color(red: 0.972, green: 0.969, blue: 0.953)

struct StudioView: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice = model.sessionNotice {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").foregroundStyle(accent)
                    Text(notice).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.sessionNotice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("关闭提示")
                }.padding(.horizontal, 22).padding(.vertical, 10).background(accent.opacity(0.08))
            }
            Divider().opacity(0.65)
            HStack(spacing: 0) {
                templateSidebar.frame(width: 180)
                Divider().opacity(0.55)
                previewArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.55)
                inspector.frame(width: 290)
            }
            Divider().opacity(0.65)
            statusBar
        }
        .background(paper)
        .foregroundStyle(ink)
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("批量导出结果", isPresented: Binding(get: { model.batchReport != nil }, set: { if !$0 { model.batchReport = nil } })) {
            Button("查看导出文件夹") { model.revealBatchFolder(); model.batchReport = nil }
            Button("完成", role: .cancel) { model.batchReport = nil }
        } message: { Text(model.batchReport ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Room for the native window controls in the hidden title bar.
            Color.clear.frame(width: 62, height: 1)
            Image(systemName: "viewfinder").font(.system(size: 23, weight: .medium)).foregroundStyle(accent)
            Text("映框").font(.system(size: 21, weight: .semibold, design: .serif))
            Text("FRAME STUDIO").font(.system(size: 9, weight: .medium)).tracking(1.9).foregroundStyle(muted).padding(.leading, 2)
            Spacer()
            Text(model.items.count > 1 ? "已导入 \(model.items.count) 张照片" : "给影像，一个漂亮的落款").font(.system(size: 11)).foregroundStyle(muted)
            Spacer()
            Button { model.choosePhoto() } label: { Label("导入照片", systemImage: "plus").padding(.horizontal, 4) }
                .keyboardShortcut("o").controlSize(.large)
                .disabled(model.isExporting || model.isReceivingDrop)
            if !model.items.isEmpty {
                Button { model.inspectorTab = 2 } label: {
                    Label(model.batchSelectedCount > 0 ? "批量选择 · \(model.batchSelectedCount)" : "批量选择", systemImage: "checklist")
                        .padding(.horizontal, 4)
                }.controlSize(.large).disabled(model.isExporting)
            }
            Button { model.export() } label: {
                HStack(spacing: 7) {
                    if model.isExporting { ProgressView().controlSize(.small) }
                    else { Image(systemName: "square.and.arrow.up") }
                    Text(model.isExporting ? "正在导出" : (model.items.count > 1 ? "导出当前" : "导出照片"))
                }.padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.photo == nil || model.isExporting || model.isLoading || model.isReceivingDrop)
        }.padding(.horizontal, 20).frame(height: 74)
    }

    private var templateSidebar: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("模板库").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "%02d", TemplateID.allCases.count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
            }.padding(.top, 5)
            ScrollView {
            VStack(spacing: 8) {
                ForEach(TemplateID.allCases) { template in
                    Button { model.selectTemplate(template) } label: {
                        HStack(spacing: 8) {
                            templateThumbnail(template)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(template.title).font(.system(size: 11, weight: .semibold))
                                Text(template.subtitle).font(.system(size: 8)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(8)
                            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                                model.style.template == template ? accent.opacity(0.7) : ink.opacity(0.08),
                                lineWidth: model.style.template == template ? 1.3 : 0.7))
                    }.buttonStyle(.plain).accessibilityIdentifier("template-" + template.rawValue)
                        .help(template.title).disabled(model.isExporting)
                }
            }
            }.frame(height: min(CGFloat(TemplateID.allCases.count * 74), max(160, geometry.size.height * 0.58))).scrollIndicators(.hidden)
            photoQueue
            Spacer(minLength: 0)
            Button { model.loadDemo() } label: { Label("打开示例照片", systemImage: "sparkles") }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent).disabled(model.isExporting)
            Divider()
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 12))
                Text("只在你的 Mac 上\n原图始终保留").font(.system(size: 9)).lineSpacing(4)
            }.foregroundStyle(muted)
        }.padding(16).frame(maxHeight: .infinity).background(Color(red: 0.95, green: 0.948, blue: 0.93))
        }
    }

    private func templateThumbnail(_ template: TemplateID) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if template.isPrint {
                    PrintTemplateThumbnail(template: template, style: model.style, photo: model.photo?.preview)
                } else if template == .walkTicket {
                    Color(red: 0.972, green: 0.956, blue: 0.921)
                    RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: model.style.walkTicket.paperColor(photo: model.photo)))
                        .frame(width: 44, height: 25).shadow(color: .black.opacity(0.2), radius: 2, y: 2)
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 12, height: 19).clipped().clipShape(RoundedRectangle(cornerRadius: 1)).offset(x: -13)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WALK").font(.system(size: 4, weight: .bold, design: .serif))
                        HStack(spacing: 1) { ForEach(0..<4) { i in
                            RoundedRectangle(cornerRadius: 0.4).fill([Color.white, muted, accent, ink][i]).frame(width: 3, height: 4)
                        } }
                    }.foregroundStyle(.white).offset(x: 3)
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 0.5, height: 21).offset(x: 14)
                } else if template == .tickets {
                    Color(red: 0.36, green: 0.46, blue: 0.39)
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 48, height: 50).clipped().blur(radius: 4)
                    }
                    TicketPaperShape().fill(.white).frame(width: 31, height: 42)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 27, height: 29).clipped().offset(y: -4)
                    }
                    Circle().stroke(muted.opacity(0.6), lineWidth: 0.5).frame(width: 7, height: 7).offset(x: 9, y: 15)
                } else if template == .softFrame || template == .postageFrame {
                    Color(red: 0.71, green: 0.52, blue: 0.43)
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 48, height: 50).clipped().blur(radius: 4)
                        if template == .postageFrame {
                            PostagePaperShape().fill(.white).frame(width: 41, height: 33)
                                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                            Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                                .frame(width: 35, height: 27).clipped()
                        } else {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFit()
                            .frame(width: 42, height: 34).clipShape(RoundedRectangle(cornerRadius: 2))
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        }
                    }
                } else if template == .classicFrame {
                    Color.white
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 48, height: 38).clipped().offset(y: -6)
                    }
                    ClassicBrandPreview(brand: model.style.classicBrand.resolved(metadata: model.metadata),
                        colored: model.style.classicBrandColor, fallback: model.metadata.brand)
                        .frame(width: 29, height: 7).offset(y: 19)
                } else if template == .colorWalk {
                    if model.style.colorWalkBackground == .horizontalStripes {
                        if model.paletteColors.isEmpty { Color.white }
                        else { VStack(spacing: 0) {
                            ForEach(Array(model.paletteColors.prefix(8).enumerated()), id: \.offset) { _, color in
                                Rectangle().fill(Color(nsColor: color.color))
                            }
                        } }
                    } else {
                        (model.colorWalkColor.map { Color(nsColor: $0.color) } ?? Color(red: 0.65, green: 0.42, blue: 0.43))
                    }
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 48, height: 28).clipped().offset(y: 11)
                    }
                    VStack(spacing: 2) {
                        Capsule().fill(.white.opacity(0.9)).frame(width: 25, height: 2)
                        Capsule().fill(.white.opacity(0.7)).frame(width: 12, height: 1)
                    }.offset(y: -15)
                } else {
                    Color.white
                    if let photo = model.photo {
                        Image(decorative: photo.preview, scale: 1).resizable().scaledToFill()
                            .frame(width: 44, height: 35).clipped().offset(y: -5)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<3) { index in
                            let color = model.paletteColors.indices.contains(index) ? Color(nsColor: model.paletteColors[index].color) : [accent, muted, ink][index]
                            if template == .colorCircles { Circle().fill(color).frame(width: 7, height: 7) }
                            else { RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 6, height: 6).rotationEffect(.degrees(45)) }
                        }
                    }.offset(y: 18)
                }
            }
        }.frame(width: 48, height: 50).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var photoQueue: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("照片 · \(model.items.count)").font(.system(size: 11, weight: .medium))
                Spacer()
                Button { model.choosePhoto() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("添加更多照片，可多选")
            }.foregroundStyle(muted)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.items) { item in
                        Button { model.selectPhoto(item.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.exportError != nil ? "exclamationmark.circle.fill" : (item.exportedTo != nil ? "checkmark.circle.fill" : "photo"))
                                    .foregroundStyle(item.exportError != nil ? Color.red : (item.exportedTo != nil ? Color.green : muted))
                                Text(item.demo ? "示例照片" : item.url.lastPathComponent)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }.font(.system(size: 10)).padding(.horizontal, 7).frame(height: 30)
                                .background(item.id == model.selectedID ? accent.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).help(item.exportError ?? item.url.path)
                            .contextMenu { Button("从列表移除") { model.removePhoto(item.id) } }
                    }
                }
            }.frame(minHeight: 70, maxHeight: .infinity).scrollIndicators(.hidden)
            Text("点击切换 · 右键移除").font(.system(size: 9)).foregroundStyle(muted)
        }.disabled(model.isExporting)
    }

    private var previewArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("画布预览").font(.system(size: 11, weight: .medium))
                Spacer()
                if model.isRendering {
                    ProgressView().controlSize(.mini)
                    Text("更新中").font(.system(size: 10)).foregroundStyle(muted)
                } else {
                    Circle().fill(Color(red: 0.38, green: 0.53, blue: 0.40)).frame(width: 5, height: 5)
                    Text("实时预览").font(.system(size: 10)).foregroundStyle(muted)
                }
            }.padding(.horizontal, 26).frame(height: 48)
            ZStack {
                Color.clear
                if let preview = model.preview {
                    Image(nsImage: preview).resizable().scaledToFit()
                        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                        .padding(.horizontal, 30).padding(.vertical, 12)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(accent)
                        Text("把照片拖到这里").font(.system(size: 22, weight: .light))
                        Text("JPEG / PNG / HEIC / TIFF").font(.system(size: 11)).foregroundStyle(muted)
                        Button("选择照片…") { model.choosePhoto() }.buttonStyle(.borderedProminent)
                    }
                }
                if model.isLoading || model.isReceivingDrop {
                    RoundedRectangle(cornerRadius: 12).fill(.regularMaterial).frame(width: 220, height: 100)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(model.isReceivingDrop ? "正在接收照片 · \(model.dropImportCompleted)/\(model.dropImportTotal)" : "正在读取照片")
                            .font(.system(size: 11))
                    }
                }
                if model.dropTargeted {
                    RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.09))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5])))
                        .padding(14)
                    Label("松开以导入照片，可添加多张", systemImage: "arrow.down.doc")
                        .font(.system(size: 17, weight: .medium)).padding(22).background(.regularMaterial, in: Capsule())
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture(count: 2) { model.choosePhoto() }
            VStack(spacing: 5) {
                Text(model.isDemo ? "山间暮色 · 程序绘制示例" : (model.photo?.url.lastPathComponent ?? "等待导入照片"))
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(model.style.template == .colorWalk ? "照片色调 · 可选纯色或横向主色条纹，搭配文字盖章" : (model.style.template.isPalette ? "主色来自当前照片 · 可在画框样式中调整" : (model.isDemo ? "程序绘制示例 · 拍摄参数为演示值，可自由修改" : "拖入照片以添加 · 点击左侧列表切换")))
                    .font(.system(size: 10)).foregroundStyle(muted)
            }.padding(.top, 10).padding(.bottom, 21)
        }
        .background(Color(red: 0.914, green: 0.915, blue: 0.895))
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("编辑内容", selection: $model.inspectorTab) {
                Text("水印信息").tag(0)
                Text("画框样式").tag(1)
                Text("批量选择").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(18)
            if model.inspectorTab == 2 {
                batchSelectionEditor
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 21) {
                        if model.inspectorTab == 0 { metadataEditor }
                        else if model.style.template.isPrint { printEditor }
                        else if model.style.template == .colorWalk { colorWalkEditor }
                        else if model.style.template == .tickets { ticketEditor }
                        else if model.style.template == .walkTicket { walkTicketEditor }
                        else if model.style.template == .postageFrame { postageEditor }
                        else if model.style.template == .classicFrame { classicEditor }
                        else if model.style.template.isPalette { paletteEditor }
                        else { styleEditor }
                        Divider()
                        exportEditor
                    }.padding(.horizontal, 20).padding(.bottom, 22)
                }.scrollIndicators(.hidden)
            }
        }.background(paper).disabled(model.isExporting)
    }

    private var batchSelectionEditor: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("照片选择").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("已选 \(model.batchSelectedCount) / \(model.items.count)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
            }
            HStack(spacing: 14) {
                Button("全选") { model.selectAllForBatch() }
                Button("取消全选") { model.clearBatchSelection() }
                Button("反选") { model.invertBatchSelection() }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                .disabled(model.items.isEmpty)
            ScrollView {
                if model.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.stack").font(.system(size: 30, weight: .light))
                        Text("先导入照片").font(.system(size: 12))
                        Button("导入照片…") { model.choosePhoto() }.controlSize(.small)
                    }.foregroundStyle(muted).frame(maxWidth: .infinity).padding(.vertical, 32)
                } else {
                    LazyVStack(spacing: 7) {
                        ForEach(model.items) { item in
                            HStack(spacing: 8) {
                                Toggle(isOn: Binding(get: { model.isBatchSelected(item.id) },
                                                     set: { model.setBatchSelection(item.id, selected: $0) })) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.demo ? "示例照片" : item.url.lastPathComponent)
                                            .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                                        if item.id == model.selectedID {
                                            Text("当前预览").font(.system(size: 9)).foregroundStyle(muted)
                                        }
                                    }
                                }.toggleStyle(.checkbox).help(item.url.path)
                                    .accessibilityIdentifier("batch-select-" + item.id.uuidString)
                                Spacer(minLength: 0)
                                Button { model.selectPhoto(item.id) } label: { Image(systemName: "eye") }
                                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted)
                                    .help("预览 " + item.url.lastPathComponent)
                            }.padding(9)
                                .background(model.isBatchSelected(item.id) ? accent.opacity(0.09) : Color.white,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ink.opacity(0.08), lineWidth: 0.7))
                        }
                    }
                }
            }.frame(maxHeight: .infinity).scrollIndicators(.hidden)
            Divider()
            HStack(spacing: 10) {
                Text("导出设置").font(.system(size: 11, weight: .medium))
                Spacer()
            }
            HStack(spacing: 8) {
                Picker("图片格式", selection: $model.format) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
                Picker("画布宽度", selection: $model.exportSize) {
                    ForEach(ExportSize.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }.controlSize(.small)
            Text(batchTemplateNote)
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(muted)
            HStack(spacing: 8) {
                Button { model.exportBatch() } label: { Label("导出已选", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent).disabled(model.batchSelectedCount == 0 || model.isLoading)
                Button { model.removeBatchSelectedPhotos() } label: { Label("移除已选", systemImage: "minus.circle") }
                    .foregroundStyle(.red).disabled(model.batchSelectedCount == 0)
            }.controlSize(.regular)
            Text("仅从 App 列表移除，原片和已导出文件均保留。")
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(muted)
        }.padding(.horizontal, 20).padding(.bottom, 22)
    }

    @ViewBuilder private var metadataEditor: some View {
        if model.style.template.isPrint { printContentEditor }
        else if model.style.template == .walkTicket { walkTicketContentEditor }
        else if model.style.template == .tickets { ticketContentEditor }
        else if model.style.template == .colorWalk { colorWalkStampEditor }
        else if model.style.template == .classicFrame { classicMetadataEditor }
        else if model.style.template == .postageFrame {
            VStack(alignment: .leading, spacing: 16) {
                postageVariantPicker
                if model.style.postageVariant == .caption { postageTextEditor }
                else { Text("切换为「底部落款」，可填写地点和日期。").font(.system(size: 10)).foregroundStyle(muted) }
            }
        }
        else {
        VStack(alignment: .leading, spacing: 16) {
            if !model.style.template.isPalette {
                sectionTitle("相机与品牌", caption: "CAMERA & IDENTITY")
                labeledField("品牌文字", placeholder: "例如 Nikon", text: $model.metadata.brand)
                labeledField("相机型号", placeholder: "例如 NIKON Z 6_2", text: $model.metadata.camera)
                HStack(spacing: 7) {
                    Button { model.chooseLogo() } label: { Label(model.logoName == nil ? "使用自定义 Logo" : "更换 Logo", systemImage: "photo.on.rectangle") }
                        .font(.system(size: 10)).controlSize(.small)
                    if model.logoName != nil { Button { model.removeLogo() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("移除自定义 Logo") }
                }
                if let name = model.logoName { Text(name).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1) }
                else { Text("默认品牌为字体样式，可用透明 PNG 替换").font(.system(size: 9)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true) }
                Divider().padding(.vertical, 2)
                sectionTitle("拍摄参数", caption: "PHOTO DETAILS")
                HStack(spacing: 12) {
                    labeledField("焦距 · mm", placeholder: "24.0", text: $model.metadata.focalLength)
                    labeledField("光圈 · f/", placeholder: "22.0", text: $model.metadata.aperture)
                }
                HStack(spacing: 12) {
                    labeledField("快门", placeholder: "1/15", text: $model.metadata.shutter)
                    labeledField("ISO", placeholder: "200", text: $model.metadata.iso)
                }
                if let photo = model.photo, !model.isDemo {
                    let hasMetadata = !photo.metadata.parameterLine.isEmpty || !photo.metadata.camera.isEmpty
                    Label(hasMetadata ? "已从 EXIF 读取，可手动修改" : "未检测到 EXIF，请手动填写", systemImage: hasMetadata ? "checkmark.circle" : "info.circle")
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Button("恢复照片原始参数") { model.restoreMetadata() }
                    .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
                Divider().padding(.vertical, 2)
            }
            labeledField("个人落款 · 选填", placeholder: "© 你的名字 / 拍摄地点", text: $model.style.signature)
            slider("落款字号", value: $model.style.signatureScale, range: 0.5...2,
                   display: "\(Int((model.style.signatureScale * 100).rounded()))%", defaultValue: FrameStyle().signatureScale)
                .font(.system(size: 11))
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
            Text("中文与全角标点使用中文字体；英文、数字与半角符号使用英文字体。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            if !SignatureTypography.isAvailable(model.style.signatureChineseFont)
                || !SignatureTypography.isAvailable(model.style.signatureEnglishFont) {
                Text("所选字体未安装，暂用系统字体替代。可从菜单选择本机已有字体。")
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
            if model.style.template.isPalette {
                Text("个人落款显示在照片底部，可留空；色卡模板不显示相机和拍摄参数。")
                    .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            } else { HStack {
                Toggle("品牌", isOn: $model.style.showBrand)
                Toggle("型号", isOn: $model.style.showCamera)
                Toggle("参数", isOn: $model.style.showParameters)
            }.toggleStyle(.checkbox).font(.system(size: 10)) }
        }
        }
    }

    private var batchTemplateNote: String {
        switch model.style.template {
        case .classicFrame: return model.style.classicBrand == .automatic
            ? "共用经典版式，每张照片分别识别品牌、型号与拍摄参数；缺少的信息留空。"
            : "手动选择的品牌共用于整批照片，型号、拍摄参数与日期按照片分别读取。"
        case .tickets: return "共用票券标题、副标题、邮戳或条码；拍摄日期按各张照片读取，自定义日期整批共用。"
        case .walkTicket: return "共用横向票根与文案，每张照片分别取色和读取日期；手动色卡沿用各张照片的编辑。"
        case .postageFrame: return "共用邮票样式和地点；拍摄日期按每张照片分别读取，自定义日期则整批共用。"
        case .colorWalk: return "共用背景模式、盖章和版式，每张照片分别提取纯色或条纹；手动颜色与拍摄时间按照片保留。"
        case .colorCircles, .colorSquares: return "沿用当前色卡样式与落款，每张照片独立提取主色。"
        case .softFrame: return "沿用当前画框、落款和 Logo，保留每张照片的拍摄参数。"
        case .film35: return "共用胶片标签、编号和版式，日期与拍摄参数按各张照片读取；编号为手填，整批共用。"
        case .gallery, .instant: return "共用文案、相纸和落款；拍摄日期逐张读取，自定义日期整批共用，保留完整照片。"
        case .cinema: return "共用字幕、场次标记和幕边，保留各张照片的完整构图；个人落款可选择显示。"
        case .tornPaper: return "共用撕边样式，撕裂只作用于照片最外沿；可选底部落款区，日期逐张读取。"
        case .receipt: return "共用小票文案和纸面，各张照片分别读取拍摄日期和相机信息；编号为手填，整批共用。"
        case .editorial: return "共用杂志标题和版式，拍摄日期与自动强调色逐张读取；自定义颜色整批共用。"
        }
    }

    private var classicBrandEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("摄影品牌", selection: $model.style.classicBrand) {
                ForEach(CameraBrand.allCases) { Text($0.rawValue).tag($0) }
            }.controlSize(.small).accessibilityIdentifier("classic-brand")
            let brand = model.style.classicBrand.resolved(metadata: model.metadata)
            if model.style.classicBrand == .automatic {
                Text(brand == .custom ? "未识别到已知品牌，可手动选择；已有品牌文字会保留。" : "当前识别：" + brand.label + " · 批量逐张识别")
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
            if model.style.classicBrand == .custom {
                labeledField("品牌文字", placeholder: "输入品牌名称", text: $model.metadata.brand)
            }
            if !(model.style.classicUseCustomLogo && model.hasCustomLogo) {
                ClassicBrandPreview(brand: brand, colored: model.style.classicBrandColor, fallback: model.metadata.brand)
                    .frame(maxWidth: .infinity).frame(height: 44).padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("经典品牌标志预览：" + (brand == .custom ? model.metadata.brand : brand.label))
            }
            HStack {
                Button(model.logoName == nil ? "上传自定义 Logo" : "更换自定义 Logo") { model.chooseLogo(useForClassic: true) }
                    .controlSize(.small)
                if model.logoName != nil { Button { model.removeLogo() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("移除自定义 Logo") }
            }
            if model.hasCustomLogo {
                Toggle("使用上传的 Logo", isOn: $model.style.classicUseCustomLogo).toggleStyle(.switch).controlSize(.mini)
                if let name = model.logoName { Text(name).font(.system(size: 9)).foregroundStyle(muted) }
            }
            Toggle("使用品牌色", isOn: $model.style.classicBrandColor).toggleStyle(.switch).controlSize(.mini)
                .disabled(model.style.classicUseCustomLogo && model.hasCustomLogo)
        }.font(.system(size: 11))
    }

    private var classicMetadataEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("经典品牌", caption: "CAMERA BRAND")
            classicBrandEditor
            Divider()
            sectionTitle("拍摄信息", caption: "PHOTO DETAILS")
            labeledField("相机型号", placeholder: "例如 NIKON Z 6_2", text: $model.metadata.camera)
            HStack(spacing: 12) {
                labeledField("焦距 · mm", placeholder: "24.0", text: $model.metadata.focalLength)
                labeledField("光圈 · f/", placeholder: "2.8", text: $model.metadata.aperture)
            }
            HStack(spacing: 12) {
                labeledField("快门", placeholder: "1/125", text: $model.metadata.shutter)
                labeledField("ISO", placeholder: "200", text: $model.metadata.iso)
            }
            Button("恢复照片原始参数") { model.restoreMetadata() }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
            Divider()
            labeledField("个人落款 · 选填", placeholder: "© 你的名字 / 拍摄地点", text: $model.style.signature)
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
            Text("照片参数按各张照片保存；品牌与版式在「画框样式」中调整。").font(.system(size: 9)).foregroundStyle(muted)
        }
    }

    private var classicEditor: some View {
        let defaults = FrameStyle()
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle("经典画框", caption: "CLASSIC CAMERA FRAME")
            Picker("底栏布局", selection: $model.style.classicArrangement) {
                ForEach(ClassicArrangement.allCases) { Text($0.rawValue).tag($0) }
            }.controlSize(.small).accessibilityIdentifier("classic-arrangement")
            classicBrandEditor
            Divider()
            Toggle("显示相机型号", isOn: $model.style.classicShowCamera)
            Toggle("显示拍摄参数", isOn: $model.style.classicShowParameters)
            Toggle("显示拍摄日期", isOn: $model.style.classicShowDate)
            Toggle("显示个人落款", isOn: $model.style.classicShowSignature)
            Text("型号、参数和落款可在「水印信息」中编辑。缺少 EXIF 的日期留空。").font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            Divider()
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("经典底栏高度", value: $model.style.classicFooter, range: 0.06...0.22,
                display: String(format: "%.1f%%", model.style.classicFooter * 100), defaultValue: defaults.classicFooter)
            slider("经典白边留白", value: $model.style.classicMargin, range: 0...0.08,
                display: String(format: "%.1f%%", model.style.classicMargin * 100), defaultValue: defaults.classicMargin)
            slider("品牌标志大小", value: $model.style.classicBrandScale, range: 0.5...2,
                display: String(format: "%.0f%%", model.style.classicBrandScale * 100), defaultValue: defaults.classicBrandScale)
            slider("拍摄信息字号", value: $model.style.classicInfoScale, range: 0.5...2,
                display: String(format: "%.0f%%", model.style.classicInfoScale * 100), defaultValue: defaults.classicInfoScale)
            Button("恢复经典默认版式") { model.resetClassicStyle() }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
        }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
    }

    private var printEditor: some View {
        VStack(alignment: .leading, spacing: 17) {
            printContentEditor
            Divider()
            sectionTitle("纸面与版式", caption: "PAPER & LAYOUT")
            Text(model.style.template == .tornPaper ? "撕裂只作用于最外沿，照片主体保持原色。双击数值可恢复默认值。" : "保留完整照片。双击滑块数值可恢复该项默认值。")
                .font(.system(size: 9)).foregroundStyle(muted)
            printLayoutEditor
            Button("恢复此模板版式") { model.resetPrintStyle() }
                .buttonStyle(.plain).foregroundStyle(accent)
        }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
    }

    private var printContentEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(model.style.template.title, caption: "PRINT COLLECTION")
            printSpecificContent
            Divider()
            labeledField("个人落款", placeholder: "你的名字 / 摄影签名 · 选填", text: $model.style.signature)
            slider("落款字号", value: $model.style.signatureScale, range: 0.5...2,
                display: String(format: "%.0f%%", model.style.signatureScale * 100), defaultValue: FrameStyle().signatureScale)
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
            Text("落款与中英文字体沿用公共设置；各模板的标题字体可单独选择。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
        }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
    }

    @ViewBuilder private var printSpecificContent: some View {
        switch model.style.template {
        case .film35:
            labeledField("胶片标签", placeholder: "FILM", text: $model.style.film35.label)
            labeledField("画面编号", placeholder: "01", text: $model.style.film35.number)
            Text("标签与编号为装饰文案，整批共用；边字使用等宽字体。")
                .font(.system(size: 9)).foregroundStyle(muted)
            printDateEditor($model.style.film35.dateMode, custom: $model.style.film35.customDate)
            Toggle("显示拍摄参数", isOn: $model.style.film35.showParameters)
            if model.style.film35.showParameters {
                labeledField("焦距 mm", placeholder: "35", text: $model.metadata.focalLength)
                labeledField("光圈 f/", placeholder: "2.8", text: $model.metadata.aperture)
                labeledField("快门", placeholder: "1/125", text: $model.metadata.shutter)
                labeledField("ISO", placeholder: "200", text: $model.metadata.iso)
            }
            Toggle("显示个人落款", isOn: $model.style.film35.showSignature)
        case .gallery:
            labeledField("作品名称", placeholder: "作品名 · 选填", text: $model.style.gallery.title)
            labeledField("作品说明", placeholder: "系列 / 地点 · 选填", text: $model.style.gallery.subtitle)
            SignatureFontPicker(title: "作品名字体", selection: $model.style.gallery.titleFont, chinese: false)
            printDateEditor($model.style.gallery.dateMode, custom: $model.style.gallery.customDate)
            Toggle("显示个人落款", isOn: $model.style.gallery.showSignature)
        case .editorial:
            labeledField("杂志标题", placeholder: "WANDER / 城市名", text: $model.style.editorial.title)
            labeledField("副标题", placeholder: "旅行影像日志", text: $model.style.editorial.subtitle)
            labeledField("期号", placeholder: "VOL. 01", text: $model.style.editorial.edition)
            labeledField("旅途短句", placeholder: "一句旅途笔记 · 选填", text: $model.style.editorial.notes)
            SignatureFontPicker(title: "杂志标题字体", selection: $model.style.editorial.titleFont, chinese: false)
            printDateEditor($model.style.editorial.dateMode, custom: $model.style.editorial.customDate)
            Toggle("显示个人落款", isOn: $model.style.editorial.showSignature)
        case .instant:
            labeledField("相纸短句", placeholder: "Keep this moment.", text: $model.style.instant.caption)
            SignatureFontPicker(title: "短句英文字体", selection: $model.style.instant.captionFont, chinese: false)
            printDateEditor($model.style.instant.dateMode, custom: $model.style.instant.customDate)
            Toggle("显示个人落款", isOn: $model.style.instant.showSignature)
        case .cinema:
            labeledField("主字幕", placeholder: "把日常，留给时间。", text: $model.style.cinema.subtitle)
            labeledField("第二行字幕", placeholder: "Let the ordinary become a scene.", text: $model.style.cinema.translation)
            labeledField("场次标记", placeholder: "SCENE 01 · 选填", text: $model.style.cinema.scene)
            Text("字幕放在黑色幕边，保留完整照片，不自动裁成电影比例。")
                .font(.system(size: 9)).foregroundStyle(muted)
            Toggle("显示个人落款", isOn: $model.style.cinema.showSignature)
        case .receipt:
            labeledField("小票标题", placeholder: "MEMORY RECEIPT", text: $model.style.receipt.title)
            labeledField("地点 / 店名", placeholder: "一个值得记住的地方 · 选填", text: $model.style.receipt.place)
            labeledField("小票编号", placeholder: "001", text: $model.style.receipt.number)
            labeledField("票尾短句", placeholder: "THANK YOU FOR THIS MOMENT", text: $model.style.receipt.note)
            printDateEditor($model.style.receipt.dateMode, custom: $model.style.receipt.customDate)
            Toggle("显示拍摄参数", isOn: $model.style.receipt.showParameters)
            Toggle("显示个人落款", isOn: $model.style.receipt.showSignature)
        case .tornPaper:
            Toggle("显示底部落款区", isOn: $model.style.tornPaper.showCaptionArea)
            Text("默认呈现整张撕边照片。开启落款区可显示短句、日期和个人落款；撕裂仅作用于最外沿。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            if model.style.tornPaper.showCaptionArea {
                labeledField("纸上短句", placeholder: "A quiet moment.", text: $model.style.tornPaper.caption)
                SignatureFontPicker(title: "短句英文字体", selection: $model.style.tornPaper.captionFont, chinese: false)
                printDateEditor($model.style.tornPaper.dateMode, custom: $model.style.tornPaper.customDate)
                Toggle("显示个人落款", isOn: $model.style.tornPaper.showSignature)
            }
        default: EmptyView()
        }
    }

    private func printDateEditor(_ mode: Binding<TicketDateMode>, custom: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("日期", selection: mode) {
                ForEach(TicketDateMode.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("print-date-mode")
            if mode.wrappedValue == .custom {
                labeledField("自定义日期", placeholder: "22 OCT 2026", text: custom)
            } else if mode.wrappedValue == .captureDate {
                let value = TicketDateMode.captureDate.text(metadata: model.metadata, custom: "")
                Text(value.isEmpty ? "照片没有有效拍摄日期，将留空。" : "从照片读取：\(value)")
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
        }
    }

    @ViewBuilder private var printLayoutEditor: some View {
        switch model.style.template {
        case .film35:
            Toggle("显示胶片齿孔", isOn: $model.style.film35.showSprockets)
            printPercentSlider("胶片侧边", value: $model.style.film35.margin, range: 0.035...0.12, defaultValue: Film35Style().margin)
            printPercentSlider("上下片边", value: $model.style.film35.rail, range: 0.065...0.14, defaultValue: Film35Style().rail)
            printPercentSlider("胶片边字", value: $model.style.film35.textScale, range: 0.65...1.6, defaultValue: Film35Style().textScale)
        case .gallery:
            printPaperPicker($model.style.gallery.paper)
            Toggle("显示细内框", isOn: $model.style.gallery.showOutline)
            printPercentSlider("画廊留白", value: $model.style.gallery.margin, range: 0.045...0.18, defaultValue: GalleryStyle().margin)
            Text("竖版照片两侧额外增加 2% 留白。")
                .font(.system(size: 9)).foregroundStyle(muted)
            printPercentSlider("作品落款区", value: $model.style.gallery.footer, range: 0.12...0.26, defaultValue: GalleryStyle().footer)
            printPercentSlider("画廊文字", value: $model.style.gallery.textScale, range: 0.65...1.6, defaultValue: GalleryStyle().textScale)
        case .editorial:
            printPaperPicker($model.style.editorial.paper)
            Toggle("显示强调色细线", isOn: $model.style.editorial.showAccent)
            if model.style.editorial.showAccent {
                Picker("强调色", selection: $model.style.editorial.accent) {
                    ForEach(EditorialAccent.allCases) { Text($0.rawValue).tag($0) }
                }
                if model.style.editorial.accent == .custom {
                    ColorPicker("自定义强调色", selection: editorialAccentBinding, supportsOpacity: false)
                    Text(model.style.editorial.accentHex).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }
                Text("自动强调色取自各张照片；自定义颜色共用于整批照片。")
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
            printPercentSlider("杂志侧边", value: $model.style.editorial.margin, range: 0.025...0.12, defaultValue: EditorialStyle().margin)
            printPercentSlider("标题区高度", value: $model.style.editorial.header, range: 0.17...0.32, defaultValue: EditorialStyle().header)
            printPercentSlider("杂志底栏", value: $model.style.editorial.footer, range: 0.09...0.20, defaultValue: EditorialStyle().footer)
            printPercentSlider("杂志文字", value: $model.style.editorial.textScale, range: 0.65...1.6, defaultValue: EditorialStyle().textScale)
        case .instant:
            printPaperPicker($model.style.instant.paper)
            printPercentSlider("相纸外留白", value: $model.style.instant.margin, range: 0.035...0.12, defaultValue: InstantStyle().margin)
            printPercentSlider("相纸白边", value: $model.style.instant.border, range: 0.025...0.075, defaultValue: InstantStyle().border)
            printPercentSlider("相纸底边", value: $model.style.instant.footer, range: 0.10...0.24, defaultValue: InstantStyle().footer)
            printPercentSlider("相纸文字", value: $model.style.instant.textScale, range: 0.65...1.6, defaultValue: InstantStyle().textScale)
            printPercentSlider("相纸阴影", value: $model.style.instant.shadow, range: 0...0.35, defaultValue: InstantStyle().shadow)
        case .cinema:
            Picker("字幕颜色", selection: $model.style.cinema.ink) {
                ForEach(CinemaInk.allCases) { Text($0.rawValue).tag($0) }
            }
            printPercentSlider("上幕边", value: $model.style.cinema.top, range: 0.025...0.14, defaultValue: CinemaStyle().top)
            printPercentSlider("字幕幕边", value: $model.style.cinema.bottom, range: 0.12...0.30, defaultValue: CinemaStyle().bottom)
            printPercentSlider("字幕上下位置", value: $model.style.cinema.position, range: 0...1, defaultValue: CinemaStyle().position)
            printPercentSlider("字幕字号", value: $model.style.cinema.textScale, range: 0.65...1.6, defaultValue: CinemaStyle().textScale)
        case .receipt:
            printPaperPicker($model.style.receipt.paper)
            printPercentSlider("小票外留白", value: $model.style.receipt.margin, range: 0.06...0.18, defaultValue: ReceiptStyle().margin)
            printPercentSlider("票尾高度", value: $model.style.receipt.footer, range: 0.22...0.38, defaultValue: ReceiptStyle().footer)
            printPercentSlider("小票文字", value: $model.style.receipt.textScale, range: 0.65...1.6, defaultValue: ReceiptStyle().textScale)
        case .tornPaper:
            printPaperPicker($model.style.tornPaper.paper)
            printPercentSlider("撕边外留白", value: $model.style.tornPaper.margin, range: 0.035...0.14, defaultValue: TornPaperStyle().margin)
            printPercentSlider("撕边白边", value: $model.style.tornPaper.border, range: 0.004...0.08, defaultValue: TornPaperStyle().border)
            if model.style.tornPaper.showCaptionArea {
                printPercentSlider("纸上落款区", value: $model.style.tornPaper.footer, range: 0.09...0.22, defaultValue: TornPaperStyle().footer)
            }
            printPercentSlider("撕裂程度", value: $model.style.tornPaper.roughness, range: 0.001...0.008, defaultValue: TornPaperStyle().roughness)
            printPercentSlider("纸面阴影", value: $model.style.tornPaper.shadow, range: 0...0.35, defaultValue: TornPaperStyle().shadow)
            printPercentSlider("纸上文字", value: $model.style.tornPaper.textScale, range: 0.65...1.6, defaultValue: TornPaperStyle().textScale)
        default: EmptyView()
        }
    }

    private func printPaperPicker(_ binding: Binding<PrintPaper>) -> some View {
        Picker("纸面颜色", selection: binding) {
            ForEach(PrintPaper.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("print-paper")
    }

    private func printPercentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, defaultValue: Double) -> some View {
        slider(title, value: value, range: range, display: String(format: "%.1f%%", value.wrappedValue * 100), defaultValue: defaultValue)
    }

    private var editorialAccentBinding: Binding<Color> {
        Binding(get: { Color(nsColor: (PaletteColor(hex: model.style.editorial.accentHex) ?? PaletteColor(hex: "#8B7565")!).color) },
            set: { value in
                guard let c = NSColor(value).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
                model.style.editorial.accentHex = String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
            })
    }

    private var walkTicketContentEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("漫步票根", caption: "ROUTE WALK")
            labeledField("顶部短句 · 选填", placeholder: "「漫步日志」", text: $model.style.walkTicket.heading)
            labeledField("大标题", placeholder: "COLOR WALK / 城市名称", text: $model.style.walkTicket.title)
                .accessibilityIdentifier("walkticket-title")
            labeledField("副标题", placeholder: "漫步日志 / 地点", text: $model.style.walkTicket.subtitle)
                .accessibilityIdentifier("walkticket-subtitle")
            Picker("票根日期", selection: $model.style.walkTicket.dateMode) {
                ForEach(TicketDateMode.allCases) { Text($0.rawValue).tag($0) }
            }.controlSize(.small)
            if model.style.walkTicket.dateMode == .custom {
                labeledField("自定义日期", placeholder: "10.22 / 22 OCT 2026", text: $model.style.walkTicket.customDate)
            } else if model.style.walkTicket.dateMode == .captureDate {
                let date = TicketDateMode.captureDate.text(metadata: model.metadata, custom: "")
                Text(date.isEmpty ? "照片没有有效拍摄日期，日期留空。" : "从照片读取：" + date)
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
            labeledField("备注 / 坐标 · 手填", placeholder: "旅途笔记，或自己填写坐标", text: $model.style.walkTicket.notes)
            Text("地点与坐标只使用你填写的文字，不读取 GPS 或猜测照片位置。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            SignatureFontPicker(title: "大标题字体", selection: $model.style.walkTicket.titleFont, chinese: false)
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
        }.font(.system(size: 11))
    }

    private var walkTicketPaperBinding: Binding<Color> {
        Binding(get: { Color(nsColor: model.style.walkTicket.paperColor(photo: model.photo)) }, set: { value in
            guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
            func byte(_ value: CGFloat) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
            var updated = model.style.walkTicket
            updated.customHex = PaletteColor(red: byte(color.redComponent), green: byte(color.greenComponent), blue: byte(color.blueComponent)).hex
            updated.theme = .custom
            model.style.walkTicket = updated
        })
    }

    private var walkTicketPaletteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("主色色卡", caption: "COLOR CARD")
            Toggle("显示色卡与右侧色带", isOn: $model.style.walkTicket.showPalette)
            if model.style.walkTicket.showPalette {
                HStack {
                    Text("自动取色数量")
                    Spacer()
                    Picker("漫步票根色块数量", selection: $model.style.walkTicket.paletteCount) {
                        ForEach(2...8, id: \.self) { Text("\($0) 色").tag($0) }
                    }.labelsHidden().frame(width: 100).disabled(model.hasManualPalette)
                }
                Picker("颜色排序", selection: $model.style.paletteOrder) {
                    ForEach(PaletteOrder.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(model.hasManualPalette)
                if let photoID = model.selectedID {
                    ForEach(Array(model.paletteSwatches.enumerated()), id: \.element.id) { index, swatch in
                        paletteColorRow(swatch, number: index + 1, photoID: photoID)
                    }
                }
                Button("恢复自动取色") { model.restoreAutomaticPalette() }
                    .buttonStyle(.plain).foregroundStyle(accent).disabled(!model.hasManualPalette)
                Toggle("显示色块 HEX", isOn: $model.style.walkTicket.showHex)
                Text(model.hasManualPalette ? "手动改色与删除按照片保存，与圆形、方形色卡共用。" : "每张照片独立取色；可点选改色、输入 HEX 或删除色块。")
                    .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            }
        }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
    }

    private var walkTicketEditor: some View {
        let defaults = WalkTicketStyle()
        return VStack(alignment: .leading, spacing: 16) {
            walkTicketContentEditor
            Divider()
            sectionTitle("票面与照片", caption: "PAPER & PHOTO")
            Picker("票面配色", selection: $model.style.walkTicket.theme) {
                ForEach(WalkTicketTheme.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("walkticket-theme")
            ColorPicker("票面颜色", selection: walkTicketPaperBinding, supportsOpacity: false)
            if model.style.walkTicket.theme == .custom {
                labeledField("票面 HEX", placeholder: "#494644", text: $model.style.walkTicket.customHex)
                if PaletteColor(hex: model.style.walkTicket.customHex) == nil {
                    Text("请输入六位 HEX 色号；未完成时暂用默认深灰。")
                        .font(.system(size: 9)).foregroundStyle(.red)
                }
            }
            Picker("照片显示", selection: $model.style.walkTicket.photoMode) {
                ForEach(WalkTicketPhotoMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("walkticket-photo-mode")
            Text("完整照片保留全部构图；填满裁切将照片居中填满左侧窗口。文字自动匹配票面明暗。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            Divider()
            walkTicketPaletteEditor
            Divider()
            sectionTitle("右侧票根", caption: "ADMIT ONE")
            labeledField("竖排票根文字", placeholder: "ADMIT ONE · NO. 02", text: $model.style.walkTicket.admission)
            labeledField("右下角文字", placeholder: "ROUTE WALK", text: $model.style.walkTicket.stubCaption)
            Toggle("显示装饰条码", isOn: $model.style.walkTicket.showBarcode)
                .accessibilityIdentifier("walkticket-decoration")
            Text("同色线条与票根文字呼应，作为装饰，不编码或存储内容。")
                .font(.system(size: 9)).foregroundStyle(muted)
            Divider()
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("票根留白", value: $model.style.walkTicket.margin, range: 0.05...0.16,
                display: String(format: "%.1f%%", model.style.walkTicket.margin * 100), defaultValue: defaults.margin)
            slider("票面高宽比", value: $model.style.walkTicket.aspect, range: 0.44...0.64,
                display: String(format: "%.0f%%", model.style.walkTicket.aspect * 100), defaultValue: defaults.aspect)
            slider("票根圆角", value: $model.style.walkTicket.corner, range: 0...0.045,
                display: String(format: "%.1f%%", model.style.walkTicket.corner * 100), defaultValue: defaults.corner)
            slider("票根字号", value: $model.style.walkTicket.textScale, range: 0.5...2,
                display: String(format: "%.0f%%", model.style.walkTicket.textScale * 100), defaultValue: defaults.textScale)
            slider("票根阴影", value: $model.style.walkTicket.shadow, range: 0...1,
                display: String(format: "%.0f%%", model.style.walkTicket.shadow * 100), defaultValue: defaults.shadow)
            Button("恢复漫步票根版式") { model.resetWalkTicketStyle() }
                .buttonStyle(.plain).foregroundStyle(accent)
        }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
    }

    private var ticketContentEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("旅途票根", caption: "TICKETS")
            labeledField("标题 / 地点", placeholder: "Beijing / 旅行标题", text: $model.style.ticketTitle)
                .accessibilityIdentifier("ticket-title")
            labeledField("副标题 · 选填", placeholder: "北京 / 这一程的记录", text: $model.style.ticketSubtitle)
                .accessibilityIdentifier("ticket-subtitle")
            Picker("票券日期", selection: $model.style.ticketDateMode) {
                ForEach(TicketDateMode.allCases) { Text($0.rawValue).tag($0) }
            }.controlSize(.small).accessibilityIdentifier("ticket-date-mode")
            if model.style.ticketDateMode == .custom {
                labeledField("自定义日期", placeholder: "18 OCT 2026", text: $model.style.ticketCustomDate)
                    .accessibilityIdentifier("ticket-date")
            } else if model.style.ticketDateMode == .captureDate {
                let date = TicketDateMode.captureDate.text(metadata: model.metadata, custom: "")
                Text(date.isEmpty ? "照片没有有效拍摄日期，日期留空。" : "从照片读取：" + date)
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
        }.font(.system(size: 11))
    }

    private var ticketEditor: some View {
        let defaults = FrameStyle()
        return VStack(alignment: .leading, spacing: 16) {
            ticketContentEditor
            Divider()
            sectionTitle("右下角贴印", caption: "POSTMARK & BARCODE")
            Picker("票券贴印", selection: $model.style.ticketMark) {
                ForEach(TicketMark.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("ticket-mark")
            if model.style.ticketMark == .stamp {
                labeledField("邮戳上弧文字", placeholder: "WORLD POST", text: $model.style.ticketStampTop)
                labeledField("邮戳下弧文字", placeholder: "AIR MAIL", text: $model.style.ticketStampBottom)
            } else if model.style.ticketMark == .barcode {
                labeledField("条码内容", placeholder: "FRAMESTUDIO", text: $model.style.ticketBarcodeValue)
                    .accessibilityIdentifier("ticket-barcode")
                if !TicketBarcode.content(model.style.ticketBarcodeValue).isEmpty && !TicketBarcode.isValid(model.style.ticketBarcodeValue) {
                    Text("请使用 48 个以内的英文、数字或半角符号，修改后即可导出。")
                        .font(.system(size: 9)).foregroundStyle(.red)
                } else {
                    Text("Code 128 · 内容可自定义，留空隐藏；不会自动写入照片位置等信息。识读效果受导出尺寸影响。")
                        .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
                }
            }
            if model.style.ticketMark != .none {
                slider("贴印大小", value: $model.style.ticketMarkScale, range: 0.6...1.3,
                    display: String(format: "%.0f%%", model.style.ticketMarkScale * 100), defaultValue: defaults.ticketMarkScale)
            }
            Divider()
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("票券留白", value: $model.style.ticketMargin, range: 0.08...0.24,
                display: String(format: "%.1f%%", model.style.ticketMargin * 100), defaultValue: defaults.ticketMargin)
            slider("票券白边", value: $model.style.ticketBorder, range: 0.018...0.05,
                display: String(format: "%.1f%%", model.style.ticketBorder * 100), defaultValue: defaults.ticketBorder)
            slider("票根底栏", value: $model.style.ticketFooter, range: 0.13...0.30,
                display: String(format: "%.1f%%", model.style.ticketFooter * 100), defaultValue: defaults.ticketFooter)
            slider("票券齿孔", value: $model.style.ticketPerforation, range: 0.004...0.012,
                display: String(format: "%.2f%%", model.style.ticketPerforation * 100), defaultValue: defaults.ticketPerforation)
            slider("票券文字大小", value: $model.style.ticketTextScale, range: 0.5...2,
                display: String(format: "%.0f%%", model.style.ticketTextScale * 100), defaultValue: defaults.ticketTextScale)
            slider("背景虚化", value: $model.style.ticketBlur, range: 0...0.085,
                display: String(format: "%.0f%%", model.style.ticketBlur / 0.085 * 100), defaultValue: defaults.ticketBlur)
            slider("背景明暗", value: $model.style.ticketBrightness, range: -0.5...0.5,
                display: String(format: "%+.0f%%", model.style.ticketBrightness * 100), defaultValue: defaults.ticketBrightness)
            slider("悬浮阴影", value: $model.style.ticketShadow, range: 0...1,
                display: String(format: "%.0f%%", model.style.ticketShadow * 100), defaultValue: defaults.ticketShadow)
            Button("恢复票券默认版式") { model.resetTicketStyle() }
                .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
        }.font(.system(size: 11))
    }

    private var postageVariantPicker: some View {
        Picker("邮票样式", selection: $model.style.postageVariant) {
            ForEach(PostageVariant.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("postage-variant")
    }

    private var postageTextEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("旅途落款", caption: "PLACE & DATE")
            labeledField("地点 · 选填", placeholder: "Beijing / 拍摄地点", text: $model.style.postagePlace)
                .accessibilityIdentifier("postage-place")
            Picker("日期内容", selection: $model.style.postageDateMode) {
                ForEach(PostageDateMode.allCases) { Text($0.rawValue).tag($0) }
            }.controlSize(.small)
            if model.style.postageDateMode == .custom {
                labeledField("自定义日期", placeholder: "2026/10/11", text: $model.style.postageCustomDate)
                    .accessibilityIdentifier("postage-date")
            } else if model.style.postageDateMode == .captureDate {
                let date = PostageDateMode.captureDate.text(metadata: model.metadata, custom: "")
                Text(date.isEmpty ? "照片没有有效拍摄日期，日期留空；也可以手动填写。" : "从照片读取：" + date)
                    .font(.system(size: 9)).foregroundStyle(muted)
            }
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
        }.font(.system(size: 11))
    }

    private var postageEditor: some View {
        let defaults = FrameStyle()
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle("邮票画框", caption: "POSTAGE FRAME")
            postageVariantPicker
            Text("齿孔白边与悬浮阴影，背景来自同一张照片。横竖构图均保留完整画面。")
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(muted)
            if model.style.postageVariant == .caption { postageTextEditor; Divider() }
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("画框留白", value: $model.style.postageMargin, range: 0.035...0.19,
                display: String(format: "%.1f%%", model.style.postageMargin * 100), defaultValue: defaults.postageMargin)
            slider("邮票白边", value: $model.style.postageBorder, range: 0.014...0.06,
                display: String(format: "%.1f%%", model.style.postageBorder * 100), defaultValue: defaults.postageBorder)
            slider("齿孔大小", value: $model.style.postagePerforation, range: 0.006...0.022,
                display: String(format: "%.2f%%", model.style.postagePerforation * 100), defaultValue: defaults.postagePerforation)
            if model.style.postageVariant == .caption {
                slider("落款底栏", value: $model.style.postageFooter, range: 0.07...0.18,
                    display: String(format: "%.1f%%", model.style.postageFooter * 100), defaultValue: defaults.postageFooter)
                slider("邮票文字大小", value: $model.style.postageTextScale, range: 0.5...2,
                    display: String(format: "%.0f%%", model.style.postageTextScale * 100), defaultValue: defaults.postageTextScale)
            }
            slider("背景虚化", value: $model.style.postageBlur, range: 0...0.085,
                display: String(format: "%.0f%%", model.style.postageBlur / 0.085 * 100), defaultValue: defaults.postageBlur)
            slider("背景明暗", value: $model.style.postageBrightness, range: -0.5...0.5,
                display: String(format: "%+.0f%%", model.style.postageBrightness * 100), defaultValue: defaults.postageBrightness)
            slider("悬浮阴影", value: $model.style.postageShadow, range: 0...1,
                display: String(format: "%.0f%%", model.style.postageShadow * 100), defaultValue: defaults.postageShadow)
            Button("恢复邮票默认样式") { model.resetPostageStyle() }
                .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
        }.font(.system(size: 11))
    }

    private var colorWalkStampEditor: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("文字盖章", caption: "STAMP")
            Toggle("显示文字盖章", isOn: $model.style.colorWalkShowStamp).toggleStyle(.switch).controlSize(.mini)
            labeledField("主文字", placeholder: "Stay alive · keep trying", text: $model.style.colorWalkStamp)
                .accessibilityIdentifier("colorwalk-stamp")
            HStack {
                Text("第二行").font(.system(size: 11))
                Spacer()
                Picker("第二行内容", selection: $model.style.colorWalkDetail) {
                    ForEach(ColorWalkDetail.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 132).controlSize(.small)
            }
            if model.style.colorWalkDetail == .custom {
                labeledField("第二行文字", placeholder: "拍摄地点 / 日期 / 一句心情", text: $model.style.colorWalkCustomDetail)
            } else if model.style.colorWalkDetail == .captureTime || model.style.colorWalkDetail == .captureDate {
                let detail = model.style.colorWalkDetail.text(metadata: model.metadata, custom: "")
                Text(detail.isEmpty ? "照片没有拍摄时间，第二行留空；也可以选择自定义文字。" : "从照片读取：" + detail)
                    .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            }
            SignatureFontPicker(title: "中文字体", selection: $model.style.signatureChineseFont, chinese: true)
            SignatureFontPicker(title: "英文字体", selection: $model.style.signatureEnglishFont, chinese: false)
            Text("沿用个人落款的中英文字体，默认微软雅黑。")
                .font(.system(size: 9)).foregroundStyle(muted)
        }.font(.system(size: 11))
    }

    private var colorWalkEditor: some View {
        let defaults = FrameStyle()
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Color Walk", caption: "COLOR & STRIPES")
            Picker("背景样式", selection: Binding(get: { model.style.colorWalkBackground }, set: { model.selectColorWalkBackground($0) })) {
                ForEach(ColorWalkBackground.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("colorwalk-background")
            if model.style.colorWalkBackground == .horizontalStripes {
                colorWalkStripeEditor
            } else {
                Text("综合颜色占比、饱和度与明暗，选取照片的一种代表色。可手动调整，按照片分别保存。")
                    .font(.system(size: 10)).lineSpacing(3).foregroundStyle(muted)
                if let photoID = model.selectedID, let color = model.colorWalkColor {
                    HStack(spacing: 10) {
                        Button { model.chooseColorWalkColor(photoID: photoID) } label: {
                            RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: color.color)).frame(width: 42, height: 42)
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ink.opacity(0.14), lineWidth: 0.7))
                        }.buttonStyle(.plain).accessibilityLabel("修改 Color Walk 主色").accessibilityValue(color.hex)
                            .accessibilityIdentifier("colorwalk-color").help("点击修改颜色")
                        TextField("#RRGGBB", text: Binding(get: { model.colorWalkHex }, set: { model.setColorWalkHex($0, photoID: photoID) }))
                            .font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder)
                            .onSubmit { model.commitColorWalkHex(photoID: photoID) }
                            .accessibilityLabel("Color Walk HEX 色号").accessibilityIdentifier("colorwalk-hex")
                        Text(model.hasManualColorWalkColor ? "手动" : "自动").font(.system(size: 9)).foregroundStyle(muted)
                    }.disabled(model.isLoading)
                }
                Button("恢复自动主色") { model.restoreAutomaticColorWalkColor() }
                    .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
                    .disabled(!model.hasManualColorWalkColor || model.isLoading)
            }
            Divider()
            colorWalkStampEditor
            Divider()
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("色面高度", value: $model.style.colorWalkHeader, range: 0.25...1,
                display: String(format: "%.1f%%", model.style.colorWalkHeader * 100), defaultValue: defaults.colorWalkHeader)
            slider("盖章字号", value: $model.style.colorWalkTextScale, range: 0.5...2,
                display: "\(Int((model.style.colorWalkTextScale * 100).rounded()))%", defaultValue: defaults.colorWalkTextScale)
            slider("文字上下位置", value: $model.style.colorWalkTextPosition, range: 0...1,
                display: "\(Int((model.style.colorWalkTextPosition * 100).rounded()))%", defaultValue: defaults.colorWalkTextPosition)
            Text("左侧向上，右侧向下；两行文字一起移动。")
                .font(.system(size: 9)).foregroundStyle(muted)
            Picker("文字颜色", selection: $model.style.colorWalkInk) {
                ForEach(ColorWalkInk.allCases) { Text($0.rawValue).tag($0) }
            }.controlSize(.small)
            Button("恢复 Color Walk 默认版式") { model.resetColorWalkStyle() }
                .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 10))
        }.font(.system(size: 11))
    }

    private var colorWalkStripeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("多种主色按列表顺序从上到下等高拼接，每条横贯整个色面。")
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(muted)
            Picker("自动条纹数量", selection: $model.style.colorWalkStripeCount) {
                ForEach(2...8, id: \.self) { Text("\($0) 色").tag($0) }
            }.disabled(model.hasManualPalette).accessibilityIdentifier("colorwalk-stripe-count")
            Picker("条纹排序", selection: $model.style.paletteOrder) {
                ForEach(PaletteOrder.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(model.hasManualPalette)
            Text("当前 \(model.paletteColors.count) 种颜色").font(.system(size: 10, weight: .medium))
            if let photoID = model.selectedID {
                ForEach(Array(model.paletteSwatches.enumerated()), id: \.element.id) { index, swatch in
                    paletteColorRow(swatch, number: index + 1, photoID: photoID)
                }
            }
            Button("恢复条纹自动取色") { model.restoreAutomaticPalette() }
                .buttonStyle(.plain).foregroundStyle(accent).disabled(!model.hasManualPalette || model.isLoading)
            Text(model.paletteColors.isEmpty && model.hasManualPalette
                ? "已删除全部条纹，色面留白；可恢复自动取色。"
                : "支持逐个改色、输入 HEX 和删除；与色卡模板共用每张照片的手动色卡。纯色主色独立保留。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            Text("文字可选「自动对比」，在深浅条纹上分别使用黑白文字。")
                .font(.system(size: 9)).foregroundStyle(muted)
        }.controlSize(.small)
    }

    private var paletteEditor: some View {
        let defaults = FrameStyle()
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle(model.style.template.title, caption: "COLOR PALETTE")
            Text("从照片自动提取主色，按每张原片分别取色。")
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(muted)
            HStack {
                Text("自动取色数量")
                Spacer()
                Picker("色块数量", selection: $model.style.paletteCount) {
                    ForEach(2...8, id: \.self) { Text("\($0) 色").tag($0) }
                }.labelsHidden().frame(width: 100).disabled(model.hasManualPalette)
            }
            HStack {
                Text("颜色排序")
                Spacer()
                Picker("颜色排序", selection: $model.style.paletteOrder) {
                    ForEach(PaletteOrder.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 110).disabled(model.hasManualPalette)
            }
            if !model.paletteColors.isEmpty || model.hasManualPalette {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.hasManualPalette ? "手动色卡 · \(model.paletteColors.count) 色" : "识别到 \(model.paletteColors.count) 种主色")
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Button("恢复自动取色") { model.restoreAutomaticPalette() }
                            .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(accent)
                            .disabled(!model.hasManualPalette || model.isLoading)
                    }
                    if let photoID = model.selectedID {
                        ForEach(Array(model.paletteSwatches.enumerated()), id: \.element.id) { index, swatch in
                            paletteColorRow(swatch, number: index + 1, photoID: photoID)
                        }
                    }
                    if model.paletteColors.isEmpty {
                        Text("已删除全部色块，可恢复自动取色。")
                            .font(.system(size: 10)).foregroundStyle(muted).padding(.vertical, 6)
                    }
                }.padding(11).background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
            Text(model.hasManualPalette
                 ? "手动修改按照片保存。恢复自动取色后，可重新调整数量和排序。"
                 : "点击色块选色，或输入六位 HEX 色号；右侧减号可删除色块。颜色占比为近似值。")
                .font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            Toggle("显示 HEX 色号", isOn: $model.style.paletteShowHex).toggleStyle(.switch).controlSize(.small)
            if model.style.template == .colorSquares {
                Toggle("旋转为菱形", isOn: $model.style.paletteDiamond).toggleStyle(.switch).controlSize(.small)
            }
            Toggle("显示个人落款", isOn: $model.style.paletteShowSignature).toggleStyle(.switch).controlSize(.small)
            Divider()
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("白边留白", value: $model.style.paletteMargin, range: 0...0.08,
                   display: String(format: "%.1f%%", model.style.paletteMargin * 100), defaultValue: defaults.paletteMargin)
            slider("底栏高度", value: $model.style.paletteFooter, range: 0.10...0.25,
                   display: String(format: "%.1f%%", model.style.paletteFooter * 100), defaultValue: defaults.paletteFooter)
            slider("色块大小", value: $model.style.paletteSwatchSize, range: 0.03...0.095,
                   display: String(format: "%.1f%%", model.style.paletteSwatchSize * 100), defaultValue: defaults.paletteSwatchSize)
            Button("恢复色卡默认样式") { model.resetPaletteStyle() }
                .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 11))
        }.font(.system(size: 11))
    }

    private func paletteColorRow(_ swatch: EditablePaletteSwatch, number: Int, photoID: UUID) -> some View {
        HStack(spacing: 8) {
            Button { model.choosePaletteColor(photoID: photoID, swatchID: swatch.id) } label: {
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: swatch.color.color)).frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(0.12)))
            }.buttonStyle(.plain).help("点击修改颜色")
                .accessibilityLabel("修改色块 \(number) 颜色")
                .accessibilityValue(swatch.color.hex)
                .accessibilityIdentifier("palette-color-" + swatch.id.uuidString)
            TextField("#RRGGBB", text: Binding(
                get: { model.paletteHex(for: swatch.id) },
                set: { model.setPaletteHex($0, photoID: photoID, swatchID: swatch.id) }))
                .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced)).frame(width: 82)
                .onSubmit { model.commitPaletteHex(photoID: photoID, swatchID: swatch.id) }
                .help("六位 HEX 色号，例如 #AABBCC")
                .accessibilityLabel("色块 \(number) HEX 色号")
                .accessibilityIdentifier("palette-hex-" + swatch.id.uuidString)
            Spacer(minLength: 0)
            Text(swatch.modified ? "手动" : String(format: "%.0f%%", swatch.color.fraction * 100))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
            Button { model.removePaletteColor(photoID: photoID, swatchID: swatch.id) } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red.opacity(0.75))
            }.buttonStyle(.plain).help("删除这个色块")
                .accessibilityLabel("删除色块 \(number)")
                .accessibilityIdentifier("palette-remove-" + swatch.id.uuidString)
        }.disabled(model.isLoading)
    }

    private var styleEditor: some View {
        let defaults = FrameStyle()
        return VStack(alignment: .leading, spacing: 16) {
            sectionTitle("柔焦画框", caption: "SOFT FOCUS FRAME")
            Text("双击数值，恢复该项默认值").font(.system(size: 9)).foregroundStyle(muted)
            slider("背景虚化", value: $model.style.blur, range: 0...0.085, display: "\(Int(model.style.blur / 0.085 * 100))%", defaultValue: defaults.blur)
            slider("背景明暗", value: $model.style.brightness, range: -0.5...0.5, display: String(format: "%+.0f%%", model.style.brightness * 100), defaultValue: defaults.brightness)
            slider(model.isPortrait ? "竖版左右留白" : "横版左右留白", value: $model.currentMargin,
                   range: 0.015...0.15, display: String(format: "%.1f%%", model.currentMargin * 100),
                   defaultValue: model.isPortrait ? defaults.portraitMargin : defaults.margin)
            Text("横版与竖版的左右留白分别保存").font(.system(size: 9)).foregroundStyle(muted)
            slider("顶部留白", value: $model.style.topSpace, range: 0.025...0.15, display: String(format: "%.1f%%", model.style.topSpace * 100), defaultValue: defaults.topSpace)
            slider("底部留白", value: $model.style.footerSpace, range: 0.13...0.30, display: String(format: "%.1f%%", model.style.footerSpace * 100), defaultValue: defaults.footerSpace)
            slider("照片圆角", value: $model.style.corner, range: 0...0.05, display: "\(Int(model.style.corner / 0.05 * 100))%", defaultValue: defaults.corner)
            slider("悬浮阴影", value: $model.style.shadow, range: 0...1, display: "\(Int(model.style.shadow * 100))%", defaultValue: defaults.shadow)
            Divider()
            slider("文字大小", value: $model.style.textScale, range: 0.65...1.5, display: "\(Int(model.style.textScale * 100))%", defaultValue: defaults.textScale)
            Text("调整品牌、型号与参数，落款字号可在「水印信息」中单独设置").font(.system(size: 9)).foregroundStyle(muted)
            Toggle("浅色参数与型号", isOn: $model.style.whiteText).toggleStyle(.switch).controlSize(.small)
            Toggle("浅色品牌文字", isOn: $model.style.whiteBrand).toggleStyle(.switch).controlSize(.small)
            Button("恢复参考图样式") { model.resetStyle() }
                .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 11)).padding(.top, 4)
        }.font(.system(size: 11))
    }

    private var exportEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("导出设置", caption: "EXPORT")
            HStack { Text("图片格式"); Spacer(); Picker("图片格式", selection: $model.format) { ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 112) }
            HStack { Text("画布宽度"); Spacer(); Picker("画布宽度", selection: $model.exportSize) { ForEach(ExportSize.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 112) }
            HStack {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Text(model.dimensions).monospacedDigit()
                Spacer()
                Text("sRGB").font(.system(size: 9, weight: .medium))
            }.font(.system(size: 10)).foregroundStyle(muted)
            Text("原图尺寸保留主照片像素，另加画框。\n导出生成新文件，移除定位等原始 EXIF。").font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            if model.items.count > 1 {
                Text("在「批量选择」中勾选照片后导出；拍摄参数分别保存，重名文件自动编号。").font(.system(size: 9)).lineSpacing(3).foregroundStyle(muted)
            }
        }.font(.system(size: 11))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.lastExport == nil ? "circle.dotted" : "checkmark.circle.fill")
                .foregroundStyle(model.lastExport == nil ? muted : Color.green)
            Text(model.status).lineLimit(1)
            if model.lastExport != nil && !model.isExporting { Button("在 Finder 中查看") { model.revealExport() }.buttonStyle(.plain).foregroundStyle(accent) }
            Spacer()
            if model.isBatchExporting {
                ProgressView(value: Double(model.batchCompleted), total: Double(max(1, model.batchTotal))).frame(width: 110)
                Text("\(model.batchCompleted)/\(model.batchTotal)").monospacedDigit()
                Button("取消") { model.cancelBatch() }.controlSize(.small)
            } else { Text("⌘O 导入    ⇧⌘E 导出当前    ⌥⌘E 导出已选").foregroundStyle(muted) }
        }.font(.system(size: 10)).padding(.horizontal, 20).frame(height: 32)
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(caption).font(.system(size: 7, weight: .medium)).tracking(1).foregroundStyle(muted)
        }
    }
    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(muted)
            TextField(placeholder, text: text).textFieldStyle(.plain).font(.system(size: 12))
                .padding(.horizontal, 10).frame(height: 32).background(.white, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ink.opacity(0.12), lineWidth: 0.7))
        }
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String, defaultValue: Double) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(display).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                    .padding(.horizontal, 4).padding(.vertical, 2).contentShape(Rectangle())
                    .onTapGesture(count: 2) { value.wrappedValue = defaultValue }
                    .help("双击恢复默认值")
                    .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
                    .accessibilityLabel("\(title)数值").accessibilityValue(display)
                    .accessibilityIdentifier("reset-" + title)
                    .accessibilityAction(named: Text("恢复默认值")) { value.wrappedValue = defaultValue }
            }
            Slider(value: value, in: range).controlSize(.mini)
                .accessibilityLabel(title).accessibilityIdentifier("slider-" + title)
        }
    }
}

private struct PostagePaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = PostageLayout(imageWidth: 3, imageHeight: 2, outputWidth: 1000, style: FrameStyle())
        let transform = CGAffineTransform(translationX: -layout.cardRect.minX, y: -layout.cardRect.minY)
            .concatenating(CGAffineTransform(scaleX: rect.width / layout.cardRect.width, y: rect.height / layout.cardRect.height))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Path(layout.outline).applying(transform)
    }
}

private struct TicketPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = TicketLayout(imageWidth: 2, imageHeight: 3, outputWidth: 1000, style: FrameStyle())
        let transform = CGAffineTransform(translationX: -layout.cardRect.minX, y: -layout.cardRect.minY)
            .concatenating(CGAffineTransform(scaleX: rect.width / layout.cardRect.width, y: rect.height / layout.cardRect.height))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Path(layout.outline).applying(transform)
    }
}

private struct ClassicBrandPreview: View {
    let brand: CameraBrand
    let colored: Bool
    let fallback: String
    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
                brand.draw(in: cg, rect: CGRect(origin: .zero, size: size), color: colored, fallback: fallback)
            }
        }
    }
}
