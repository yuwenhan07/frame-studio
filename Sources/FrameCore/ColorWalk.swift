import AppKit

public enum ColorWalkBackground: String, CaseIterable, Codable, Identifiable, Sendable {
    case solid = "纯色色面", horizontalStripes = "横向主色条纹"
    public var id: String { rawValue }
}

public enum ColorWalkDetail: String, CaseIterable, Codable, Identifiable, Sendable {
    case captureTime = "拍摄时间", captureDate = "拍摄日期", custom = "自定义文字", none = "不显示"
    public var id: String { rawValue }

    public func text(metadata: PhotoMetadata, custom: String) -> String {
        if self == .custom { return custom.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard self != .none, let raw = metadata.captureDateTime else { return "" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.isLenient = false
        guard let date = parser.date(from: raw) else { return "" }
        // Preserve the camera's wall-clock time; its time zone is often absent.
        parser.dateFormat = self == .captureTime ? "h:mm a" : "MMM d, yyyy"
        return self == .captureDate ? parser.string(from: date).uppercased() : parser.string(from: date)
    }
}

public enum ColorWalkInk: String, CaseIterable, Codable, Identifiable, Sendable {
    case white = "白色", black = "黑色", automatic = "自动对比"
    public var id: String { rawValue }
    public func color(on background: PaletteColor) -> NSColor {
        if self == .white { return .white }
        if self == .black { return .black }
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(background.red) + 0.7152 * linear(background.green) + 0.0722 * linear(background.blue)
        return luminance > 0.179 ? .black : .white
    }
}

extension PhotoPalette {
    /// Gently lift automatic backgrounds, with a small lightness cap and a slight
    /// saturation reduction for a restrained, matte tone. Preserve the source hue.
    /// Manual overrides and the original photograph bypass this adjustment.
    public func colorWalkColor() -> PaletteColor {
        let original = representativeColorWalkColor()
        let channels = [Double(original.red), Double(original.green), Double(original.blue)].map { $0 / 255 }
        let minimum = channels.min()!, maximum = channels.max()!
        let lightness = (minimum + maximum) / 2
        let lifted = lightness + min(0.035, (1 - lightness) * 0.07)
        let spread = maximum - minimum
        let saturation = spread > 0 ? spread / (1 - abs(2 * lightness - 1)) : 0
        let newSpread = (1 - abs(2 * lifted - 1)) * saturation * 0.90
        let newMinimum = lifted - newSpread / 2
        let result = channels.map { channel -> UInt8 in
            let value = spread > 0 ? newMinimum + (channel - minimum) / spread * newSpread : lifted
            return UInt8(min(255, max(0, (value * 255).rounded())))
        }
        return PaletteColor(red: result[0], green: result[1], blue: result[2], fraction: original.fraction)
    }

    /// Select a substantial chromatic family, so large black shadows or white sky
    /// do not hide the photo's color mood. Neutral photographs stay neutral.
    private func representativeColorWalkColor() -> PaletteColor {
        let candidates = colors(count: 8, order: .dominance)
        guard let dominant = candidates.first else { return PaletteColor(hex: "#808080")! }
        struct Tone {
            let color: PaletteColor
            let hue: Double
            let saturation: Double
            let brightness: Double
        }
        let tones = candidates.map { color -> Tone in
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return Tone(color: color, hue: Double(h), saturation: Double(s), brightness: Double(b))
        }
        let chromatic = tones.filter { $0.saturation >= 0.12 && $0.brightness >= 0.18 && $0.color.lightness < 242 }
        guard chromatic.reduce(0, { $0 + $1.color.fraction }) >= 0.15 else { return dominant }
        func hueDistance(_ a: Double, _ b: Double) -> Double { min(abs(a - b), 1 - abs(a - b)) }
        func family(for tone: Tone) -> [Tone] { chromatic.filter { hueDistance($0.hue, tone.hue) <= 0.10 } }
        func score(_ tone: Tone) -> Double {
            family(for: tone).reduce(0) { $0 + $1.color.fraction * (0.6 + 0.4 * $1.saturation) }
        }
        let chosen = chromatic.max {
            let a = score($0), b = score($1)
            return a == b ? $0.color.fraction < $1.color.fraction : a < b
        }!
        let group = family(for: chosen)
        let total = group.reduce(0) { $0 + $1.color.fraction }
        func channel(_ key: KeyPath<PaletteColor, UInt8>) -> UInt8 {
            UInt8(min(255, max(0, (group.reduce(0) { $0 + Double($1.color[keyPath: key]) * $1.color.fraction } / total).rounded())))
        }
        return PaletteColor(red: channel(\.red), green: channel(\.green), blue: channel(\.blue), fraction: total)
    }
}
