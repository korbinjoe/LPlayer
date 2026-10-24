import AppKit

enum Palette {
    static let background = NSColor(srgbRed: 0.075, green: 0.079, blue: 0.087, alpha: 1)
    // Shared by every floating playback surface. Keep text and images solid;
    // only the backdrop lets the picture through.
    static let panel = NSColor(srgbRed: 0.135, green: 0.139, blue: 0.153, alpha: 0.72)
    static let overlaySecondary = NSColor(srgbRed: 0.85, green: 0.855, blue: 0.88, alpha: 1)
    static let accent = NSColor(srgbRed: 0.039, green: 0.518, blue: 1, alpha: 1)
    static let muted = NSColor(srgbRed: 0.60, green: 0.605, blue: 0.64, alpha: 1)
    static let chrome = NSColor(srgbRed: 0.115, green: 0.119, blue: 0.131, alpha: 1)
    static let textShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        return shadow
    }()
}

/// Keep glyphs solid and readable against bright video without darkening the
/// entire panel or fading its contents along with its background.
private final class OverlayLabel: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        Palette.textShadow.set()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

func label(_ text: String, size: CGFloat = 13, color: NSColor = .labelColor, weight: NSFont.Weight = .regular, overVideo: Bool = false) -> NSTextField {
    let field = overVideo ? OverlayLabel(labelWithString: text) : NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    return field
}

func symbolButton(_ name: String, label title: String, target: AnyObject, action: Selector) -> NSButton {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: title)?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) ?? NSImage()
    let button = ChromeButton(image: image, target: target, action: action)
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.contentTintColor = NSColor.white.withAlphaComponent(0.88)
    button.toolTip = title
    button.setAccessibilityLabel(title)
    return button
}

final class PlayerSurface: NSView {
    var onDrop: (([URL]) -> Void)?
    var onMovement: (() -> Void)?
    var onMagnify: ((NSEvent) -> Void)?
    var onSmartMagnify: ((NSEvent) -> Void)?
    var onPan: ((NSEvent) -> Bool)?
    var videoPanCursorRect: NSRect? {
        didSet { if videoPanCursorRect != oldValue { window?.invalidateCursorRects(for: self) } }
    }
    var isVideoPanCursorClosed = false {
        didSet { if isVideoPanCursorClosed != oldValue { window?.invalidateCursorRects(for: self) } }
    }
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) { onMovement?() }
    override func mouseEntered(with event: NSEvent) { onMovement?() }
    // The video view forwards native trackpad events through its responder
    // chain. Keep controls and overlay content at their normal size.
    override func magnify(with event: NSEvent) { onMagnify?(event) }
    override func smartMagnify(with event: NSEvent) { onSmartMagnify?(event) }
    override func scrollWheel(with event: NSEvent) {
        if onPan?(event) != true { super.scrollWheel(with: event) }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if let rect = videoPanCursorRect, !rect.isEmpty {
            addCursorRect(rect, cursor: isVideoPanCursorClosed ? .closedHand : .openHand)
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let values = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !values.isEmpty else { return false }
        onDrop?(values)
        return true
    }
}

/// A small, passive affordance; gestures still reach the picture beneath it.
final class VideoZoomHintView: NSView {
    private let scaleLabel = label("", size: 11, color: .white, weight: .semibold, overVideo: true)
    private let movementLabel = label("", size: 11, color: .white, overVideo: true)
    private let resetLabel = label("", size: 11, color: Palette.overlaySecondary, overVideo: true)
    private struct Presentation: Equatable {
        let scalePercent: Int
        let resetKey: String
        let zoomKeys: String
        let language: AppLanguage
    }
    private var presentation: Presentation?
    private var measuredWidths: [CGFloat] = [0, 0, 0]
    private(set) var preferredWidth: CGFloat = 58
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.panel.cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        scaleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        [scaleLabel, movementLabel, resetLabel].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func refresh(scale: Double, resetKey: String, zoomKeys: String = "") {
        // Panning and mouse movement can refresh this presentation at trackpad
        // frequency. Reuse text metrics until its visible content changes.
        let percentage = scale.isFinite ? min(500, max(100, scale * 100)).rounded(.toNearestOrEven) : 100
        let next = Presentation(scalePercent: Int(percentage), resetKey: resetKey, zoomKeys: zoomKeys, language: L10n.language)
        guard next != presentation else { return }
        presentation = next
        let values = [L10n.format("%.0f%%", "%.0f%%", percentage),
                      (zoomKeys.isEmpty ? "" : L10n.text("\(zoomKeys) Zoom · ", "\(zoomKeys) 缩放 · ")) + L10n.text("Two-finger slide · Lift to stop", "双指滑动 · 松手即停"),
                      L10n.text("\(resetKey) Fit", "\(resetKey) 复原")]
        for (field, value) in zip([scaleLabel, movementLabel, resetLabel], values) where field.stringValue != value {
            field.stringValue = value
        }
        measuredWidths = [scaleLabel, movementLabel, resetLabel].map { ceil($0.fittingSize.width) }
        preferredWidth = measuredWidths.reduce(58, +)
        let instructions = L10n.text("Move two fingers without pressing. The picture follows your fingers and stops when you lift them.", "无需按下触控板，双指滑动即可移动画面，松手即停。")
        toolTip = instructions
        setAccessibilityLabel(values.joined(separator: " · ") + ". " + instructions)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        var x: CGFloat = 12
        for (field, width) in zip([scaleLabel, movementLabel, resetLabel], measuredWidths) {
            field.frame = NSRect(x: x, y: 7, width: width, height: 16)
            x += width + 17
        }
    }
}

final class SeekSlider: NSSlider {
    private(set) var isTracking = false
    private(set) var hoverPoint: NSPoint?
    var onHover: ((Double, NSPoint) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onTrackingChange: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private struct HoverGeometryKey: Equatable {
        let cell: ObjectIdentifier
        let bounds: NSRect
        let flipped: Bool
        let vertical: Bool
        let controlSize: NSControl.ControlSize
        let tickCount: Int
        let tickPosition: NSSlider.TickMarkPosition
        let direction: NSUserInterfaceLayoutDirection
        let minimum: Double
        let maximum: Double
    }
    private var hoverGeometry: (key: HoverGeometryKey, start: CGFloat, end: CGFloat)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        hoverTrackingArea = area
        addTrackingArea(area)
    }

    /// NSSlider's travel ends at the knob centers, inside the control's bounds.
    /// Ask its native cell for both endpoints so hover and native seeking agree.
    func hoverTime(at point: NSPoint) -> Double? {
        guard isEnabled, !isHidden, point.x.isFinite, point.y.isFinite,
              minValue.isFinite, maxValue.isFinite, maxValue > minValue,
              let sliderCell = cell as? NSSliderCell,
              sliderCell.sliderType == .linear else { return nil }
        let vertical = sliderCell.isVertical
        let key = HoverGeometryKey(cell: ObjectIdentifier(sliderCell), bounds: bounds, flipped: isFlipped,
            vertical: vertical, controlSize: sliderCell.controlSize, tickCount: sliderCell.numberOfTickMarks,
            tickPosition: sliderCell.tickMarkPosition, direction: userInterfaceLayoutDirection,
            minimum: minValue, maximum: maxValue)
        let start: CGFloat, end: CGFloat
        if let geometry = hoverGeometry, geometry.key == key {
            start = geometry.start; end = geometry.end
        } else {
            let originalValue = sliderCell.doubleValue
            sliderCell.calcDrawInfo(bounds)
            sliderCell.doubleValue = minValue
            let minimumKnob = sliderCell.knobRect(flipped: isFlipped)
            sliderCell.doubleValue = maxValue
            let maximumKnob = sliderCell.knobRect(flipped: isFlipped)
            sliderCell.doubleValue = originalValue
            start = vertical ? minimumKnob.midY : minimumKnob.midX
            end = vertical ? maximumKnob.midY : maximumKnob.midX
            hoverGeometry = (key, start, end)
        }
        let coordinate = vertical ? point.y : point.x
        guard start.isFinite, end.isFinite, abs(end - start) > 0.001 else { return nil }
        let fraction = max(0, min(1, Double((coordinate - start) / (end - start))))
        let time = minValue + fraction * (maxValue - minValue)
        return time.isFinite ? time : nil
    }

    func endHover() {
        guard hoverPoint != nil else { return }
        hoverPoint = nil
        onHoverEnd?()
    }

    private func updateHover(at point: NSPoint) {
        guard let time = hoverTime(at: point) else { endHover(); return }
        hoverPoint = point
        onHover?(time, point)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) { endHover() }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        onTrackingChange?(true)
        updateHover(at: convert(event.locationInWindow, from: nil))
        defer {
            isTracking = false
            onTrackingChange?(false)
            if let window {
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if bounds.contains(point) { updateHover(at: point) } else { endHover() }
            } else { endHover() }
        }
        super.mouseDown(with: event)
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        // NSSliderCell owns the native tracking loop. Continuous actions still
        // let the preview follow dragging without replacing native scrubbing.
        if isTracking, let window {
            updateHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        return super.sendAction(action, to: target)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endHover() }
    }
}

/// A passive preview that never takes clicks away from the video or slider.
final class ThumbnailPreviewView: NSView {
    enum State { case loading, ready, unavailable }
    static let preferredSize = NSSize(width: 212, height: 148)
    var pointerX: CGFloat = preferredSize.width / 2 { didSet { needsDisplay = true } }
    private var previewTime: Double = 0
    private var previewImage: NSImage?
    private var state: State = .loading

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { Self.preferredSize }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setPreview(time: Double, image: NSImage?, state: State) {
        previewTime = time.isFinite ? max(0, time) : 0
        previewImage = image
        self.state = state
        needsDisplay = true
    }

    func refreshLocalization() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 30, bounds.height > 40 else { return }
        let panel = NSRect(x: bounds.minX + 0.5, y: bounds.minY + 7.5, width: bounds.width - 1, height: bounds.height - 8)
        let tipX = max(panel.minX + 18, min(panel.maxX - 18, pointerX))
        let radius: CGFloat = 10
        let curve: CGFloat = radius * 0.55228475
        let path = NSBezierPath()
        path.move(to: NSPoint(x: panel.minX + radius, y: panel.minY))
        path.line(to: NSPoint(x: tipX - 6, y: panel.minY))
        path.line(to: NSPoint(x: tipX, y: bounds.minY + 1))
        path.line(to: NSPoint(x: tipX + 6, y: panel.minY))
        path.line(to: NSPoint(x: panel.maxX - radius, y: panel.minY))
        path.curve(to: NSPoint(x: panel.maxX, y: panel.minY + radius), controlPoint1: NSPoint(x: panel.maxX - radius + curve, y: panel.minY), controlPoint2: NSPoint(x: panel.maxX, y: panel.minY + radius - curve))
        path.line(to: NSPoint(x: panel.maxX, y: panel.maxY - radius))
        path.curve(to: NSPoint(x: panel.maxX - radius, y: panel.maxY), controlPoint1: NSPoint(x: panel.maxX, y: panel.maxY - radius + curve), controlPoint2: NSPoint(x: panel.maxX - radius + curve, y: panel.maxY))
        path.line(to: NSPoint(x: panel.minX + radius, y: panel.maxY))
        path.curve(to: NSPoint(x: panel.minX, y: panel.maxY - radius), controlPoint1: NSPoint(x: panel.minX + radius - curve, y: panel.maxY), controlPoint2: NSPoint(x: panel.minX, y: panel.maxY - radius + curve))
        path.line(to: NSPoint(x: panel.minX, y: panel.minY + radius))
        path.curve(to: NSPoint(x: panel.minX + radius, y: panel.minY), controlPoint1: NSPoint(x: panel.minX, y: panel.minY + radius - curve), controlPoint2: NSPoint(x: panel.minX + radius - curve, y: panel.minY))
        path.close()
        Palette.panel.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()

        let imageRect = NSRect(x: panel.minX + 5.5, y: panel.minY + 22.5, width: panel.width - 11, height: panel.height - 28)
        let imageClip = NSBezierPath(roundedRect: imageRect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        imageClip.addClip()
        NSColor.black.withAlphaComponent(0.2).setFill()
        imageRect.fill()
        if state != .unavailable, let image = previewImage, image.size.width > 0, image.size.height > 0 {
            let scale = min(imageRect.width / image.size.width, imageRect.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let destination = NSRect(x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            if state == .loading {
                // Keep the previous picture while the independent decoder finds
                // a new frame, but clearly label it as a pending preview.
                let loading = L10n.text("Loading…", "加载中…")
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white, .shadow: Palette.textShadow]
                let textSize = (loading as NSString).size(withAttributes: attributes)
                let badge = NSRect(x: imageRect.maxX - textSize.width - 14, y: imageRect.maxY - textSize.height - 11,
                                   width: textSize.width + 10, height: textSize.height + 6)
                Palette.panel.setFill()
                NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
                (loading as NSString).draw(at: NSPoint(x: badge.minX + 5, y: badge.minY + 3), withAttributes: attributes)
            }
        } else {
            let text = state == .unavailable ? L10n.text("Preview unavailable", "此处暂无预览") : L10n.text("Loading preview…", "正在生成预览…")
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Palette.overlaySecondary, .shadow: Palette.textShadow]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()

        let time = clockText(previewTime)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .shadow: Palette.textShadow]
        let timeSize = (time as NSString).size(withAttributes: attributes)
        (time as NSString).draw(at: NSPoint(x: panel.midX - timeSize.width / 2, y: panel.minY + 4), withAttributes: attributes)
    }
}

final class RoundedView: NSView {
    var passesThroughEvents = false
    init(color: NSColor, radius: CGFloat = 16) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        passesThroughEvents ? nil : super.hitTest(point)
    }
}

final class KeyHelpView: NSView {
    static let preferredWidth: CGFloat = 292
    var preferredHeight: CGFloat = 490
    var onClose: (() -> Void)?
    var shortcuts: ShortcutStore? { didSet { refreshLocalization() } }
    var hand: HandLayout = .left {
        didSet { if hand != oldValue { refreshLocalization() } }
    }
    private var shortcutItems: [(String, String)] = []
    private let scrollView = NSScrollView()
    private let rowsView = ShortcutRowsView()
    private let closeButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.panel.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        layer?.borderWidth = 1
        setAccessibilityElement(false)
        setAccessibilityRole(.group)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = rowsView
        addSubview(scrollView)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.contentTintColor = Palette.muted
        closeButton.target = self
        closeButton.action = #selector(closeSidebar)
        addSubview(closeButton)
        refreshLocalization()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeSidebar() { onClose?() }

    func refreshLocalization() {
        setAccessibilityLabel(L10n.text("Keyboard shortcuts sidebar", "快捷键侧栏"))
        scrollView.setAccessibilityLabel(L10n.text("One-handed keyboard shortcuts", "单手快捷键列表"))
        closeButton.setAccessibilityLabel(L10n.text("Close keyboard shortcuts", "收起快捷键提醒"))
        shortcutItems = makeShortcutItems()
        rowsView.items = shortcutItems
        updateAccessibility()
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: bounds.width - 39, y: bounds.height - 42, width: 24, height: 24)
        scrollView.frame = NSRect(x: 14, y: 81, width: max(0, bounds.width - 28), height: max(0, bounds.height - 144))
        rowsView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: CGFloat(shortcutItems.count) * ShortcutRowsView.rowHeight)
    }

    private func makeShortcutItems() -> [(String, String)] {
        let configured = ShortcutAction.allCases.compactMap { action -> (String, String)? in
            let primary = shortcuts.map { $0.binding(for: action, hand: hand) }
                ?? ShortcutStore.defaultBinding(for: action, hand: hand)
            let binding = primary ?? shortcuts?.aliases(for: action, hand: hand).first
            guard let binding else { return nil }
            return (binding.display, action.title)
        }
        return configured + [("Esc", L10n.text("Close / exit full screen", "收起 / 退出全屏"))]
    }

    private func shortcutLabel(_ action: ShortcutAction) -> String {
        if let shortcuts {
            return shortcuts.binding(for: action, hand: hand)?.display
                ?? shortcuts.aliases(for: action, hand: hand).first?.display ?? "—"
        }
        return ShortcutStore.defaultBinding(for: action, hand: hand)?.display ?? "—"
    }

    private func updateAccessibility() {
        let keys = shortcutItems.map { $0.0 + L10n.text(": ", "：") + $0.1 }.joined(separator: L10n.text(". ", "。"))
        rowsView.setAccessibilityLabel(hand == .left ? L10n.text("Left-hand shortcuts", "左手布局快捷键") : L10n.text("Right-hand shortcuts", "右手布局快捷键"))
        rowsView.setAccessibilityValue(keys + L10n.format(". Pinch to zoom, double-tap to zoom or reset. When zoomed, slide two fingers without clicking to move the picture. It follows your fingers and stops when you lift them. Pan sensitivity is adjustable in Quick Controls. In quick controls, use %@, then Space to confirm. Arrow keys, Enter and Esc stay available.", "。双指捏合缩放画面，双指双击放大或复原。放大后无需按下触控板，双指滑动即可移动画面，松手即停。快捷面板可调整拖动灵敏度。快捷面板内使用%@，空格确认。方向键、回车与 Esc 始终可用。", hand.movement))
        closeButton.toolTip = L10n.format("Press %@ or Esc to close", "按 %@ 或 Esc 收起", shortcutLabel(.help))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        (L10n.text("Keyboard shortcuts", "快捷键") as NSString).draw(at: NSPoint(x: 20, y: bounds.height - 35), withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.white, .shadow: Palette.textShadow])
        ((hand == .left ? L10n.text("Left-hand layout", "左手布局") : L10n.text("Right-hand layout", "右手布局")) as NSString).draw(at: NSPoint(x: 20, y: bounds.height - 53), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Palette.muted, .shadow: Palette.textShadow])
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: 20, y: bounds.height - 62, width: bounds.width - 40, height: 1).fill()
        NSRect(x: 20, y: 74, width: bounds.width - 40, height: 1).fill()
        let footerAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: Palette.muted, .shadow: Palette.textShadow]
        (L10n.text("Pinch to zoom · Double-tap zoom / reset", "双指捏合缩放 · 双指双击放大 / 复原") as NSString).draw(at: NSPoint(x: 20, y: 57), withAttributes: footerAttributes)
        (L10n.text("Two-finger slide · Lift to stop", "双指滑动移动画面 · 松手即停") as NSString).draw(at: NSPoint(x: 20, y: 42), withAttributes: footerAttributes)
        (L10n.text("↑↓ / Enter navigate panels · Esc closes", "面板内 ↑↓ / 回车选择 · Esc 收起") as NSString).draw(at: NSPoint(x: 20, y: 27), withAttributes: footerAttributes)
        (L10n.format("%@ Customize shortcuts", "%@ 自定义快捷键", shortcutLabel(.customizeShortcuts)) as NSString).draw(in: NSRect(x: 20, y: 12, width: bounds.width - 40, height: 15), withAttributes: footerAttributes)
    }

    private final class ShortcutRowsView: NSView {
        static let rowHeight: CGFloat = 26
        var items: [(String, String)] = [] { didSet { needsDisplay = true } }
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let keyAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: Palette.accent, .shadow: Palette.textShadow]
            let descriptionAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.white, .shadow: Palette.textShadow]
            for (index, item) in items.enumerated() {
                let keyRect = NSRect(x: 6, y: CGFloat(index) * Self.rowHeight + 2, width: 86, height: 22)
                guard dirtyRect.intersects(NSRect(x: 0, y: keyRect.minY, width: bounds.width, height: Self.rowHeight)) else { continue }
                Palette.accent.withAlphaComponent(0.09).setFill()
                NSBezierPath(roundedRect: keyRect, xRadius: 5, yRadius: 5).fill()
                let keyStyle = NSMutableParagraphStyle()
                keyStyle.alignment = .center; keyStyle.lineBreakMode = .byTruncatingMiddle
                var keys = keyAttributes; keys[.paragraphStyle] = keyStyle
                (item.0 as NSString).draw(in: keyRect.insetBy(dx: 3, dy: 4), withAttributes: keys)
                let descriptionSize = (item.1 as NSString).size(withAttributes: descriptionAttributes)
                let descriptionStyle = NSMutableParagraphStyle(); descriptionStyle.lineBreakMode = .byTruncatingTail
                var descriptions = descriptionAttributes; descriptions[.paragraphStyle] = descriptionStyle
                (item.1 as NSString).draw(in: NSRect(x: 103, y: keyRect.midY - descriptionSize.height / 2, width: max(0, bounds.width - 108), height: 22), withAttributes: descriptions)
            }
        }
    }
}

final class PanelRowButton: NSButton {
    override var isFlipped: Bool { false }
    var rowTitle = "" { didSet { if rowTitle != oldValue { needsDisplay = true } } }
    var detail = "" { didSet { if detail != oldValue { needsDisplay = true } } }
    var shortcut = "" {
        didSet { if shortcut != oldValue { shortcutWidth = nil; needsDisplay = true } }
    }
    var selected = false { didSet { if selected != oldValue { needsDisplay = true } } }
    private var shortcutWidth: CGFloat?
    private static let shortcutFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)

    var shortcutFrame: NSRect {
        let width: CGFloat
        if let cached = shortcutWidth { width = cached }
        else {
            width = max(26, min(100, ceil((shortcut as NSString).size(withAttributes: [.font: Self.shortcutFont]).width) + 14))
            shortcutWidth = width
        }
        return NSRect(x: bounds.width - 12 - width, y: 24, width: width, height: 20)
    }

    var titleFrame: NSRect {
        NSRect(x: 12, y: 24, width: max(0, shortcutFrame.minX - 20), height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            Palette.accent.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 9, yRadius: 9).fill()
        }
        let textColor: NSColor = selected ? Palette.accent : .white
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        (rowTitle as NSString).draw(in: titleFrame, withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular), .foregroundColor: textColor, .paragraphStyle: paragraph, .shadow: Palette.textShadow])
        (detail as NSString).draw(in: NSRect(x: 12, y: 7, width: bounds.width - 24, height: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Palette.muted, .paragraphStyle: paragraph, .shadow: Palette.textShadow])
        NSColor.white.withAlphaComponent(selected ? 0.09 : 0.055).setFill()
        NSBezierPath(roundedRect: shortcutFrame, xRadius: 5, yRadius: 5).fill()
        let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        let keyStyle = NSMutableParagraphStyle()
        keyStyle.alignment = .center; keyStyle.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: selected ? Palette.accent : Palette.muted, .paragraphStyle: keyStyle, .shadow: Palette.textShadow]
        (shortcut as NSString).draw(in: shortcutFrame.insetBy(dx: 5, dy: 3), withAttributes: attributes)
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
