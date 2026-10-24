import AppKit

/// Solid cards and controls stay readable above the translucent sheet backdrop.
enum SettingsPalette {
    static let background = NSColor(srgbRed: 0.149, green: 0.149, blue: 0.161, alpha: 1)
    static let sidebar = NSColor(srgbRed: 0.125, green: 0.125, blue: 0.137, alpha: 1)
    static let group = NSColor(srgbRed: 0.188, green: 0.188, blue: 0.204, alpha: 1)
    static let line = NSColor.white.withAlphaComponent(0.075)
    static let text = NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    static let secondary = NSColor(srgbRed: 0.651, green: 0.651, blue: 0.686, alpha: 1)
    static let tertiary = NSColor(srgbRed: 0.467, green: 0.467, blue: 0.502, alpha: 1)
    static let accent = NSColor(srgbRed: 0.039, green: 0.518, blue: 1, alpha: 1)
}

/// Settings labels deliberately omit the shadow used by labels over video.
func settingsLabel(_ text: String = "", size: CGFloat = 13, color: NSColor = SettingsPalette.text,
                   weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsSurfaceView: SettingsFlippedView {
    var fillColor = SettingsPalette.group { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 9 { didSet { needsDisplay = true } }
    var drawsBorder = true { didSet { needsDisplay = true } }
    var separatorOffsets: [CGFloat] = [] { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        SettingsPalette.line.setFill()
        for offset in separatorOffsets { NSRect(x: 14, y: offset, width: max(0, bounds.width - 14), height: 1).fill() }
        if drawsBorder {
            SettingsPalette.line.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
            path.lineWidth = 1
            path.stroke()
        }
    }
}

final class SettingsSidebarButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    var symbolName = "gearshape" { didSet { imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) } }
    var symbolColor = NSColor.systemGray
    private let imageView = NSImageView()
    private let nameLabel = settingsLabel()

    init(title: String, symbol: String, color: NSColor) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .exterior
        symbolName = symbol
        symbolColor = color
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)
        addSubview(nameLabel)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 13, y: 10, width: 15, height: 15)
        nameLabel.frame = NSRect(x: 39, y: 9, width: max(0, bounds.width - 47), height: 19)
    }
    override func draw(_ dirtyRect: NSRect) {
        if selected {
            SettingsPalette.accent.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        } else if isHighlighted {
            NSColor.white.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        (selected ? NSColor.white.withAlphaComponent(0.18) : symbolColor).setFill()
        NSBezierPath(roundedRect: NSRect(x: 9, y: 6, width: 23, height: 23), xRadius: 5, yRadius: 5).fill()
        nameLabel.stringValue = title
        nameLabel.font = .systemFont(ofSize: 13, weight: selected ? .medium : .regular)
        nameLabel.textColor = SettingsPalette.text
    }
}

/// A consistent primary action even when a borderless sheet is not rendered as
/// a native titled window. NSButton retains keyboard and accessibility behavior.
final class SettingsPrimaryButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        font = .systemFont(ofSize: 12, weight: .medium)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (isEnabled ? SettingsPalette.accent : NSColor.white.withAlphaComponent(0.12)).setFill()
        shape.fill()
        if isHighlighted {
            NSColor.white.withAlphaComponent(0.13).setFill()
            shape.fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isEnabled ? NSColor.white : SettingsPalette.secondary
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

struct ShortcutPresentationGroup {
    let title: String
    let actions: [ShortcutAction]

    static var all: [ShortcutPresentationGroup] {
        [
            .init(title: L10n.text("Playback & Seeking", "播放与跳转"), actions: [.playPause, .seekBackward, .seekForward, .seekBackwardLarge, .seekForwardLarge, .undoSeek, .previousFile, .nextFile]),
            .init(title: L10n.text("Volume & Speed", "音量与速度"), actions: [.volumeDown, .volumeUp, .mute, .speedDown, .speedUp, .resetSpeed]),
            .init(title: L10n.text("Picture & Subtitles", "画面与字幕"), actions: [.zoomOut, .zoomIn, .resetZoom, .fullscreen, .subtitles, .subtitleEarlier, .subtitleLater, .cycleAudioTrack, .cycleSubtitleTrack]),
            .init(title: L10n.text("Files & Panels", "文件与面板"), actions: [.openFiles, .playlist, .panel, .help, .privatePlayback, .customizeShortcuts])
        ]
    }
}
