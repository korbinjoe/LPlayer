import AppKit

final class PlayerTitlebarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

/// Shared native chrome for the approved LPlayer visual design.
final class ChromeButton: NSButton {
    enum Treatment { case plain, play, primary }
    var treatment: Treatment = .plain { didSet { needsDisplay = true } }
    var active = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor?
        switch treatment {
        case .play: color = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: isHighlighted ? 0.75 : 1)
        case .primary: color = Palette.accent.withAlphaComponent(isHighlighted ? 0.75 : 1)
        case .plain: color = active ? Palette.accent.withAlphaComponent(0.14) : (hovered || isHighlighted ? NSColor.white.withAlphaComponent(0.075) : nil)
        }
        if let color {
            color.setFill()
            let radius = treatment == .play ? bounds.height / 2 : 6
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
    }
}

final class ChromeSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let fraction = maxValue > minValue ? max(0, min(1, (doubleValue - minValue) / (maxValue - minValue))) : 0
        if fraction > 0 {
            Palette.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
    override func drawKnob(_ knobRect: NSRect) {
        let diameter: CGFloat = 9
        let circle = NSRect(x: knobRect.midX - diameter / 2, y: knobRect.midY - diameter / 2, width: diameter, height: diameter)
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(ovalIn: circle).fill()
    }
}

final class ChromeDivider: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.white.withAlphaComponent(0.075).setFill(); bounds.fill() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PlayerEmptyState: NSView {
    var onOpen: (() -> Void)?
    var onDemo: (() -> Void)?
    private let icon = NSImageView()
    private let heading = NSTextField(labelWithString: "")
    private let explanation = NSTextField(labelWithString: "")
    private let openButton = ChromeButton(title: "", target: nil, action: nil)
    private let demoButton = ChromeButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = Palette.background.cgColor
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        heading.font = .systemFont(ofSize: 25, weight: .semibold); heading.textColor = .white
        explanation.font = .systemFont(ofSize: 12); explanation.textColor = Palette.muted
        [heading, explanation].forEach { $0.alignment = .center }
        openButton.treatment = .primary; openButton.isBordered = false; openButton.bezelStyle = .regularSquare
        openButton.font = .systemFont(ofSize: 12, weight: .medium); openButton.contentTintColor = .white
        openButton.target = self; openButton.action = #selector(open)
        openButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openButton.imagePosition = .imageLeading; openButton.imageHugsTitle = true
        demoButton.isBordered = false; demoButton.font = .systemFont(ofSize: 11); demoButton.contentTintColor = Palette.muted
        demoButton.target = self; demoButton.action = #selector(demo)
        demoButton.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        demoButton.imagePosition = .imageTrailing; demoButton.imageHugsTitle = true
        [icon, heading, explanation, openButton, demoButton].forEach(addSubview)
        refreshLocalization()
    }
    required init?(coder: NSCoder) { fatalError() }
    func refreshLocalization() {
        heading.stringValue = L10n.text("Settle in. Press play.", "好好看一部视频。")
        explanation.stringValue = L10n.text("Drop a video here, or open one from your files.", "把视频拖到这里，或从文件中打开。")
        openButton.title = L10n.text("Open Video…    ⌘O", "打开视频…    ⌘O")
        demoButton.title = L10n.text("Try a demo film", "体验演示影片")
        openButton.setAccessibilityLabel(L10n.text("Open video · ⌘O", "打开视频 · ⌘O"))
        demoButton.setAccessibilityLabel(demoButton.title)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let center = bounds.midY + 10
        icon.frame = NSRect(x: bounds.midX - 43, y: center + 57, width: 86, height: 86)
        heading.frame = NSRect(x: 12, y: center + 1, width: bounds.width - 24, height: 36)
        explanation.frame = NSRect(x: 12, y: center - 31, width: bounds.width - 24, height: 20)
        openButton.frame = NSRect(x: bounds.midX - 78, y: center - 87, width: 156, height: 34)
        demoButton.frame = NSRect(x: bounds.midX - 92, y: center - 129, width: 184, height: 28)
    }
    @objc private func open() { onOpen?() }
    @objc private func demo() { onDemo?() }
}

/// A real AppKit control per row, with the same keyboard selection as playback.
final class QuickAdjustmentRow: NSView {
    enum Kind { case popup, slider, toggle, stepper, button }
    let kind: Kind
    var onFocus: (() -> Void)?
    var onNumber: ((Double) -> Void)?
    var onOption: ((Int) -> Void)?
    var onToggle: (() -> Void)?
    var onStep: ((Int) -> Void)?
    var onActivate: (() -> Void)?
    var selected = false { didSet { needsDisplay = true } }
    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let toggle = NSSwitch()
    private let minus = NSButton()
    private let plus = NSButton()
    private let actionButton = ChromeButton(title: "", target: nil, action: nil)

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        titleField.font = .systemFont(ofSize: 12); titleField.textColor = .white
        valueField.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular); valueField.textColor = Palette.muted; valueField.alignment = .right
        addSubview(titleField)
        switch kind {
        case .popup:
            popup.font = .systemFont(ofSize: 11); popup.controlSize = .small
            popup.target = self; popup.action = #selector(optionChanged)
            addSubview(popup)
        case .slider:
            slider.cell = ChromeSliderCell(); slider.minValue = 0; slider.maxValue = 100
            slider.isContinuous = true; slider.controlSize = .small
            slider.target = self; slider.action = #selector(numberChanged)
            addSubview(slider); addSubview(valueField)
        case .toggle:
            toggle.controlSize = .mini; toggle.target = self; toggle.action = #selector(toggleChanged)
            addSubview(toggle)
        case .stepper:
            valueField.alignment = .center
            for (button, symbol, action) in [(minus, "minus", #selector(stepMinus)), (plus, "plus", #selector(stepPlus))] {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                button.isBordered = false; button.contentTintColor = .white
                button.target = self; button.action = action
                addSubview(button)
            }
            addSubview(valueField)
        case .button:
            actionButton.isBordered = false
            actionButton.font = .systemFont(ofSize: 11)
            actionButton.contentTintColor = Palette.muted
            actionButton.target = self; actionButton.action = #selector(activateAction)
            addSubview(actionButton)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func setTitle(_ title: String, help: String) {
        titleField.stringValue = title; toolTip = help
        popup.setAccessibilityLabel(title); slider.setAccessibilityLabel(title); toggle.setAccessibilityLabel(title)
        minus.setAccessibilityLabel(title + L10n.text(" earlier", "提前"))
        plus.setAccessibilityLabel(title + L10n.text(" later", "延后"))
        actionButton.setAccessibilityLabel(title)
    }
    func setOptions(_ options: [String], selected index: Int, enabled: Bool = true) {
        if popup.itemTitles != options { popup.removeAllItems(); popup.addItems(withTitles: options) }
        if options.indices.contains(index) { popup.selectItem(at: index) }
        popup.isEnabled = enabled
    }
    func setNumber(_ value: Double, min: Double, max: Double, text: String) {
        slider.minValue = min; slider.maxValue = max
        if abs(slider.doubleValue - value) > 0.01 { slider.doubleValue = value }
        valueField.stringValue = text
    }
    func setToggle(_ value: Bool) { toggle.state = value ? .on : .off }
    func setStepText(_ text: String) { valueField.stringValue = text }
    func setActionTitle(_ text: String) { actionButton.title = text }
    override func draw(_ dirtyRect: NSRect) {
        if selected {
            Palette.accent.withAlphaComponent(0.13).setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 5, yRadius: 5)
            path.fill(); Palette.accent.withAlphaComponent(0.48).setStroke(); path.lineWidth = 1; path.stroke()
        }
        if kind == .stepper {
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 119, y: 6, width: 112, height: 24), xRadius: 5, yRadius: 5).fill()
        }
    }
    override func layout() {
        super.layout()
        let w = bounds.width
        titleField.frame = NSRect(x: 7, y: 9, width: max(80, w - 152), height: 18)
        switch kind {
        case .popup: popup.frame = NSRect(x: w - 122, y: 4, width: 119, height: 27)
        case .slider:
            slider.frame = NSRect(x: w - 150, y: 7, width: 105, height: 22)
            valueField.frame = NSRect(x: w - 45, y: 10, width: 36, height: 16)
        case .toggle: toggle.frame = NSRect(x: w - 38, y: 7, width: 30, height: 22)
        case .stepper:
            minus.frame = NSRect(x: w - 118, y: 7, width: 25, height: 22)
            valueField.frame = NSRect(x: w - 92, y: 10, width: 58, height: 16)
            plus.frame = NSRect(x: w - 33, y: 7, width: 25, height: 22)
        case .button: actionButton.frame = NSRect(x: w - 122, y: 5, width: 119, height: 25)
        }
    }
    override func mouseDown(with event: NSEvent) { onFocus?(); onActivate?() }
    @objc private func optionChanged() { onFocus?(); onOption?(popup.indexOfSelectedItem) }
    @objc private func numberChanged() { onFocus?(); onNumber?(slider.doubleValue) }
    @objc private func toggleChanged() { onFocus?(); onToggle?() }
    @objc private func stepMinus() { onFocus?(); onStep?(-1) }
    @objc private func stepPlus() { onFocus?(); onStep?(1) }
    @objc private func activateAction() { onFocus?(); onActivate?() }
}
