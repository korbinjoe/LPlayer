import AppKit

/// These preferences are backed by existing player capabilities. The owning app
/// supplies callbacks so changes update playback and menus immediately.
final class SettingsGeneralPane: SettingsFlippedView {
    var onHandChange: ((HandLayout) -> Void)?
    var onLanguageChange: ((AppLanguage) -> Void)?
    var onPanSensitivityChange: ((Double) -> Void)?
    var onOpenShortcuts: (() -> Void)?
    private let heading = settingsLabel(size: 20, weight: .semibold)
    private let subtitle = settingsLabel(size: 12, color: SettingsPalette.secondary)
    private let operationHeading = settingsLabel(size: 11, color: SettingsPalette.secondary, weight: .medium)
    private let operationGroup = SettingsSurfaceView()
    private let handLabel = settingsLabel()
    private let handControl = NSSegmentedControl()
    private let languageLabel = settingsLabel()
    private let languageControl = NSPopUpButton()
    private let operationNote = settingsLabel(size: 11, color: SettingsPalette.tertiary)
    private let gestureHeading = settingsLabel(size: 11, color: SettingsPalette.secondary, weight: .medium)
    private let gestureGroup = SettingsSurfaceView()
    private let sensitivityLabel = settingsLabel()
    private let sensitivityDescription = settingsLabel(size: 11, color: SettingsPalette.secondary)
    private let sensitivitySlider = NSSlider(value: 1, minValue: 0.25, maxValue: 1.5, target: nil, action: nil)
    private let sensitivityValue = settingsLabel(size: 11, color: SettingsPalette.secondary)
    private let shortcutsButton = NSButton()
    private let shortcutsIcon = NSImageView()
    private let shortcutsLabel = settingsLabel(size: 11, color: SettingsPalette.secondary)
    var hand: HandLayout = .left { didSet { handControl.selectedSegment = hand == .left ? 0 : 1 } }
    var sensitivity: Double = 1 {
        didSet {
            sensitivitySlider.doubleValue = min(1.5, max(0.25, sensitivity))
            sensitivityValue.stringValue = String(format: "%.0f%%", sensitivitySlider.doubleValue * 100)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        operationGroup.separatorOffsets = [54]
        handControl.segmentCount = 2
        handControl.trackingMode = .selectOne
        handControl.segmentStyle = .rounded
        handControl.controlSize = .small
        handControl.target = self
        handControl.action = #selector(changeHand)
        languageControl.controlSize = .small
        languageControl.target = self
        languageControl.action = #selector(changeLanguage)
        sensitivitySlider.numberOfTickMarks = 6
        sensitivitySlider.allowsTickMarkValuesOnly = true
        sensitivitySlider.isContinuous = true
        sensitivitySlider.controlSize = .small
        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(changeSensitivity)
        sensitivityValue.alignment = .right
        shortcutsButton.isBordered = false
        shortcutsButton.font = .systemFont(ofSize: 11)
        shortcutsButton.contentTintColor = SettingsPalette.accent
        shortcutsButton.target = self
        shortcutsButton.action = #selector(openShortcuts)
        shortcutsIcon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcutsIcon.contentTintColor = SettingsPalette.tertiary
        [heading, subtitle, operationHeading, operationGroup, operationNote, gestureHeading, gestureGroup, shortcutsIcon, shortcutsLabel, shortcutsButton].forEach(addSubview)
        [handLabel, handControl, languageLabel, languageControl].forEach(operationGroup.addSubview)
        [sensitivityLabel, sensitivityDescription, sensitivitySlider, sensitivityValue].forEach(gestureGroup.addSubview)
        refreshLocalization()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refreshLocalization() {
        heading.stringValue = L10n.text("General", "通用")
        subtitle.stringValue = L10n.text("Make the player feel like your own.", "让播放器更合你的习惯。")
        operationHeading.stringValue = L10n.text("Language & Controls", "语言与操作")
        handLabel.stringValue = L10n.text("One-hand layout", "单手布局")
        handControl.setLabel(HandLayout.left.title, forSegment: 0)
        handControl.setLabel(HandLayout.right.title, forSegment: 1)
        handControl.selectedSegment = hand == .left ? 0 : 1
        handControl.setAccessibilityLabel(handLabel.stringValue)
        languageLabel.stringValue = L10n.text("Interface language", "界面语言")
        languageControl.removeAllItems()
        languageControl.addItems(withTitles: AppLanguage.allCases.map(\.nativeName))
        languageControl.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
        languageControl.setAccessibilityLabel(languageLabel.stringValue)
        operationNote.stringValue = L10n.text("Shortcuts follow your hand layout. Playback shortcuts can be customized in Keyboard.", "单手快捷键随布局切换，可在快捷键中自定义播放与暂停按键。")
        operationNote.toolTip = operationNote.stringValue
        gestureHeading.stringValue = L10n.text("Trackpad", "触控板")
        sensitivityLabel.stringValue = L10n.text("Pan sensitivity", "画面拖动灵敏度")
        sensitivityDescription.stringValue = L10n.text("How far the zoomed picture follows your fingers", "调整放大画面跟随双指移动的幅度")
        sensitivityDescription.toolTip = sensitivityDescription.stringValue
        sensitivitySlider.setAccessibilityLabel(sensitivityLabel.stringValue)
        sensitivitySlider.setAccessibilityValueDescription(L10n.format("%.0f percent", "百分之 %.0f", sensitivity * 100))
        shortcutsLabel.stringValue = L10n.text("See the shortcuts for your layout", "查看当前布局的快捷键")
        shortcutsButton.title = L10n.text("View ›", "查看 ›")
        shortcutsButton.setAccessibilityLabel(L10n.text("Open keyboard shortcut settings", "打开快捷键设置"))
        sensitivityValue.stringValue = String(format: "%.0f%%", sensitivity * 100)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 56)
        heading.frame = NSRect(x: 28, y: 30, width: width - 24, height: 26)
        subtitle.frame = NSRect(x: 28, y: 62, width: width, height: 19)
        operationHeading.frame = NSRect(x: 38, y: 107, width: width - 20, height: 16)
        operationGroup.frame = NSRect(x: 28, y: 130, width: width, height: 108)
        handLabel.frame = NSRect(x: 14, y: 18, width: max(0, width - 186), height: 19)
        handControl.frame = NSRect(x: max(132, width - 158), y: 13, width: 144, height: 28)
        languageLabel.frame = NSRect(x: 14, y: 71, width: max(0, width - 186), height: 19)
        languageControl.frame = NSRect(x: max(132, width - 158), y: 66, width: 144, height: 28)
        operationNote.frame = NSRect(x: 38, y: 248, width: width - 20, height: 20)
        gestureHeading.frame = NSRect(x: 38, y: 294, width: width - 20, height: 16)
        gestureGroup.frame = NSRect(x: 28, y: 317, width: width, height: 72)
        let controlWidth: CGFloat = min(144, max(100, width * 0.30))
        sensitivityLabel.frame = NSRect(x: 14, y: 13, width: max(0, width - controlWidth - 86), height: 19)
        sensitivityDescription.frame = NSRect(x: 14, y: 36, width: max(0, width - controlWidth - 86), height: 18)
        sensitivitySlider.frame = NSRect(x: width - controlWidth - 68, y: 23, width: controlWidth, height: 24)
        sensitivityValue.frame = NSRect(x: width - 60, y: 26, width: 48, height: 17)
        shortcutsIcon.frame = NSRect(x: 31, y: 421, width: 17, height: 17)
        shortcutsLabel.frame = NSRect(x: 56, y: 420, width: max(0, width - 95), height: 20)
        shortcutsButton.frame = NSRect(x: bounds.width - 83, y: 417, width: 58, height: 26)
    }

    @objc private func changeHand() { onHandChange?(handControl.selectedSegment == 0 ? .left : .right) }
    @objc private func changeLanguage() {
        guard AppLanguage.allCases.indices.contains(languageControl.indexOfSelectedItem) else { return }
        onLanguageChange?(AppLanguage.allCases[languageControl.indexOfSelectedItem])
    }
    @objc private func changeSensitivity() {
        sensitivity = sensitivitySlider.doubleValue
        sensitivitySlider.setAccessibilityValueDescription(L10n.format("%.0f percent", "百分之 %.0f", sensitivity * 100))
        onPanSensitivityChange?(sensitivity)
    }
    @objc private func openShortcuts() { onOpenShortcuts?() }
}
