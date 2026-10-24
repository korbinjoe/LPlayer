import AppKit

extension KeyChord {
    private static let physicalKeys: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
            12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o",
            32: "u", 33: "[", 34: "i", 35: "p", 36: "\r", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 48: "\t", 49: " ", 50: "`", 51: "\u{7f}",
            53: "\u{1b}", 65: ".", 67: "*", 69: "+", 71: "\u{f739}", 75: "/", 76: "\u{3}", 78: "-",
            81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
            96: "\u{f708}", 97: "\u{f709}", 98: "\u{f70a}", 99: "\u{f706}", 100: "\u{f70b}", 101: "\u{f70c}",
            103: "\u{f70e}", 105: "\u{f710}", 106: "\u{f713}", 107: "\u{f711}", 109: "\u{f70d}", 111: "\u{f70f}",
            113: "\u{f712}", 114: "\u{f727}", 115: "\u{f729}", 116: "\u{f72c}", 117: "\u{f728}",
            118: "\u{f707}", 119: "\u{f72b}", 120: "\u{f705}", 121: "\u{f72d}", 122: "\u{f704}",
            123: "\u{f702}", 124: "\u{f703}", 125: "\u{f701}", 126: "\u{f700}", 64: "\u{f714}", 79: "\u{f715}", 80: "\u{f716}"
        ]

    /// Respect printable keyboard layouts, falling back to the physical ANSI
    /// position when an input method produces non-Latin or composition text.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        var modifiers: ShortcutModifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }

        let key: String
        if let characters = event.charactersIgnoringModifiers, characters.unicodeScalars.count == 1,
           let scalar = characters.unicodeScalars.first,
           (scalar.value < 0x80 || (0xf700...0xf747).contains(scalar.value)) {
            key = characters
        } else if let physical = Self.physicalKeys[event.keyCode] {
            key = physical
        } else {
            return nil
        }
        self.init(key, modifiers: modifiers)
    }
}

/// A native settings sheet that also owns shortcut recording. Existing callers
/// can continue opening the shortcut section through `present(asSheetFor:)`.
final class ShortcutEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    enum Section: Int, CaseIterable { case general, shortcuts, about }
    var onHandChange: ((HandLayout) -> Void)?
    var onLanguageChange: ((AppLanguage) -> Void)?
    var onPanSensitivityChange: ((Double) -> Void)?
    var onClose: (() -> Void)?
    var panSensitivity: Double {
        didSet { generalPane.sensitivity = min(1.5, max(0.25, panSensitivity)) }
    }
    private let store: ShortcutStore
    private var hand: HandLayout
    private var section: Section = .shortcuts
    private var sheet: ShortcutCapturePanel?
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let profileControl = NSSegmentedControl()
    private let titleLabel = settingsLabel(size: 20, weight: .semibold)
    private let subtitleLabel = settingsLabel(size: 12, color: SettingsPalette.secondary)
    private let statusLabel = settingsLabel(size: 11, color: SettingsPalette.secondary)
    private let footerLabel = settingsLabel(size: 11, color: SettingsPalette.tertiary)
    private let restoreButton = NSButton()
    private let doneButton = SettingsPrimaryButton()
    private let closeButton = NSButton()
    private let sidebar = SettingsSurfaceView()
    private let brandLabel = settingsLabel("LPlayer", size: 13, weight: .semibold)
    private let brandSubtitle = settingsLabel(size: 11, color: SettingsPalette.secondary)
    private let brandIcon = NSImageView()
    private let sidebarCaption = settingsLabel(size: 10, color: SettingsPalette.tertiary)
    private let shortcutPane = SettingsFlippedView()
    private let generalPane = SettingsGeneralPane()
    private let aboutPane = SettingsAboutPane()
    private let scrollView = NSScrollView()
    private var navigation: [SettingsSidebarButton] = []
    private var recordingAction: ShortcutAction?
    private var keyMonitor: Any?
    private enum TableEntry { case heading(String), action(ShortcutAction) }
    private var entries: [TableEntry] = []

    init(store: ShortcutStore, hand: HandLayout, panSensitivity: Double? = nil) {
        self.store = store
        self.hand = hand
        self.panSensitivity = min(1.5, max(0.25, panSensitivity ?? UserDefaults.standard.double(forKey: "videoPanSensitivity").nonzeroSensitivity))
        super.init()
    }

    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

    func present(asSheetFor parent: NSWindow) { presentSettings(asSheetFor: parent, section: .shortcuts) }

    func presentSettings(asSheetFor parent: NSWindow, section: Section = .general) {
        self.section = section
        if let sheet {
            guard sheet.sheetParent == nil, parent.attachedSheet == nil else { return }
            refreshLocalization()
            updateSection()
            parent.beginSheet(sheet)
            sheet.makeFirstResponder(section == .shortcuts ? searchField : closeButton)
            return
        }
        guard parent.attachedSheet == nil else { return }
        let panel = ShortcutCapturePanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 540),
                                         styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.minSize = NSSize(width: 680, height: 520)
        panel.delegate = self
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onRecordingKey = { [weak self] event in self?.capture(event) ?? false }
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.recordingAction != nil { self.cancelRecording() } else { self.dismiss() }
        }
        let content = ShortcutEditorContentView(frame: NSRect(x: 0, y: 0, width: 740, height: 540))
        panel.contentView = content
        sheet = panel
        sidebar.fillColor = SettingsPalette.sidebar
        sidebar.cornerRadius = 0
        sidebar.drawsBorder = false
        BrandTypography.applyWordmark(to: brandLabel, size: 13)
        brandIcon.image = NSApp.applicationIconImage
        brandIcon.imageScaling = .scaleProportionallyDown
        [brandIcon, brandLabel, brandSubtitle, sidebarCaption].forEach(sidebar.addSubview)
        navigation = [
            SettingsSidebarButton(title: "", symbol: "gearshape", color: .systemGray),
            SettingsSidebarButton(title: "", symbol: "keyboard", color: .systemPurple),
            SettingsSidebarButton(title: "", symbol: "info.circle", color: .systemBlue)
        ]
        for (index, button) in navigation.enumerated() {
            button.tag = index
            button.target = self
            button.action = #selector(selectSection(_:))
            sidebar.addSubview(button)
        }
        generalPane.hand = hand
        generalPane.sensitivity = panSensitivity
        generalPane.onHandChange = { [weak self] in self?.setHand($0) }
        generalPane.onLanguageChange = { [weak self] language in
            guard let self else { return }
            self.stopRecording()
            if let callback = self.onLanguageChange { callback(language) } else { L10n.select(language) }
            self.refreshLocalization()
        }
        generalPane.onPanSensitivityChange = { [weak self] sensitivity in
            guard let self else { return }
            self.panSensitivity = sensitivity
            UserDefaults.standard.set(sensitivity, forKey: "videoPanSensitivity")
            self.onPanSensitivityChange?(sensitivity)
        }
        generalPane.onOpenShortcuts = { [weak self] in self?.showSection(.shortcuts) }

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        column.minWidth = 0
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 48
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        profileControl.segmentCount = 2
        profileControl.trackingMode = .selectOne
        profileControl.segmentStyle = .rounded
        profileControl.controlSize = .small
        profileControl.target = self
        profileControl.action = #selector(chooseProfile(_:))
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.controlSize = .small
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefaults(_:))
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .small
        restoreButton.font = .systemFont(ofSize: 11)
        doneButton.target = self
        doneButton.action = #selector(done(_:))
        doneButton.contentTintColor = .white
        doneButton.font = .systemFont(ofSize: 12, weight: .medium)
        doneButton.keyEquivalent = "\r"
        doneButton.keyEquivalentModifierMask = []
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.contentTintColor = SettingsPalette.secondary
        closeButton.target = self
        closeButton.action = #selector(done(_:))
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.cell?.usesSingleLineMode = false
        [titleLabel, subtitleLabel, profileControl, searchField, scrollView, statusLabel].forEach(shortcutPane.addSubview)
        [sidebar, generalPane, shortcutPane, aboutPane, footerLabel, restoreButton, doneButton, closeButton].forEach(content.addSubview)
        content.onLayout = { [weak self] bounds in self?.layoutContent(bounds) }
        refreshLocalization()
        updateSection()
        parent.beginSheet(panel)
        panel.minSize = NSSize(width: 680, height: 520)
        panel.makeFirstResponder(section == .shortcuts ? searchField : closeButton)
    }

    private func layoutContent(_ bounds: NSRect) {
        let sidebarWidth: CGFloat = 160
        let paneWidth = bounds.width - sidebarWidth
        let paneHeight = bounds.height - 60
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        brandIcon.frame = NSRect(x: 20, y: 25, width: 31, height: 31)
        brandLabel.frame = NSRect(x: 61, y: 26, width: 82, height: 19)
        brandSubtitle.frame = NSRect(x: 61, y: 46, width: 82, height: 16)
        for (index, button) in navigation.enumerated() { button.frame = NSRect(x: 10, y: 91 + CGFloat(index) * 40, width: 140, height: 36) }
        sidebarCaption.frame = NSRect(x: 20, y: bounds.height - 29, width: 128, height: 17)
        let paneFrame = NSRect(x: sidebarWidth, y: 0, width: paneWidth, height: paneHeight)
        generalPane.frame = paneFrame
        shortcutPane.frame = paneFrame
        aboutPane.frame = paneFrame
        closeButton.frame = NSRect(x: bounds.width - 42, y: 16, width: 25, height: 25)
        titleLabel.frame = NSRect(x: 28, y: 30, width: paneWidth - 80, height: 26)
        subtitleLabel.frame = NSRect(x: 28, y: 62, width: paneWidth - 56, height: 18)
        profileControl.frame = NSRect(x: 27, y: 95, width: 153, height: 28)
        searchField.frame = NSRect(x: 194, y: 96, width: paneWidth - 222, height: 26)
        scrollView.frame = NSRect(x: 22, y: 139, width: paneWidth - 44, height: max(0, paneHeight - 191))
        tableView.tableColumns.first?.width = scrollView.contentSize.width
        tableView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: tableView.frame.height))
        statusLabel.frame = NSRect(x: 29, y: paneHeight - 43, width: paneWidth - 58, height: 35)
        footerLabel.frame = NSRect(x: sidebarWidth + 23, y: bounds.height - 38, width: paneWidth - 140, height: 17)
        restoreButton.frame = NSRect(x: sidebarWidth + 20, y: bounds.height - 44, width: min(220, paneWidth - 150), height: 29)
        doneButton.frame = NSRect(x: bounds.width - 89, y: bounds.height - 44, width: 66, height: 29)
    }

    func dismiss() {
        guard let panel = sheet else { return }
        stopRecording()
        if let parent = panel.sheetParent { parent.endSheet(panel) }
        panel.orderOut(nil)
        onClose?()
    }

    func refreshLocalization() {
        guard sheet != nil else { return }
        brandSubtitle.stringValue = L10n.text("Settings", "设置")
        sidebarCaption.stringValue = L10n.text("Made for focused viewing", "为专注观看而设")
        navigation[0].title = L10n.text("General", "通用")
        navigation[1].title = L10n.text("Shortcuts", "快捷键")
        navigation[2].title = L10n.text("About", "关于")
        navigation.forEach { $0.needsDisplay = true; $0.setAccessibilityLabel($0.title) }
        titleLabel.stringValue = L10n.text("Keyboard Shortcuts", "快捷键")
        subtitleLabel.stringValue = L10n.text("Click a key to record. Each hand has its own shortcuts.", "点击键帽录制快捷键，左右手布局分别保存。")
        profileControl.setLabel(HandLayout.left.title, forSegment: 0)
        profileControl.setLabel(HandLayout.right.title, forSegment: 1)
        profileControl.selectedSegment = hand == .left ? 0 : 1
        profileControl.setAccessibilityLabel(L10n.text("Active hand profile", "当前左右手布局"))
        searchField.placeholderString = L10n.text("Search shortcuts", "搜索快捷键")
        searchField.setAccessibilityLabel(L10n.text("Search keyboard shortcuts", "搜索快捷键功能"))
        tableView.setAccessibilityLabel(L10n.text("Keyboard shortcut assignments", "快捷键设置列表"))
        restoreButton.title = L10n.text("Restore Profile Defaults", "恢复此布局的默认快捷键")
        doneButton.title = L10n.text("Done", "完成")
        closeButton.setAccessibilityLabel(L10n.text("Close settings", "关闭设置"))
        footerLabel.stringValue = L10n.text("Changes take effect immediately", "更改会立即生效")
        generalPane.hand = hand
        generalPane.sensitivity = panSensitivity
        generalPane.refreshLocalization()
        aboutPane.refreshLocalization()
        sheet?.title = L10n.text("LPlayer Settings", "LPlayer 设置")
        applyFilter()
        if recordingAction != nil { setStatus(recordingPrompt(), error: false) }
    }

    private func defaultStatus() -> String {
        L10n.text("Use the row menu to clear or reset a key. Standard menu shortcuts stay available.", "通过行末菜单清除或重置快捷键，标准菜单快捷键始终保留。")
    }

    private func showSection(_ section: Section) {
        if recordingAction != nil { cancelRecording(releaseFocus: false) }
        self.section = section
        updateSection()
        sheet?.makeFirstResponder(section == .shortcuts ? searchField : closeButton)
    }

    private func updateSection() {
        generalPane.isHidden = section != .general
        shortcutPane.isHidden = section != .shortcuts
        aboutPane.isHidden = section != .about
        restoreButton.isHidden = section != .shortcuts
        footerLabel.isHidden = section == .shortcuts
        for (index, button) in navigation.enumerated() {
            button.selected = index == section.rawValue
            button.setAccessibilityValue(button.selected ? 1 : 0)
        }
        sheet?.contentView?.needsLayout = true
    }

    private func setHand(_ selected: HandLayout) {
        stopRecording()
        hand = selected
        UserDefaults.standard.set(hand.rawValue, forKey: "handLayout")
        onHandChange?(hand)
        generalPane.hand = hand
        profileControl.selectedSegment = hand == .left ? 0 : 1
        applyFilter()
        if !entries.isEmpty {
            setStatus(L10n.text("Profile switched. Changes are saved separately for each hand.", "已切换当前布局，左右手快捷键分别保存。"), error: false)
        }
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        entries = ShortcutPresentationGroup.all.flatMap { group -> [TableEntry] in
            let actions = group.actions.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || store.label(for: $0, hand: hand).localizedCaseInsensitiveContains(query) }
            return actions.isEmpty ? [] : [.heading(group.title)] + actions.map(TableEntry.action)
        }
        tableView.reloadData()
        if recordingAction == nil {
            setStatus(entries.isEmpty ? L10n.text("No shortcuts match this search.", "没有找到相关快捷键，试试功能名称或按键。") : defaultStatus(), error: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard entries.indices.contains(row) else { return 48 }
        if case .heading = entries[row] { return 29 }
        return 48
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        switch entries[row] {
        case .heading(let title):
            let view = ShortcutEditorHeadingRow()
            view.configure(title)
            return view
        case .action(let action):
            let identifier = NSUserInterfaceItemIdentifier("ShortcutEditorRow")
            let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? ShortcutEditorRow) ?? ShortcutEditorRow(frame: .zero)
            view.identifier = identifier
            view.configure(action: action, binding: store.binding(for: action, hand: hand), aliases: store.aliases(for: action, hand: hand), recording: recordingAction == action)
            view.onRecord = { [weak self] in self?.beginRecording(action: action) }
            view.onClear = { [weak self] in self?.clearBinding(action: action) }
            view.onReset = { [weak self] in self?.resetBinding(action: action) }
            return view
        }
    }

    private func beginRecording(action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event) == true ? nil : event
        }
        sheet?.makeFirstResponder(sheet?.contentView)
        tableView.reloadData()
        setStatus(recordingPrompt(), error: false)
    }
    private func recordingPrompt() -> String { L10n.text("Press a key combination · Esc cancels · Delete clears", "请按下快捷键组合 · Esc 取消 · Delete 清除") }
    private func setStatus(_ message: String, error: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = error ? .systemOrange : SettingsPalette.secondary
        statusLabel.toolTip = message
        statusLabel.setAccessibilityLabel(message)
    }

    /// Both the local monitor and sheet key-equivalent route use this gate, so
    /// Command-Q cannot escape recording into the application menu.
    @discardableResult private func capture(_ event: NSEvent) -> Bool {
        guard let action = recordingAction, let sheet, event.window === sheet, event.type == .keyDown else { return false }
        guard let chord = KeyChord(event: event) else { return true }
        if chord.key == "\u{1b}", chord.modifiers.isEmpty { cancelRecording(); return true }
        if (chord.key == "\u{7f}" || chord.key == "\u{f728}"), chord.modifiers.isEmpty { clearBinding(action: action); return true }
        if let message = store.setBinding(chord, for: action, hand: hand) {
            setStatus(message + " · " + L10n.text("Try another key, or Esc to cancel.", "请尝试其他按键，或按 Esc 取消。"), error: true)
            return true
        }
        stopRecording()
        tableView.reloadData()
        setStatus(L10n.format("%@ → %@", "%@ → %@", action.title, chord.display), error: false)
        sheet.makeFirstResponder(nil)
        return true
    }
    private func cancelRecording(releaseFocus: Bool = true) {
        guard recordingAction != nil else { return }
        stopRecording()
        tableView.reloadData()
        setStatus(L10n.text("Recording cancelled. The shortcut is unchanged.", "已取消录制，快捷键保持原样。"), error: false)
        if releaseFocus { sheet?.makeFirstResponder(nil) }
    }
    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        recordingAction = nil
    }
    private func clearBinding(action: ShortcutAction) {
        stopRecording()
        if let message = store.setBinding(nil, for: action, hand: hand) { setStatus(message, error: true) }
        else { setStatus(L10n.format("Cleared %@. Standard aliases stay available.", "已清除%@的主快捷键，标准别名仍然可用。", action.title), error: false) }
        tableView.reloadData()
        sheet?.makeFirstResponder(nil)
    }
    private func resetBinding(action: ShortcutAction) {
        stopRecording()
        store.reset(action, hand: hand)
        tableView.reloadData()
        setStatus(L10n.format("Restored the default for %@.", "已恢复%@的默认快捷键。", action.title), error: false)
    }
    @objc private func restoreDefaults(_ sender: Any?) {
        stopRecording()
        store.resetAll(hand: hand)
        tableView.reloadData()
        setStatus(L10n.text("This profile’s default shortcuts are restored.", "已恢复当前布局的全部默认快捷键。"), error: false)
    }
    @objc private func chooseProfile(_ sender: Any?) { setHand(profileControl.selectedSegment == 0 ? .left : .right) }
    @objc private func selectSection(_ sender: NSButton) { if let selected = Section(rawValue: sender.tag) { showSection(selected) } }
    @objc private func done(_ sender: Any?) { dismiss() }
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        if recordingAction != nil { cancelRecording(releaseFocus: false) }
        applyFilter()
    }
    func controlTextDidBeginEditing(_ obj: Notification) {
        if (obj.object as? NSSearchField) === searchField, recordingAction != nil { cancelRecording(releaseFocus: false) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}

private extension Double {
    var nonzeroSensitivity: Double { isFinite && self > 0 ? self : 1 }
}

private final class ShortcutCapturePanel: NSPanel {
    var onRecordingKey: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onRecordingKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class ShortcutEditorContentView: SettingsFlippedView {
    var onLayout: ((NSRect) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); onLayout?(bounds) }
    override func draw(_ dirtyRect: NSRect) {
        SettingsPalette.background.setFill()
        bounds.fill()
        SettingsPalette.line.setFill()
        NSRect(x: 160, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 160, y: bounds.height - 60, width: max(0, bounds.width - 160), height: 1).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        border.lineWidth = 1
        border.stroke()
    }
}

private final class ShortcutEditorHeadingRow: NSView {
    private let titleLabel = settingsLabel(size: 11, color: SettingsPalette.secondary, weight: .medium)
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); addSubview(titleLabel) }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ title: String) { titleLabel.stringValue = title }
    override func layout() { super.layout(); titleLabel.frame = NSRect(x: 10, y: 4, width: max(0, bounds.width - 20), height: 17) }
}

private final class ShortcutEditorRow: NSView {
    var onRecord: (() -> Void)?
    var onClear: (() -> Void)?
    var onReset: (() -> Void)?
    private let actionLabel = settingsLabel(size: 13)
    private let aliasLabel = settingsLabel(size: 10, color: SettingsPalette.tertiary)
    private let recordButton = NSButton()
    private let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = SettingsPalette.group.cgColor
        recordButton.target = self
        recordButton.action = #selector(record(_:))
        recordButton.bezelStyle = .rounded
        recordButton.controlSize = .small
        recordButton.font = .systemFont(ofSize: 11, weight: .medium)
        moreButton.isBordered = false
        moreButton.controlSize = .small
        moreButton.imagePosition = .imageOnly
        moreButton.menu?.autoenablesItems = false
        [actionLabel, aliasLabel, recordButton, moreButton].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(action: ShortcutAction, binding: KeyChord?, aliases: [KeyChord], recording: Bool) {
        actionLabel.stringValue = action.title
        actionLabel.toolTip = action.title
        aliasLabel.stringValue = aliases.isEmpty ? "" : L10n.text("Also: ", "保留：") + aliases.map(\.display).joined(separator: "  ")
        aliasLabel.toolTip = aliasLabel.stringValue
        recordButton.title = recording ? L10n.text("Press keys…", "请按快捷键…") : binding?.display ?? L10n.text("Unassigned", "未设置")
        recordButton.contentTintColor = recording ? SettingsPalette.accent : SettingsPalette.text
        recordButton.toolTip = L10n.format("%@ · %@ · Click to record", "%@ · %@ · 点击录制", action.title, recordButton.title)
        recordButton.setAccessibilityLabel(recordButton.toolTip)
        moreButton.removeAllItems()
        moreButton.addItem(withTitle: "")
        moreButton.item(at: 0)?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        moreButton.addItem(withTitle: L10n.text("Clear Shortcut", "清除快捷键"))
        moreButton.item(at: 1)?.target = self
        moreButton.item(at: 1)?.action = #selector(clear(_:))
        moreButton.item(at: 1)?.isEnabled = binding != nil || recording
        moreButton.addItem(withTitle: L10n.text("Restore Default", "恢复默认"))
        moreButton.item(at: 2)?.target = self
        moreButton.item(at: 2)?.action = #selector(reset(_:))
        moreButton.setAccessibilityLabel(L10n.format("More options for %@", "%@的更多操作", action.title))
        moreButton.toolTip = L10n.text("Clear or restore this shortcut", "清除或恢复此快捷键")
        layer?.borderWidth = recording ? 1 : 0
        layer?.borderColor = SettingsPalette.accent.withAlphaComponent(0.55).cgColor
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let right = bounds.width - 9
        moreButton.frame = NSRect(x: right - 25, y: 11, width: 25, height: 26)
        recordButton.frame = NSRect(x: right - 153, y: 10, width: 119, height: 28)
        let textWidth = max(0, bounds.width - 184)
        actionLabel.frame = NSRect(x: 12, y: aliasLabel.stringValue.isEmpty ? 15 : 24, width: textWidth, height: 18)
        aliasLabel.frame = NSRect(x: 12, y: 8, width: textWidth, height: 13)
    }
    @objc private func record(_ sender: Any?) { onRecord?() }
    @objc private func clear(_ sender: Any?) { onClear?() }
    @objc private func reset(_ sender: Any?) { onReset?() }
}

private final class SettingsAboutPane: SettingsFlippedView {
    private let heading = settingsLabel(size: 20, weight: .semibold)
    private let icon = NSImageView()
    private let wordmark = settingsLabel("LPlayer", size: 28, weight: .semibold)
    private let version = settingsLabel(size: 12, color: SettingsPalette.secondary)
    private let descriptionLabel = settingsLabel(size: 13, color: SettingsPalette.secondary)
    private let details = SettingsSurfaceView()
    private let keyboardLabel = settingsLabel(size: 12)
    private let keyboardValue = settingsLabel(size: 12, color: SettingsPalette.secondary)
    private let typographyLabel = settingsLabel(size: 12)
    private let typographyValue = settingsLabel("Manrope", size: 12, color: SettingsPalette.secondary)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyDown
        details.separatorOffsets = [48]
        BrandTypography.applyWordmark(to: wordmark, size: 28)
        wordmark.alignment = .center
        version.alignment = .center
        descriptionLabel.alignment = .center
        keyboardValue.alignment = .right
        typographyValue.alignment = .right
        [heading, icon, wordmark, version, descriptionLabel, details].forEach(addSubview)
        [keyboardLabel, keyboardValue, typographyLabel, typographyValue].forEach(details.addSubview)
        refreshLocalization()
    }
    required init?(coder: NSCoder) { fatalError() }
    func refreshLocalization() {
        heading.stringValue = L10n.text("About", "关于")
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            version.stringValue = L10n.text("Version ", "版本 ") + value
        } else { version.stringValue = L10n.text("Development build", "开发构建") }
        descriptionLabel.stringValue = L10n.text("A local video player. Made for focused viewing.", "本地视频播放器，为专注观看而设。")
        keyboardLabel.stringValue = L10n.text("Interface typography", "界面字体")
        keyboardValue.stringValue = L10n.text("macOS System", "macOS 系统字体")
        typographyLabel.stringValue = L10n.text("Wordmark typography", "品牌字标")
        needsLayout = true
    }
    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 28, y: 30, width: bounds.width - 80, height: 26)
        icon.frame = NSRect(x: (bounds.width - 72) / 2, y: 93, width: 72, height: 72)
        wordmark.frame = NSRect(x: 28, y: 181, width: bounds.width - 56, height: 40)
        version.frame = NSRect(x: 28, y: 229, width: bounds.width - 56, height: 20)
        descriptionLabel.frame = NSRect(x: 28, y: 265, width: bounds.width - 56, height: 22)
        details.frame = NSRect(x: 28, y: 330, width: bounds.width - 56, height: 96)
        keyboardLabel.frame = NSRect(x: 14, y: 15, width: 150, height: 19)
        keyboardValue.frame = NSRect(x: details.bounds.width - 174, y: 15, width: 160, height: 19)
        typographyLabel.frame = NSRect(x: 14, y: 62, width: 150, height: 19)
        typographyValue.frame = NSRect(x: details.bounds.width - 174, y: 62, width: 160, height: 19)
    }
}
