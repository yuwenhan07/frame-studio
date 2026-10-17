import AppKit
import SwiftUI
import FrameCore

struct SignatureFontPicker: View {
    let title: String
    @Binding var selection: String
    let chinese: Bool

    private static let installed = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") && SignatureTypography.isAvailable($0) }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    private var families: [String] {
        let preferred = chinese
            ? [SignatureTypography.defaultFontFamily, "PingFang SC", "Songti SC", "Kaiti SC", "Heiti SC", "Hiragino Sans GB"]
            : [SignatureTypography.defaultFontFamily, "Arial", "Helvetica Neue", "Times New Roman", "Georgia", "Courier New", "Avenir Next"]
        let first = preferred.filter { Self.installed.contains($0) || $0 == selection }
        return first + Self.installed.filter { !first.contains($0) }
            + (Self.installed.contains(selection) || first.contains(selection) ? [] : [selection])
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker(title, selection: $selection) {
                ForEach(families, id: \.self) { family in
                    Text(family == SignatureTypography.defaultFontFamily ? "微软雅黑" : family)
                        .tag(family)
                }
            }.labelsHidden().pickerStyle(.menu).controlSize(.small).frame(width: 170)
                .accessibilityIdentifier(chinese ? "signature-chinese-font" : "signature-english-font")
        }
    }
}
