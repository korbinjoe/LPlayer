import AppKit

/// A grouped help rail using the same live binding store as the editor. Each
/// action row is an independent accessibility element instead of one long label.
final class LPlayerShortcutHelpView: SettingsFlippedView {
    static let preferredWidth: CGFloat = 344
    var preferredHeight: CGFloat = 540
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var shortcuts: ShortcutStore? { didSet { refreshLocalization() } }
    var hand: HandLayout = .left { didSet { if hand != oldValue { refreshLocalization() } } }
    var overlaysVideo = false {
        didSet { if overlaysVideo != oldValue { updateBackdrop() } }
    }
    private let titleLabel = settingsLabel(size: 18, weight: .semibold)
    private let layoutLabel = settingsLabel(size: 11, color: SettingsPalette.secondary)
    private let closeButton = NSButton()
    private let settingsButton = NSButton()
    private let footerLabel = settingsLabel(size: 10, color: SettingsPalette.tertiary)
    private let scrollView = NSScrollView()
    private let document = SettingsFlippedView()
    private var groupViews: [(heading: NSTextField, content: ShortcutHelpGroupView)] = []
    private let gestureHeading = settingsLabel(size: 11, color: SettingsPalette.secondary, weight: .medium)
    private let gestureGuide = ShortcutGestureGuideView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = SettingsPalette.background.cgColor
        setAccessibilityElement(false)
        setAccessibilityRole(.group)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.contentTintColor = SettingsPalette.secondary
        closeButton.target = self
        closeButton.action = #selector(close)
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.font = .systemFont(ofSize: 11)
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        footerLabel.alignment = .center
        footerLabel.usesSingleLineMode = false
        footerLabel.maximumNumberOfLines = 2
        footerLabel.lineBreakMode = .byWordWrapping
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = document
        [titleLabel, layoutLabel, closeButton, scrollView, settingsButton, footerLabel].forEach(addSubview)
        refreshLocalization()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refreshLocalization() {
        titleLabel.stringValue = L10n.text("Keyboard Shortcuts", "快捷键")
        layoutLabel.stringValue = hand == .left ? L10n.text("Left-hand layout", "左手布局") : L10n.text("Right-hand layout", "右手布局")
        closeButton.setAccessibilityLabel(L10n.text("Close keyboard shortcuts", "收起快捷键提醒"))
        closeButton.toolTip = L10n.format("Press %@ or Esc to close", "按 %@ 或 Esc 收起", bindingText(.help))
        settingsButton.title = L10n.text("Customize Shortcuts…", "设置快捷键…")
        settingsButton.setAccessibilityLabel(L10n.text("Open keyboard shortcut settings", "打开快捷键设置"))
        footerLabel.stringValue = L10n.format("%@ / Esc closes\nPlayback shortcuts stay active", "%@ / Esc 收起\n可边看边操作", bindingText(.help))
        footerLabel.toolTip = L10n.text("This sidebar is a reference. Playback shortcuts remain active; scroll to see more shortcuts.", "此侧栏用于查看说明，播放快捷键仍然生效；滚动可查看更多快捷键。")
        setAccessibilityLabel(L10n.text("Keyboard shortcuts sidebar", "快捷键侧栏"))
        scrollView.setAccessibilityLabel(L10n.text("Shortcuts grouped by task", "按功能分组的快捷键"))
        document.subviews.forEach { $0.removeFromSuperview() }
        groupViews = makeGroups().map { title, rows in
            let heading = settingsLabel(title, size: 11, color: SettingsPalette.secondary, weight: .medium)
            let content = ShortcutHelpGroupView(rows: rows.map { title, actions in
                (title, actions.map(bindingText), actions.map(bindingDescription).joined(separator: " · "))
            })
            document.addSubview(heading)
            document.addSubview(content)
            return (heading, content)
        }
        gestureHeading.stringValue = L10n.text("Trackpad gestures", "触控板手势")
        gestureGuide.refreshLocalization()
        document.addSubview(gestureHeading)
        document.addSubview(gestureGuide)
        updateBackdrop()
        needsLayout = true
    }

    private func updateBackdrop() {
        layer?.backgroundColor = (overlaysVideo ? Palette.panel : SettingsPalette.background).cgColor
        let secondary = overlaysVideo ? Palette.overlaySecondary : SettingsPalette.secondary
        layoutLabel.textColor = secondary
        footerLabel.textColor = overlaysVideo ? Palette.overlaySecondary : SettingsPalette.tertiary
        gestureHeading.textColor = secondary
        groupViews.forEach { $0.heading.textColor = secondary }
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 21, y: 23, width: max(0, bounds.width - 66), height: 25)
        layoutLabel.frame = NSRect(x: 22, y: 55, width: max(0, bounds.width - 44), height: 17)
        closeButton.frame = NSRect(x: bounds.width - 43, y: 22, width: 25, height: 25)
        scrollView.frame = NSRect(x: 17, y: 91, width: max(0, bounds.width - 34), height: max(0, bounds.height - 189))
        let width = scrollView.contentSize.width
        var top: CGFloat = 1
        for group in groupViews {
            group.heading.frame = NSRect(x: 7, y: top, width: max(0, width - 14), height: 17)
            top += 24
            let height = group.content.preferredHeight(forWidth: width)
            group.content.frame = NSRect(x: 0, y: top, width: width, height: height)
            top += height + 21
        }
        gestureHeading.frame = NSRect(x: 7, y: top, width: max(0, width - 14), height: 17)
        top += 24
        let gestureHeight = gestureGuide.preferredHeight(forWidth: width)
        gestureGuide.frame = NSRect(x: 0, y: top, width: width, height: gestureHeight)
        document.frame = NSRect(x: 0, y: 0, width: width, height: top + gestureHeight + 12)
        settingsButton.frame = NSRect(x: 23, y: bounds.height - 83, width: max(0, bounds.width - 46), height: 29)
        footerLabel.frame = NSRect(x: 17, y: bounds.height - 44, width: max(0, bounds.width - 34), height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        SettingsPalette.line.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 21, y: 82, width: max(0, bounds.width - 42), height: 1).fill()
        NSRect(x: 21, y: bounds.height - 97, width: max(0, bounds.width - 42), height: 1).fill()
    }

    private func bindingText(_ action: ShortcutAction) -> String {
        // The active one-hand or customized primary stays visible. Shared
        // arrows and other fixed aliases remain in each row's full tooltip.
        if let shortcuts {
            return shortcuts.binding(for: action, hand: hand)?.display ?? shortcuts.aliases(for: action, hand: hand).first?.display ?? "—"
        }
        return ShortcutStore.defaultBinding(for: action, hand: hand)?.display ?? "—"
    }
    private func bindingDescription(_ action: ShortcutAction) -> String {
        var values = shortcuts?.aliases(for: action, hand: hand) ?? []
        if let primary = shortcuts?.binding(for: action, hand: hand) ?? (shortcuts == nil ? ShortcutStore.defaultBinding(for: action, hand: hand) : nil) { values.insert(primary, at: 0) }
        var seen = Set<KeyChord>()
        let text = values.filter { seen.insert($0).inserted }.map(\.display).joined(separator: " / ")
        return action.title + L10n.text(": ", "：") + (text.isEmpty ? L10n.text("Unassigned", "未设置") : text)
    }

    private typealias HelpItem = (title: String, actions: [ShortcutAction])
    private func makeGroups() -> [(String, [HelpItem])] {
        [
            (L10n.text("Playback & Seeking", "播放与跳转"), [
                (ShortcutAction.playPause.title, [.playPause]),
                (L10n.text("Back / Forward 5s", "后退 / 前进 5 秒"), [.seekBackward, .seekForward]),
                (L10n.text("Back / Forward 30s", "后退 / 前进 30 秒"), [.seekBackwardLarge, .seekForwardLarge]),
                (L10n.text("Previous / Next video", "上一个 / 下一个视频"), [.previousFile, .nextFile]),
                (ShortcutAction.undoSeek.title, [.undoSeek])
            ]),
            (L10n.text("Volume & Speed", "音量与速度"), [
                (L10n.text("Volume down / up", "减小 / 增大音量"), [.volumeDown, .volumeUp]),
                (ShortcutAction.mute.title, [.mute]),
                (L10n.text("Slower / Faster", "降低 / 提高速度"), [.speedDown, .speedUp]),
                (ShortcutAction.resetSpeed.title, [.resetSpeed])
            ]),
            (L10n.text("Picture & Subtitles", "画面与字幕"), [
                (L10n.text("Zoom out / in", "缩小 / 放大画面"), [.zoomOut, .zoomIn]),
                (ShortcutAction.resetZoom.title, [.resetZoom]),
                (ShortcutAction.fullscreen.title, [.fullscreen]),
                (ShortcutAction.subtitles.title, [.subtitles]),
                (L10n.text("Subtitles earlier / later", "字幕提前 / 延后"), [.subtitleEarlier, .subtitleLater]),
                (ShortcutAction.cycleAudioTrack.title, [.cycleAudioTrack]),
                (ShortcutAction.cycleSubtitleTrack.title, [.cycleSubtitleTrack])
            ]),
            (L10n.text("Files & Panels", "文件与面板"), [
                (ShortcutAction.openFiles.title, [.openFiles]),
                (ShortcutAction.playlist.title, [.playlist]),
                (ShortcutAction.panel.title, [.panel]),
                (ShortcutAction.help.title, [.help]),
                (ShortcutAction.privatePlayback.title, [.privatePlayback]),
                (ShortcutAction.customizeShortcuts.title, [.customizeShortcuts])
            ])
        ]
    }
    @objc private func close() { onClose?() }
    @objc private func openSettings() { onOpenSettings?() }
}

private final class ShortcutHelpGroupView: SettingsFlippedView {
    private var rows: [ShortcutHelpItemView] = []
    init(rows values: [(String, [String], String)]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = SettingsPalette.group.cgColor
        layer?.borderColor = SettingsPalette.line.cgColor
        layer?.borderWidth = 1
        rows = values.map { title, keys, help in ShortcutHelpItemView(title: title, keys: keys, help: help) }
        rows.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        rows.reduce(0) { $0 + $1.preferredHeight(forWidth: width) }
    }
    override func layout() {
        super.layout()
        var top: CGFloat = 0
        for row in rows {
            let height = row.preferredHeight(forWidth: bounds.width)
            row.frame = NSRect(x: 0, y: top, width: bounds.width, height: height)
            top += height
        }
    }
}

private final class ShortcutHelpItemView: SettingsFlippedView {
    private let titleLabel: NSTextField
    private let keysLabel: NSTextField
    private let keyBackground = SettingsSurfaceView()
    private let keys: [String]
    private let naturalKeyWidth: CGFloat
    private let naturalTitleWidth: CGFloat
    init(title: String, keys: [String], help: String) {
        let titleField = settingsLabel(title, size: 12)
        let keysField = settingsLabel(keys.joined(separator: " / "), size: 11, color: SettingsPalette.text, weight: .medium)
        titleLabel = titleField
        keysLabel = keysField
        self.keys = keys
        // NSTextField's cell includes text insets that a bare string omits.
        naturalKeyWidth = ceil(keysField.cell?.cellSize.width ?? keysField.intrinsicContentSize.width)
        naturalTitleWidth = ceil(titleField.cell?.cellSize.width ?? titleField.intrinsicContentSize.width)
        super.init(frame: .zero)
        keysLabel.alignment = .center
        keysLabel.usesSingleLineMode = false
        keysLabel.maximumNumberOfLines = 0
        keysLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.usesSingleLineMode = false
        titleLabel.lineBreakMode = .byWordWrapping
        keyBackground.cornerRadius = 5
        keyBackground.fillColor = NSColor(srgbRed: 0.282, green: 0.282, blue: 0.306, alpha: 1)
        keyBackground.addSubview(keysLabel)
        addSubview(titleLabel)
        addSubview(keyBackground)
        toolTip = help
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(help)
        titleLabel.setAccessibilityElement(false)
        keysLabel.setAccessibilityElement(false)
        keyBackground.setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    private func usesStackedLayout(forWidth width: CGFloat) -> Bool {
        naturalKeyWidth + 14 > 148 || naturalTitleWidth + max(25, naturalKeyWidth + 14) + 31 > width
    }
    private func keyText(forWidth width: CGFloat) -> String {
        naturalKeyWidth + 14 > max(1, width - 22) ? keys.joined(separator: "\n") : keys.joined(separator: " / ")
    }
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard usesStackedLayout(forWidth: width) else { return 37 }
        let titleHeight = helpTextHeight(titleLabel.stringValue, font: titleLabel.font!, width: max(1, width - 22))
        let keyHeight = helpTextHeight(keyText(forWidth: width), font: keysLabel.font!, width: max(1, width - 32))
        return 8 + max(18, titleHeight) + 5 + max(22, keyHeight + 6) + 8
    }
    override func layout() {
        super.layout()
        if usesStackedLayout(forWidth: bounds.width) {
            let titleHeight = max(18, helpTextHeight(titleLabel.stringValue, font: titleLabel.font!, width: max(1, bounds.width - 22)))
            titleLabel.frame = NSRect(x: 11, y: 8, width: max(0, bounds.width - 22), height: titleHeight)
            keysLabel.stringValue = keyText(forWidth: bounds.width)
            let keyHeight = max(22, helpTextHeight(keysLabel.stringValue, font: keysLabel.font!, width: max(1, bounds.width - 32)) + 6)
            keyBackground.frame = NSRect(x: 11, y: titleLabel.frame.maxY + 5, width: max(0, bounds.width - 22), height: keyHeight)
            keysLabel.frame = NSRect(x: 5, y: 3, width: max(0, keyBackground.bounds.width - 10), height: keyHeight - 6)
        } else {
            keysLabel.stringValue = keys.joined(separator: " / ")
            let width = max(25, naturalKeyWidth + 14)
            keyBackground.frame = NSRect(x: max(0, bounds.width - width - 10), y: 8, width: width, height: 22)
            keysLabel.frame = NSRect(x: 5, y: 3, width: width - 10, height: 16)
            titleLabel.frame = NSRect(x: 11, y: 10, width: max(0, bounds.width - width - 31), height: 18)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        SettingsPalette.line.setFill()
        NSRect(x: 11, y: bounds.height - 1, width: max(0, bounds.width - 11), height: 1).fill()
    }
}

private final class ShortcutGestureGuideView: SettingsFlippedView {
    private let instructions = (0..<3).map { _ in settingsLabel(size: 11, color: SettingsPalette.secondary) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = SettingsPalette.group.cgColor
        layer?.borderColor = SettingsPalette.line.cgColor
        layer?.borderWidth = 1
        for field in instructions {
            field.usesSingleLineMode = false
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            addSubview(field)
        }
        setAccessibilityElement(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    func refreshLocalization() {
        let text = [
            L10n.text("Pinch to zoom the picture.", "双指捏合缩放画面。"),
            L10n.text("Double-tap with two fingers to zoom or fit.", "双指双击放大或恢复适应窗口。"),
            L10n.text("When zoomed, slide two fingers without clicking. Lift to stop.", "放大后无需按下触控板，双指滑动移动画面，松手即停。")
        ]
        for (field, value) in zip(instructions, text) { field.stringValue = value }
        needsLayout = true
    }
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        20 + instructions.reduce(0) { $0 + max(17, helpTextHeight($1.stringValue, font: $1.font!, width: max(1, width - 22))) } + 14
    }
    override func layout() {
        super.layout()
        var top: CGFloat = 10
        for field in instructions {
            let height = max(17, helpTextHeight(field.stringValue, font: field.font!, width: max(1, bounds.width - 22)))
            field.frame = NSRect(x: 11, y: top, width: max(0, bounds.width - 22), height: height)
            top += height + 7
        }
    }
}

private func helpTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    return ceil((text as NSString).boundingRect(with: NSSize(width: max(1, width - 4), height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading],
                                               attributes: [.font: font, .paragraphStyle: paragraph]).height) + 2
}
