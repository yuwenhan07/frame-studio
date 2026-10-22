import SwiftUI
import FrameCore

struct PrintTemplateThumbnail: View {
    let template: TemplateID
    let style: FrameStyle
    let photo: CGImage?
    @ViewBuilder private func image(width: CGFloat, height: CGFloat) -> some View {
        if let photo { Image(decorative: photo, scale: 1).resizable().scaledToFill().frame(width: width, height: height).clipped() }
        else { Rectangle().fill(Color(red: 0.64, green: 0.68, blue: 0.63)).frame(width: width, height: height) }
    }
    var body: some View {
        ZStack {
            switch template {
            case .film35:
                Color(white: 0.09)
                image(width: 41, height: 32)
                VStack {
                    if style.film35.showSprockets {
                        HStack(spacing: 3) { ForEach(0..<6) { _ in RoundedRectangle(cornerRadius: 0.5).fill(.white.opacity(0.8)).frame(width: 3, height: 1.5) } }
                    }
                    Spacer()
                    Text("\(style.film35.label)    \(style.film35.number)").lineLimit(1).minimumScaleFactor(0.5).font(.system(size: 3, design: .monospaced)).foregroundStyle(Color(red: 0.82, green: 0.64, blue: 0.39))
                }.padding(.vertical, 3)
            case .gallery:
                Color(nsColor: style.gallery.paper.color)
                image(width: 32, height: 28).offset(y: -3)
                if style.gallery.showOutline {
                    Rectangle().stroke(Color(nsColor: style.gallery.paper.ink).opacity(0.3), lineWidth: 0.4).frame(width: 34, height: 30).offset(y: -3)
                }
                Text("GALLERY").font(.system(size: 3, design: .serif)).foregroundStyle(Color(nsColor: style.gallery.paper.ink)).offset(y: 19)
            case .editorial:
                Color(nsColor: style.editorial.paper.color)
                Text("WANDER").font(.system(size: 7, design: .serif)).foregroundStyle(Color(nsColor: style.editorial.paper.ink)).offset(y: -18)
                image(width: 42, height: 28).offset(y: 3)
                if style.editorial.showAccent {
                    Rectangle().fill(Color(red: 0.57, green: 0.42, blue: 0.32)).frame(width: 42, height: 0.6).offset(y: -12)
                }
            case .instant:
                Color(red: 0.92, green: 0.91, blue: 0.88)
                Rectangle().fill(Color(nsColor: style.instant.paper.color)).frame(width: 39, height: 43).shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                image(width: 33, height: 28).offset(y: -4)
                Text("a moment.").font(.system(size: 4, design: .serif)).foregroundStyle(Color(nsColor: style.instant.paper.ink)).offset(y: 16)
            case .cinema:
                Color(white: 0.08)
                image(width: 48, height: 28).offset(y: -3)
                Text("A QUIET SCENE").font(.system(size: 3)).foregroundStyle(Color(nsColor: style.cinema.ink.color)).offset(y: 17)
            case .receipt:
                Color(red: 0.86, green: 0.85, blue: 0.82)
                Rectangle().fill(Color(nsColor: style.receipt.paper.color)).frame(width: 32, height: 46)
                Text("MEMORY").font(.system(size: 4, design: .monospaced)).foregroundStyle(Color(nsColor: style.receipt.paper.ink)).offset(y: -18)
                image(width: 27, height: 22).offset(y: -1)
                Text("—  001  —").font(.system(size: 3, design: .monospaced)).foregroundStyle(Color(nsColor: style.receipt.paper.ink)).offset(y: 17)
            case .tornPaper:
                Color(red: 0.42, green: 0.40, blue: 0.36)
                TornThumbnailShape().fill(Color(nsColor: style.tornPaper.paper.color)).frame(width: 40, height: 43)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                image(width: 36, height: style.tornPaper.showCaptionArea ? 28 : 38)
                    .clipShape(TornThumbnailShape()).offset(y: style.tornPaper.showCaptionArea ? -3 : 0)
                if style.tornPaper.showCaptionArea {
                    Text("a quiet moment").font(.system(size: 3, design: .serif)).foregroundStyle(Color(nsColor: style.tornPaper.paper.ink)).offset(y: 16)
                }
            default: EmptyView()
            }
        }.frame(width: 48, height: 50).clipped()
    }
}

private struct TornThumbnailShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(PaperEdge.torn(rect: rect, depth: 1.5, step: 0.6))
    }
}
