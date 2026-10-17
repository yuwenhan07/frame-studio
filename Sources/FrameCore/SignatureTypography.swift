import AppKit

public enum SignatureTypography {
    public static let defaultFontFamily = "Microsoft YaHei"

    public static func isAvailable(_ family: String) -> Bool {
        NSFont(name: family, size: 12) != nil
    }

    private static func font(_ family: String, size: CGFloat, chinese: Bool) -> NSFont {
        NSFont(name: family, size: size)
            ?? NSFont(name: chinese ? "PingFang SC" : "Helvetica Neue", size: size)
            ?? .systemFont(ofSize: size)
    }

    public static func attributedString(_ text: String, size: CGFloat, chineseFamily: String,
                                        englishFamily: String, color: NSColor) -> NSAttributedString {
        let chinese = font(chineseFamily, size: size, chinese: true)
        let english = font(englishFamily, size: size, chinese: false)
        let result = NSMutableAttributedString(string: text, attributes: [.font: english, .foregroundColor: color])
        var offset = 0
        // Work in grapheme clusters, then convert to UTF-16 for attributed-string ranges.
        // This keeps emoji sequences, variation selectors and combining accents intact.
        for character in text {
            let length = String(character).utf16.count
            if character.unicodeScalars.contains(where: { isChineseScalar($0.value) }) {
                result.addAttribute(.font, value: chinese, range: NSRange(location: offset, length: length))
            }
            offset += length
        }
        return result
    }

    private static func isChineseScalar(_ value: UInt32) -> Bool {
        switch value {
        case 0x2E80...0x2FFF, 0x3000...0x303F, 0x31C0...0x31EF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0xFE10...0xFE1F, 0xFE30...0xFE4F, 0xFF01...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x2FA1F, 0x30000...0x3347F:
            return true
        default:
            return false
        }
    }
}
