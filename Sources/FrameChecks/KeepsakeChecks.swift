import AppKit
import FrameCore

func runKeepsakeChecks(root: URL, folder: URL, photo: PhotoDocument, demo: PhotoDocument,
                       portrait: PhotoDocument, renderer: FrameRenderer) throws {
    let expected: [(TemplateID, Int, Int, Int, Int, Int, Int)] = [
        (.cinema,902,1735,30,100,970,710), (.receipt,1097,1705,160,280,840,710), (.tornPaper,820,1470,130,130,870,600)
    ]
    for (id,height,portraitHeight,left,top,right,bottom) in expected {
        var s = FrameStyle(); s.template = id
        let l = FrameLayout(imageWidth:600,imageHeight:400,outputWidth:1000,style:s)
        check(l.height == height, "\(id.title) 横版尺寸符合独立预期")
        let pl = FrameLayout(imageWidth:400,imageHeight:600,outputWidth:1000,style:s)
        check(pl.height == portraitHeight && abs(pl.photoRect.width / pl.photoRect.height - 2.0/3) < 0.00001,
              "\(id.title) 竖版尺寸独立验证，完整保留原比例")
        let image = try renderer.render(photo:photo,metadata:photo.metadata,style:s,width:1000)
        check(sample(image,x:left,y:top) == [240,30,20] && sample(image,x:right,y:top) == [20,220,40]
            && sample(image,x:left,y:bottom) == [20,50,240] && sample(image,x:right,y:bottom) == [245,220,20],
            "\(id.title) 四角像素与方向正确，没有裁切或滤镜")
        let preview = try renderer.render(photo:photo,metadata:photo.metadata,style:s,width:1000,preview:true)
        check((image.dataProvider!.data! as Data) == (preview.dataProvider!.data! as Data), "\(id.title) 预览与导出一致")
        let ow = ExportSize.original.width(for:photo,style:s)
        let original = FrameLayout(imageWidth:600,imageHeight:400,outputWidth:ow,style:s)
        check(original.photoRect.width >= 600, "\(id.title) 原尺寸导出保留主照片像素")
        let long = String(repeating:"一段很长的字幕 Long caption · ",count:40)
        s.cinema.subtitle = long; s.cinema.translation = long; s.cinema.scene = long; s.cinema.textScale = 1.6
        s.receipt.title = long; s.receipt.place = long; s.receipt.note = long; s.receipt.number = long; s.receipt.textScale = 1.6
        s.tornPaper.caption = long; s.tornPaper.textScale = 1.6
        s.signature = long; s.signatureScale = 2
        let extended = try renderer.render(photo:photo,metadata:photo.metadata,style:s,width:1000)
        var intact = true
        for y in stride(from:top,through:bottom,by:23) { for x in stride(from:left,through:right,by:29) {
            if sample(image,x:x,y:y) != sample(extended,x:x,y:y) { intact = false }
        } }
        check(intact,"\(id.title) 长文案、最大字号与签名不越入照片")
        _ = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:64)
        check(true,"\(id.title) 最小画布和缺少元信息可渲染")
        let dir = folder.appendingPathComponent("keepsake-\(id.rawValue)")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let report = BatchExporter.run(jobs:[BatchJob(url:photo.url),BatchJob(url:portrait.url)],folder:dir,
            style:s,size:.standard,format:.png,control:BatchControl())
        check(report.succeeded == 2 && report.failed == 0,"\(id.title) 横竖照片批量输出成功")
        var clean = FrameStyle(); clean.template = id
        var metadata = PhotoMetadata(); metadata.captureDateTime = "2026:10:22 09:20:00"
        clean.signature = "Frame Studio"; clean.receipt.place = "A LITTLE WALK"
        for (source,suffix) in [(demo,"横版"),(portrait,"竖版")] {
            try ImageWriter.save(renderer.render(photo:source,metadata:metadata,style:clean,width:1400),
                to:root.appendingPathComponent("Examples/\(id.title)-\(suffix).jpg"),format:.jpeg)
        }
    }
    var s = FrameStyle(); s.template = .cinema
    let white = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:1000)
    s.cinema.ink = .amber; s.cinema.position = 0
    let amber = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:1000)
    check((white.dataProvider!.data! as Data) != (amber.dataProvider!.data! as Data)
        && sample(white,x:250,y:300) == sample(amber,x:250,y:300),"字幕颜色与上下位置改变幕边，不改变主图")
    s.template = .tornPaper; s.tornPaper.shadow = 0; s.tornPaper.roughness = 0.001
    let smooth = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:1000)
    s.tornPaper.shadow = 0.35; s.tornPaper.roughness = 0.008
    let torn = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:1000)
    check((smooth.dataProvider!.data! as Data) != (torn.dataProvider!.data! as Data)
        && sample(smooth,x:250,y:300) == sample(torn,x:250,y:300),"自然撕边与阴影实际改变纸面边缘，不触碰照片")
    for id in [TemplateID.receipt,.tornPaper] {
        s = FrameStyle(); s.template = id
        let noDate = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:600)
        s.receipt.dateMode = .none; s.tornPaper.dateMode = .none
        let hidden = try renderer.render(photo:photo,metadata:PhotoMetadata(),style:s,width:600)
        check((noDate.dataProvider!.data! as Data) == (hidden.dataProvider!.data! as Data),"\(id.title) 缺失日期留空，不补造时间")
    }
    s.cinema.subtitle = "留住今天"; s.cinema.bottom = 0.25; s.receipt.place = "山间"; s.receipt.margin = 0.16
    s.tornPaper.caption = "Memory"; s.tornPaper.shadow = 0.30
    let restored = try JSONDecoder().decode(FrameStyle.self,from:JSONEncoder().encode(s))
    check(restored == s,"三个新模板文案、配色、独立版式完整恢复")
    let legacy = try JSONDecoder().decode(FrameStyle.self,from:Data(#"{"template":"film35","film35":{"label":"FRAME 70"}}"#.utf8))
    check(legacy.film35.label == "FRAME 70" && legacy.cinema == CinemaStyle() && legacy.receipt == ReceiptStyle()
        && legacy.tornPaper == TornPaperStyle(),"旧会话保留自定义标签并补全三模板默认值")
    let bounded = try JSONDecoder().decode(FrameStyle.self,from:Data(#"{"cinema":{"bottom":99,"position":-1},"receipt":{"margin":9},"tornPaper":{"roughness":999}}"#.utf8))
    check(bounded.cinema.bottom == 0.30 && bounded.cinema.position == 0 && bounded.receipt.margin == 0.18
        && bounded.tornPaper.roughness == 0.008,"手改会话的极端布局值被安全限制")
    check(s.cinema.resetLayout().subtitle == "留住今天" && s.receipt.resetLayout().place == "山间"
        && s.tornPaper.resetLayout().caption == "Memory",
          "恢复版式保留文案与纸色")
    var tight = FrameStyle(); tight.template = .cinema; tight.cinema.bottom = 0.12
    tight.cinema.position = 1; tight.cinema.textScale = 1.6; tight.cinema.showSignature = true
    tight.cinema.subtitle = "Subtitle"; tight.cinema.translation = String(repeating: "M", count: 42)
    tight.signature = "SIGNATURE"; tight.signatureScale = 2
    let subtitled = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: tight, width: 1000)
    tight.cinema.subtitle = ""; tight.cinema.translation = ""
    let signatureOnly = try renderer.render(photo: photo, metadata: PhotoMetadata(), style: tight, width: 1000)
    var reserved = true
    for y in (subtitled.height - 28)..<(subtitled.height - 4) {
        for x in stride(from: 40, to: 970, by: 2) {
            if sample(subtitled, x: x, y: y) != sample(signatureOnly, x: x, y: y) { reserved = false }
        }
    }
    check(reserved, "Cinema 最低位置和最大字幕字号不进入底部落款保留区")
    let retired = try JSONDecoder().decode(FrameStyle.self, from: Data(#"{"template":"contactSheet","contactSheet":{"showFilenames":true},"film35":{"label":"FRAME 70"},"signature":"Keep"}"#.utf8))
    check(retired.template == .film35 && retired.film35.label == "FRAME 70" && retired.signature == "Keep"
        && !TemplateID.allCases.map(\.rawValue).contains("contactSheet"), "移除接触印样后旧会话安全切回胶片相框，保留自定义标签与落款")
}
