import AppKit

/// A virtualized queue sidebar. The player routes keyboard commands so the
/// selected row stays separate from the video that is currently playing.
final class PlaylistView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    enum ViewStyle: String { case compact, gallery }
    static let preferredWidth: CGFloat = 284
    static let galleryPreferredWidth: CGFloat = 320
    private(set) var viewStyle: ViewStyle = ViewStyle(rawValue: UserDefaults.standard.string(forKey: "playlistViewStyle") ?? "") ?? .compact
    var sidebarWidth: CGFloat { viewStyle == .gallery ? Self.galleryPreferredWidth : Self.preferredWidth }
    var onActivate: ((Int) -> Void)?
    var onClose: (() -> Void)?
    var onSelectionChange: ((Int) -> Void)?
    var onPreferredWidthChange: (() -> Void)?
    var onOpenRequested: (() -> Void)?
    var onHelpRequested: (() -> Void)?
    var authorizePreviewURL: ((URL) -> URL?)?
    var closeShortcut: String? { didSet { updateFooter() } }
    var overlaysVideo = false { didSet { if overlaysVideo != oldValue { updateBackground() } } }

    private let titleLabel = playlistLabel(size: 15, weight: .semibold)
    private let countLabel = playlistLabel(size: 10.5, color: .secondaryLabelColor)
    private let viewControl = NSSegmentedControl()
    private let folderIcon = NSImageView()
    private let folderLabel = playlistLabel(size: 10.5, color: .secondaryLabelColor)
    private let addButton = NSButton()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let movementLabel = playlistLabel(size: 10, color: .secondaryLabelColor)
    private let closeHintLabel = playlistLabel(size: 10, color: .secondaryLabelColor)
    private let helpButton = NSButton()
    private let emptyTitle = playlistLabel(size: 13, weight: .medium)
    private let emptyHint = playlistLabel(size: 11, color: .secondaryLabelColor)
    private let thumbnails = PlaylistThumbnailStore()
    private let motionPreview = PlaylistMotionPreview()
    private var urls: [URL] = []
    private var currentIndex = -1
    private var selectedIndex = -1
    private var durations: [URL: Double] = [:]
    private var hand: HandLayout = .left
    private var scrollAfterLayout = false
    private var lastScrollViewportSize: NSSize = .zero
    private var previewsEnabled = false
    private var previewsSuspended = false
    // An explicit selection starts silent previewing. Opening the sidebar or
    // updating playback state alone does not start a second decoder.
    private var motionSelectionURL: URL?
    private var requestedMotionURL: URL?
    private weak var livePreviewView: NSView?
    private var livePreviewURL: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        updateBackground()
        setAccessibilityElement(false)
        setAccessibilityRole(.group)

        viewControl.segmentCount = 2
        viewControl.trackingMode = .selectOne
        viewControl.segmentStyle = .rounded
        viewControl.controlSize = .small
        viewControl.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil), forSegment: 0)
        viewControl.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil), forSegment: 1)
        viewControl.setWidth(26, forSegment: 0)
        viewControl.setWidth(26, forSegment: 1)
        viewControl.selectedSegment = viewStyle == .compact ? 0 : 1
        viewControl.target = self
        viewControl.action = #selector(changeViewStyle(_:))

        folderIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderIcon.contentTintColor = .secondaryLabelColor
        folderIcon.imageScaling = .scaleProportionallyDown
        folderIcon.setAccessibilityElement(false)
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.target = self
        addButton.action = #selector(openFiles)
        helpButton.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        helpButton.imagePosition = .imageLeading
        helpButton.imageHugsTitle = true
        helpButton.imageScaling = .scaleProportionallyDown
        helpButton.font = .systemFont(ofSize: 10)
        helpButton.isBordered = false
        helpButton.contentTintColor = .secondaryLabelColor
        helpButton.target = self
        helpButton.action = #selector(showHelp)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("video"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        // The inset style adds native cell margins beyond the column width.
        // This sidebar already supplies its own gutter and rounded row shape.
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.autoresizingMask = [.width]
        tableView.rowHeight = PlaylistRowButton.height(forWidth: sidebarWidth - 16, style: viewStyle)
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleRowsChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged(_:)), name: name, object: nil)
        }
        thumbnails.onUpdate = { [weak self] url, image in
            self?.updateVisibleThumbnail(url: url, image: image)
        }
        motionPreview.onViewChange = { [weak self] view, url in
            self?.setLivePreviewView(view, for: url)
        }
        motionPreview.onDurationChange = { [weak self] url, duration in
            self?.updateDuration(duration, for: url)
        }

        emptyTitle.alignment = .center
        emptyHint.alignment = .center
        [titleLabel, countLabel, viewControl, folderIcon, folderLabel, addButton, scrollView, movementLabel, closeHintLabel, helpButton, emptyTitle, emptyHint].forEach(addSubview)
        refreshLocalization()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
        needsDisplay = true
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (overlaysVideo ? Palette.panel : PlaylistStyle.background).cgColor
            let secondary = overlaysVideo ? Palette.overlaySecondary : NSColor.secondaryLabelColor
            [countLabel, folderLabel, movementLabel, closeHintLabel].forEach { $0.textColor = secondary }
            folderIcon.contentTintColor = secondary
            addButton.contentTintColor = secondary
            helpButton.contentTintColor = secondary
        }
    }

    func setViewStyle(_ style: ViewStyle) {
        guard viewStyle != style else { return }
        viewStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "playlistViewStyle")
        viewControl.selectedSegment = style == .compact ? 0 : 1
        livePreviewView?.removeFromSuperview()
        tableView.rowHeight = PlaylistRowButton.height(forWidth: max(0, sidebarWidth - 16), style: style)
        tableView.reloadData()
        scrollAfterLayout = true
        needsLayout = true
        onPreferredWidthChange?()
        layoutSubtreeIfNeeded()
        attachLivePreviewToVisibleRow()
    }

    /// Playback and history supply known durations; unknown files keep an
    /// honest placeholder instead of opening another metadata decoder.
    func updateDuration(_ duration: Double, for url: URL) {
        guard duration.isFinite, duration > 0, duration < Double(Int.max),
              durations[url].map({ floor($0) != floor(duration) }) ?? true else { return }
        durations[url] = duration
        guard let rows = visibleRows() else { return }
        for row in rows where urls[row] == url {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? PlaylistRowButton)?.setDuration(duration)
        }
    }

    func setPreviewsEnabled(_ enabled: Bool) {
        guard previewsEnabled != enabled else { return }
        previewsEnabled = enabled
        thumbnails.setEnabled(enabled)
        if enabled { refreshVisibleMotionPreview(revalidate: true) }
        motionPreview.setEnabled(enabled)
        refreshVisiblePreviews()
    }

    func setPreviewsSuspended(_ suspended: Bool) {
        guard previewsSuspended != suspended else { return }
        previewsSuspended = suspended
        thumbnails.setSuspended(suspended)
        if !suspended { refreshVisibleMotionPreview(revalidate: true) }
        motionPreview.setSuspended(suspended)
        if !suspended { refreshVisiblePreviews() }
    }

    func shutdownPreviews() {
        stopMotionPreview()
        motionPreview.shutdown()
        thumbnails.shutdown()
    }

    /// Confirming a file transfers playback to the main player. A subsequent
    /// changed keyboard selection can start another card preview.
    func stopMotionPreview() {
        motionSelectionURL = nil
        requestedMotionURL = nil
        motionPreview.request(url: nil)
        setLivePreviewView(nil, for: nil)
    }

    /// The silent decoder owns this single surface. Only the selected, visible
    /// card may host it; recycled cards keep their static cover image below it.
    func setLivePreviewView(_ view: NSView?, for url: URL?) {
        let matchesSelection = urls.indices.contains(selectedIndex)
            && urls[selectedIndex] == url
            && motionSelectionURL == url
            && requestedMotionURL == url
        let canAttach = previewsEnabled && !previewsSuspended && matchesSelection
            && visibleRows()?.contains(selectedIndex) == true
        let nextView = canAttach ? view : nil
        if livePreviewView !== nextView { livePreviewView?.removeFromSuperview() }
        livePreviewView = nextView
        livePreviewURL = nextView == nil ? nil : url
        attachLivePreviewToVisibleRow()
    }

    func refreshLocalization() {
        titleLabel.stringValue = L10n.text("Playlist", "播放列表")
        viewControl.setToolTip(L10n.text("Compact list", "紧凑列表"), forSegment: 0)
        viewControl.setToolTip(L10n.text("Large previews", "大图预览"), forSegment: 1)
        viewControl.setAccessibilityLabel(L10n.text("Playlist view", "播放列表视图"))
        addButton.toolTip = L10n.text("Open videos or a folder · ⌘O", "打开视频或文件夹 · ⌘O")
        addButton.setAccessibilityLabel(addButton.toolTip)
        helpButton.title = L10n.text("Shortcuts", "快捷键")
        helpButton.setAccessibilityLabel(L10n.text("Show keyboard shortcuts", "查看快捷键"))
        emptyTitle.stringValue = L10n.text("Your playlist is empty", "播放列表为空")
        emptyHint.stringValue = L10n.text("⌘O Open a video or folder", "⌘O 打开视频或文件夹")
        setAccessibilityLabel(L10n.text("Playlist sidebar", "播放列表侧栏"))
        tableView.setAccessibilityLabel(L10n.text("Video playlist", "视频播放列表"))
        scrollView.setAccessibilityLabel(L10n.text("Scrollable video playlist", "滚动视频播放列表"))
        updateHeader()
        updateFooter()
        // Locale changes do not alter the queue, but the visible row states
        // and accessibility descriptions still need to switch immediately.
        let range = tableView.rows(in: tableView.visibleRect)
        if range.location != NSNotFound, range.length > 0 {
            let end = min(urls.count, NSMaxRange(range))
            if range.location < end {
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: range.location..<end), columnIndexes: IndexSet(integer: 0))
            }
        }
        attachLivePreviewToVisibleRow()
        needsDisplay = true
    }

    func update(urls: [URL], currentIndex: Int, selectedIndex: Int, hand: HandLayout) {
        let queueChanged = self.urls != urls
        let oldCurrent = self.currentIndex
        let oldSelection = self.selectedIndex
        let handChanged = self.hand != hand
        self.urls = urls
        self.currentIndex = urls.indices.contains(currentIndex) ? currentIndex : -1
        self.selectedIndex = normalizedSelection(selectedIndex)
        self.hand = hand

        if queueChanged {
            let retained = Set(urls)
            durations = durations.filter { retained.contains($0.key) }
            motionSelectionURL = nil
            requestedMotionURL = nil
            motionPreview.request(url: nil)
            tableView.reloadData()
        } else if oldCurrent != self.currentIndex || oldSelection != self.selectedIndex {
            if motionSelectionURL != selectedURL {
                motionSelectionURL = nil
                requestedMotionURL = nil
                motionPreview.request(url: nil)
            }
            reloadRows([oldCurrent, self.currentIndex, oldSelection, self.selectedIndex])
        }
        if queueChanged || oldCurrent != self.currentIndex { updateHeader() }
        if handChanged { updateFooter() }
        scrollView.isHidden = urls.isEmpty
        emptyTitle.isHidden = !urls.isEmpty
        emptyHint.isHidden = !urls.isEmpty
        if queueChanged || oldSelection != self.selectedIndex {
            scrollSelectionToVisible()
        }
        refreshVisiblePreviews()
    }

    func select(index: Int, scroll: Bool = true) {
        let oldSelection = selectedIndex
        selectedIndex = normalizedSelection(index)
        // An explicit selection also previews the already-selected card, such
        // as Up at the first item or reselecting it after confirmed playback.
        motionSelectionURL = selectedURL
        if oldSelection != selectedIndex {
            reloadRows([oldSelection, selectedIndex])
        }
        if scroll { scrollSelectionToVisible() }
        refreshVisiblePreviews()
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 18, y: bounds.height - 43, width: max(0, bounds.width - 104), height: 22)
        countLabel.frame = NSRect(x: 18, y: bounds.height - 64, width: max(0, bounds.width - 36), height: 16)
        viewControl.frame = NSRect(x: bounds.width - 74, y: bounds.height - 46, width: 60, height: 26)
        folderIcon.frame = NSRect(x: 18, y: bounds.height - 111, width: 14, height: 14)
        folderLabel.frame = NSRect(x: 39, y: bounds.height - 112, width: max(0, bounds.width - 87), height: 16)
        addButton.frame = NSRect(x: bounds.width - 42, y: bounds.height - 117, width: 28, height: 28)
        scrollView.frame = NSRect(x: 8, y: 59, width: max(0, bounds.width - 16), height: max(0, bounds.height - 185))
        let viewportSize = scrollView.contentSize
        if viewportSize != lastScrollViewportSize {
            lastScrollViewportSize = viewportSize
            scrollAfterLayout = true
        }
        if tableView.frame.width != viewportSize.width {
            tableView.setFrameSize(NSSize(width: viewportSize.width, height: tableView.frame.height))
        }
        if let column = tableView.tableColumns.first, column.width != viewportSize.width {
            column.width = viewportSize.width
        }
        let rowHeight = PlaylistRowButton.height(forWidth: viewportSize.width, style: viewStyle)
        if abs(tableView.rowHeight - rowHeight) > 0.5 {
            tableView.rowHeight = rowHeight
        }
        movementLabel.frame = NSRect(x: 16, y: 33, width: max(0, bounds.width - 32), height: 14)
        closeHintLabel.frame = NSRect(x: 16, y: 11, width: max(0, bounds.width - 110), height: 16)
        helpButton.frame = NSRect(x: bounds.width - 83, y: 7, width: 70, height: 24)
        emptyTitle.frame = NSRect(x: 20, y: bounds.midY - 2, width: max(0, bounds.width - 40), height: 20)
        emptyHint.frame = NSRect(x: 20, y: bounds.midY - 25, width: max(0, bounds.width - 40), height: 18)
        if scrollAfterLayout, urls.indices.contains(selectedIndex) {
            tableView.scrollRowToVisible(selectedIndex)
            scrollAfterLayout = false
        }
        refreshVisiblePreviews()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.075).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 16, y: bounds.height - 84, width: max(0, bounds.width - 32), height: 1).fill()
        NSRect(x: 0, y: 57, width: bounds.width, height: 1).fill()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { urls.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard urls.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("playlistRow")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? PlaylistRowButton) ?? PlaylistRowButton()
        cell.identifier = identifier
        cell.target = self
        cell.action = #selector(selectRow(_:))
        cell.onActivate = { [weak self] index in self?.activateRow(at: index) }
        cell.configure(url: urls[row], index: row, current: row == currentIndex, selected: row == selectedIndex,
                       preview: thumbnails.image(for: urls[row]), duration: durations[urls[row]], style: viewStyle)
        if row == selectedIndex, urls[row] == livePreviewURL, previewsEnabled, !previewsSuspended {
            cell.setLivePreviewView(livePreviewView)
        }
        return cell
    }

    func selectionShouldChange(in tableView: NSTableView) -> Bool { false }

    @objc private func selectRow(_ sender: PlaylistRowButton) {
        guard urls.indices.contains(sender.rowIndex) else { return }
        activateRow(at: sender.rowIndex)
    }

    private func activateRow(at index: Int) {
        guard urls.indices.contains(index) else { return }
        select(index: index)
        onSelectionChange?(index)
        onActivate?(index)
    }

    @objc private func changeViewStyle(_ sender: NSSegmentedControl) {
        setViewStyle(sender.selectedSegment == 1 ? .gallery : .compact)
    }
    @objc private func openFiles() { onOpenRequested?() }
    @objc private func showHelp() { onHelpRequested?() }

    @objc private func visibleRowsChanged() {
        refreshVisibleHoverStates()
        refreshVisiblePreviews()
    }

    @objc private func windowKeyChanged(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
        refreshVisibleHoverStates()
    }

    private func refreshVisibleHoverStates() {
        guard let rows = visibleRows() else { return }
        for row in rows {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? PlaylistRowButton)?.refreshHoverState()
        }
    }

    private func visibleRows() -> Range<Int>? {
        let range = tableView.rows(in: tableView.visibleRect)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        let end = min(urls.count, NSMaxRange(range))
        guard range.location < end else { return nil }
        return range.location..<end
    }

    private func refreshVisiblePreviews() {
        defer { refreshVisibleMotionPreview() }
        guard previewsEnabled, !scrollView.isHidden, scrollView.bounds.width > 0, scrollView.bounds.height > 0, let rows = visibleRows() else {
            thumbnails.setVisibleURLs([])
            return
        }
        thumbnails.setVisibleURLs(rows.map { urls[$0] })
    }

    private var selectedURL: URL? {
        urls.indices.contains(selectedIndex) ? urls[selectedIndex] : nil
    }

    private func refreshVisibleMotionPreview(revalidate: Bool = false) {
        // Disabled surfaces retain their desired selection for focus changes.
        // A selected card scrolled out of view releases its decoder entirely.
        if previewsEnabled {
            var target = !scrollView.isHidden
                && visibleRows()?.contains(selectedIndex) == true
                && motionSelectionURL == selectedURL ? motionSelectionURL : nil
            if let candidate = target, requestedMotionURL != target || revalidate,
               let authorizePreviewURL {
                let authorized = authorizePreviewURL(candidate)
                // A moved bookmark requires a refreshed queue before a view
                // can safely represent the original row's URL.
                if authorized?.standardizedFileURL != candidate.standardizedFileURL { target = nil }
            }
            if requestedMotionURL != target {
                requestedMotionURL = target
                motionPreview.request(url: target)
            }
        }
        attachLivePreviewToVisibleRow()
    }

    private func attachLivePreviewToVisibleRow() {
        let targetRow = previewsEnabled && !previewsSuspended
            && selectedURL == livePreviewURL && motionSelectionURL == livePreviewURL
            ? selectedIndex : -1
        var attached = false
        if let rows = visibleRows() {
            for row in rows {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? PlaylistRowButton else { continue }
                let view = row == targetRow && cell.representedURL == livePreviewURL ? livePreviewView : nil
                cell.setLivePreviewView(view)
                attached = attached || view != nil
            }
        }
        if !attached { livePreviewView?.removeFromSuperview() }
    }

    private func updateVisibleThumbnail(url: URL, image: NSImage?) {
        guard previewsEnabled, let rows = visibleRows() else { return }
        for row in rows where urls[row] == url {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? PlaylistRowButton,
                  cell.representedURL == url else { continue }
            cell.setPreviewImage(image)
        }
    }

    private func normalizedSelection(_ index: Int) -> Int {
        guard !urls.isEmpty else { return -1 }
        return min(urls.count - 1, max(0, index))
    }

    private func reloadRows(_ indices: [Int]) {
        let valid = IndexSet(indices.filter { urls.indices.contains($0) })
        guard !valid.isEmpty else { return }
        tableView.reloadData(forRowIndexes: valid, columnIndexes: IndexSet(integer: 0))
    }

    private func scrollSelectionToVisible() {
        guard urls.indices.contains(selectedIndex) else { return }
        tableView.scrollRowToVisible(selectedIndex)
        // A queue can arrive before the sidebar receives its first frame.
        // Repeat once after layout so the current row is visible on first open.
        scrollAfterLayout = true
        needsLayout = true
    }

    private func updateHeader() {
        let count = urls.count == 1
            ? L10n.text("1 video", "1 个视频")
            : L10n.format("%ld videos", "%ld 个视频", urls.count)
        countLabel.stringValue = currentIndex >= 0
            ? count + L10n.format(" · Current %ld", " · 当前 %ld", currentIndex + 1)
            : count
        tableView.setAccessibilityValue(countLabel.stringValue)
        let folders = Set(urls.map { $0.deletingLastPathComponent() })
        if let folder = folders.first, folders.count == 1 {
            folderLabel.stringValue = folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
            folderLabel.toolTip = folder.path
        } else {
            folderLabel.stringValue = urls.isEmpty
                ? L10n.text("Choose videos or a folder", "选择视频或文件夹")
                : L10n.text("Custom playlist", "自选播放列表")
            folderLabel.toolTip = folderLabel.stringValue
        }
    }

    private func updateFooter() {
        let key = closeShortcut ?? hand.playlistKey
        let navigation = hand == .left ? "W/S" : "I/K"
        movementLabel.stringValue = L10n.format("%@ / ↑↓ Select · ↵ Play", "%@ / ↑↓ 选择 · ↵ 播放", navigation)
        closeHintLabel.stringValue = L10n.format("%@ / Esc Close", "%@ / Esc 收起", key)
        closeHintLabel.toolTip = closeHintLabel.stringValue
        closeHintLabel.setAccessibilityLabel(closeHintLabel.stringValue)
        movementLabel.toolTip = L10n.format("%@ or ↑↓ select and preview silently · ←→ seek the current video, Shift for 30 seconds · Click, Enter or Space to play · %@ / Esc close", "%@ 或 ↑↓ 选择并静音预览 · ←→ 快退/快进当前视频，Shift 为 30 秒 · 单击、回车或空格播放 · %@ / Esc 收起", navigation, key)
        movementLabel.setAccessibilityLabel(movementLabel.toolTip)
    }
}

/// Real buttons keep each visible queue item actionable through accessibility.
/// NSTableView recycles them instead of materializing every file in a large queue.
private final class PlaylistRowButton: NSButton {
    override var isFlipped: Bool { false }
    var onActivate: ((Int) -> Void)?
    private let previewView = PlaylistPreviewView()
    private let filenameLabel = playlistLabel(size: 12, weight: .medium)
    private let detailLabel = playlistLabel(size: 10, color: .secondaryLabelColor)
    private let durationLabel = playlistLabel(size: 10, color: .secondaryLabelColor)
    private let playingIcon = NSImageView()
    private let playButton = NSButton()
    private(set) var rowIndex = -1
    private(set) var representedURL: URL?
    private var current = false
    private var selected = false
    private var hasLivePreview = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var style: PlaylistView.ViewStyle = .compact

    static func height(forWidth width: CGFloat, style: PlaylistView.ViewStyle) -> CGFloat {
        style == .compact ? 68 : max(0, width - 16) * 9 / 16 + 54
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        title = ""
        previewView.setAccessibilityElement(false)
        addSubview(previewView)
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        durationLabel.alignment = .right
        [filenameLabel, detailLabel, durationLabel].forEach {
            $0.setAccessibilityElement(false)
            addSubview($0)
        }
        playingIcon.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        playingIcon.contentTintColor = .systemBlue
        playingIcon.imageScaling = .scaleProportionallyDown
        playingIcon.setAccessibilityElement(false)
        addSubview(playingIcon)
        playButton.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
        playButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        playButton.isBordered = false
        playButton.isHidden = true
        playButton.contentTintColor = .systemBlue
        playButton.target = self
        playButton.action = #selector(activateVideo)
        // The whole row is the playback target. This icon is a visual cue,
        // not an extra confirmation step or a second accessibility action.
        playButton.setAccessibilityElement(false)
        addSubview(playButton)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(url: URL, index: Int, current: Bool, selected: Bool, preview: NSImage?, duration: Double?, style: PlaylistView.ViewStyle) {
        // Recycled rows may never receive an exit for their previous position.
        hovered = false
        rowIndex = index
        representedURL = url
        self.current = current
        self.selected = selected
        self.style = style
        setLivePreviewView(nil)
        previewView.setImage(preview)
        filenameLabel.stringValue = url.deletingPathExtension().lastPathComponent
        playingIcon.isHidden = !current
        toolTip = L10n.text("Click to play", "单击播放") + " · " + url.path
        filenameLabel.toolTip = url.lastPathComponent
        playButton.toolTip = L10n.text("Play this video", "播放此视频")
        playButton.setAccessibilityLabel(L10n.format("Play %@", "播放%@", url.lastPathComponent))
        setDuration(duration)
        setAccessibilityLabel(L10n.format("%ld, %@", "%ld，%@", index + 1, url.lastPathComponent) + (current ? L10n.text(", current video", "，当前视频") : ""))
        updatePreviewStatus()
        setAccessibilityHelp(L10n.text("Click or press Enter / Space to play. Use the vertical playlist navigation keys to select and preview silently. Left / Right seek the current video; hold Shift for 30 seconds.", "单击、回车或空格播放；使用列表上下导航键选择并静音预览。左右方向键快退/快进当前视频，按住 Shift 为 30 秒。") + " " + url.path)
        refreshHoverState()
        needsLayout = true
        needsDisplay = true
    }

    func setPreviewImage(_ image: NSImage?) { previewView.setImage(image) }

    func setDuration(_ duration: Double?) {
        if let duration, duration.isFinite, duration > 0, duration < Double(Int.max) {
            durationLabel.stringValue = clockText(duration)
        } else {
            durationLabel.stringValue = "—:—"
        }
    }

    func setLivePreviewView(_ view: NSView?) {
        previewView.setLiveView(view)
        let live = view != nil
        guard hasLivePreview != live else { return }
        hasLivePreview = live
        updatePreviewStatus()
        needsLayout = true
    }

    private func updatePreviewStatus() {
        detailLabel.stringValue = hasLivePreview
            ? L10n.text("Muted preview", "静音预览")
            : (current ? L10n.text("Current video", "当前视频")
               : (selected ? L10n.text("Selected", "已选择") : representedURL?.pathExtension.uppercased() ?? ""))
        detailLabel.textColor = .secondaryLabelColor
        var values: [String] = []
        if selected { values.append(L10n.text("Selected", "已选择")) }
        if hasLivePreview { values.append(L10n.text("Muted preview", "静音预览")) }
        setAccessibilityValue(values.joined(separator: ", "))
    }

    // Preserve the original single-click playback contract. The second press
    // of a double-click must not activate the row a second time during loading.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else { return }
        super.mouseDown(with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        activateVideo()
        return true
    }

    @objc private func activateVideo() { onActivate?(rowIndex) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        refreshHoverState()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverState()
    }
    override func mouseEntered(with event: NSEvent) { refreshHoverState() }
    override func mouseExited(with event: NSEvent) { refreshHoverState() }

    func refreshHoverState() {
        let isUnderPointer: Bool
        if let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            isUnderPointer = bounds.contains(point) && visibleRect.contains(point)
        } else {
            isUnderPointer = false
        }
        if hovered != isUnderPointer { needsDisplay = true }
        hovered = isUnderPointer
        updatePlayButton()
    }

    private func updatePlayButton() {
        playButton.isHidden = !hovered && !(selected && !current)
    }

    override func layout() {
        super.layout()
        let gallery = style == .gallery
        let textX: CGFloat = gallery ? 10 : 94
        let textRight = bounds.width - 10
        let previewWidth: CGFloat = gallery ? max(0, bounds.width - 16) : 76
        previewView.frame = NSRect(x: 8, y: gallery ? 46 : 12, width: previewWidth,
                                   height: gallery ? previewWidth * 9 / 16 : 44)
        filenameLabel.frame = NSRect(x: textX, y: gallery ? 25 : 35, width: max(0, textRight - textX), height: 18)
        let detailY: CGFloat = gallery ? 7 : 17
        let durationWidth: CGFloat = min(58, max(40, durationLabel.fittingSize.width + 2))
        durationLabel.frame = NSRect(x: textRight - durationWidth, y: detailY, width: durationWidth, height: 14)
        let detailX = textX + (current ? 14 : 0)
        detailLabel.frame = NSRect(x: detailX, y: detailY, width: max(0, durationLabel.frame.minX - detailX - 6), height: 14)
        playingIcon.frame = NSRect(x: textX, y: detailY + 2, width: 9, height: 10)
        playButton.frame = NSRect(x: previewView.frame.maxX - 27, y: previewView.frame.maxY - 27, width: 24, height: 24)
        refreshHoverState()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        if current || selected || hovered || cell?.isHighlighted == true {
            (current ? NSColor.systemBlue.withAlphaComponent(0.10) : NSColor.labelColor.withAlphaComponent(selected ? 0.045 : 0.025)).setFill()
            path.fill()
        }
        if selected {
            NSColor.systemBlue.withAlphaComponent(0.65).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        if current {
            NSColor.systemBlue.setFill()
            let indicator = style == .gallery
                ? NSRect(x: 10, y: 1, width: max(0, bounds.width - 20), height: 2)
                : NSRect(x: 1, y: 17, width: 2, height: max(0, bounds.height - 34))
            NSBezierPath(roundedRect: indicator, xRadius: 1, yRadius: 1).fill()
        }
    }
}

/// A fixed 16:9 well keeps different source aspect ratios intact, including
/// portrait videos. The button above owns hit testing for the entire row.
private final class PlaylistPreviewView: NSView {
    private let imageView = NSImageView()
    private let placeholderIcon = NSImageView()
    private weak var liveView: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.setAccessibilityElement(false)
        placeholderIcon.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        placeholderIcon.imageScaling = .scaleProportionallyDown
        placeholderIcon.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.6)
        placeholderIcon.setAccessibilityElement(false)
        addSubview(imageView)
        addSubview(placeholderIcon)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: NSImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        placeholderIcon.isHidden = image != nil
    }

    func setLiveView(_ view: NSView?) {
        if liveView !== view {
            if liveView?.superview === self { liveView?.removeFromSuperview() }
            liveView = view
        }
        if let view, view.superview !== self {
            view.removeFromSuperview()
            addSubview(view)
        }
        if let view, view.frame != bounds { view.frame = bounds }
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        placeholderIcon.frame = NSRect(x: bounds.midX - 10, y: bounds.midY - 8, width: 20, height: 16)
        if let liveView, liveView.superview === self, liveView.frame != bounds { liveView.frame = bounds }
    }
}

/// Sidebar text is on a stable surface rather than over the video, so it uses
/// ordinary system text rendering without the playback overlay's shadow.
private func playlistLabel(size: CGFloat, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    return field
}

private enum PlaylistStyle {
    static let background = NSColor(name: "LPlayerPlaylistBackground") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.125, green: 0.129, blue: 0.141, alpha: 1)
        }
        return NSColor(srgbRed: 0.945, green: 0.945, blue: 0.953, alpha: 1)
    }
}
