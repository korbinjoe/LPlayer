import AppKit
import CoreText

/// The wordmark has its own typeface; playback controls use the system font.
enum BrandTypography {
    private static let semiboldDescriptor: CTFontDescriptor? = {
        let bundled = Bundle.main.url(forResource: "Manrope", withExtension: "ttf", subdirectory: "Fonts")
        // `swift run` has no app resource bundle. Packaged apps only use their
        // own resources, including when a development checkout is available.
        let development = Bundle.main.bundleURL.pathExtension == "app" ? nil
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Fonts/Manrope.ttf")
        guard let url = bundled ?? development,
              FileManager.default.fileExists(atPath: url.path) else { return nil }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        // OpenType's `wght` axis is 600 for SemiBold. The unvaried font is
        // ExtraLight, so selecting the family name alone is insufficient.
        return CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: 0x77676874), 600)
    }()

    static func wordmarkFont(ofSize size: CGFloat) -> NSFont {
        guard let descriptor = semiboldDescriptor else {
            return .systemFont(ofSize: size, weight: .semibold)
        }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    static func applyWordmark(to field: NSTextField, size: CGFloat = 13) {
        let font = wordmarkFont(ofSize: size)
        field.font = font
        field.attributedStringValue = NSAttributedString(string: "LPlayer", attributes: [
            .font: font,
            .foregroundColor: field.textColor ?? .labelColor,
            .kern: -size * 0.035
        ])
    }
}
