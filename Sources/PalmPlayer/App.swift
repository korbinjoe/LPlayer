import AppKit
import CoreAudio

@main
enum LPlayerMain {
    static func main() {
        L10n.configure()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = PlayerApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

private struct QuickItem {
    let title: String
    let detail: String
    let shortcut: String
    let shortcutHelp: String
    let action: () -> Void
    let adjust: ((Int) -> Void)?
    init(_ title: String, _ detail: String, shortcut: String, shortcutHelp: String, action: @escaping () -> Void, adjust: ((Int) -> Void)? = nil) {
        self.title = title; self.detail = detail; self.shortcut = shortcut; self.shortcutHelp = shortcutHelp
        self.action = action; self.adjust = adjust
    }
}

private struct PanelPresentation: Equatable {
    var speed: Double; var volume: Double; var subtitleDelay: Double
    var subtitlesVisible: Bool; var tracks: [MediaTrack]
    var zoom: Double; var sensitivity: Double; var hand: HandLayout; var language: AppLanguage
    var privateMode: Bool; var folderAccess: Bool; var queueCount: Int; var shortcutRevision: UInt64
}

private struct ZoomPresentation: Equatable {
    var visible: Bool; var scale: Double; var videoFrame: NSRect; var surfaceSize: NSSize
    var resetKey: String; var zoomKeys: String; var language: AppLanguage; var panning: Bool
}

final class PlayerApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSGestureRecognizerDelegate {
    private static let topBarHeight: CGFloat = 38
    private static let bottomBarHeight: CGFloat = 56
    private var window: NSWindow!
    private var surface: PlayerSurface!
    private var engine: MPVEngine!
    private let store: LibraryStore = {
        let store = LibraryStore(persistence: .background)
        // Finder may deliver URLs before applicationDidFinishLaunching.
        store.isPrivate = CommandLine.arguments.contains("--no-history")
        return store
    }()
    private let fileAccess = FileAccessStore()
    private let shortcuts = ShortcutStore(defaults: UserDefaults.standard)
    private var shortcutEditor: ShortcutEditor?
    private var currentURL: URL?
    private var queue: [URL] = []
    private var queueIndex = 0
    private var pendingRestore: PlaybackBookmark?
    private var fileReady = false
    private var finished = false
    private var lastSaved = Date.distantPast
    private let mediaDiscovery = MediaDiscovery()
    private var mediaRequestID: UInt64 = 0
    private var pendingExplicitQueueOpen: UInt64?
    private var subtitleRequestID: UInt64 = 0
    private var automaticSubtitleMaySelect = false
    private var pendingAutomaticSubtitleID: Int?
    // Volume belongs to the player, independent of each file's watch history.
    private var globalVolume: Double = {
        guard let stored = UserDefaults.standard.object(forKey: "playbackVolume") as? NSNumber,
              stored.doubleValue.isFinite else { return 70 }
        return min(100, max(0, stored.doubleValue))
    }()
    private var speedTarget: Double?
    private var subtitleDelayTarget: Double?
    private var editedControlsDuringLoad = Set<String>()
    private var controlRevisions: [String: UInt64] = [:]
    private var currentFolderAccess = false
    private var lastPresentedState: EngineSnapshot?
    private var lastPresentationLanguage: AppLanguage?
    private var panelPresentation: PanelPresentation?
    private var zoomPresentation: ZoomPresentation?
    private var shortcutRevision: UInt64 = 0
    private var undoPosition: Double?
    private var seekTarget: Double?
    private var lastSeekDate = Date.distantPast
    private lazy var seekScheduler = SeekScheduler { [weak self] target in self?.submitSeek(to: target) }
    private var thumbnailResumeWork: DispatchWorkItem?
    private var thumbnailPauseUntil = Date.distantPast
    private var hand = HandLayout(rawValue: UserDefaults.standard.string(forKey: "handLayout") ?? "left") ?? .left
    private var keyMonitor: Any?
    private lazy var videoSingleClick = NSClickGestureRecognizer(target: self, action: #selector(videoClicked))
    private lazy var videoDoubleClick = NSClickGestureRecognizer(target: self, action: #selector(fullscreen))
    private var titlebarObservations: [NSKeyValueObservation] = []
    private var titlebarLayoutPending = false
    private var audioListener: AudioObjectPropertyListenerBlock?
    private var terminated = false
    private var diagnosticsURL: URL?
    private var subtitleMargin = 0
    private var isZooming = false
    private var isPanningVideo = false
    private var allowsVideoPanMomentum = false
    private var videoPanSensitivity: Double = {
        guard let value = UserDefaults.standard.object(forKey: "videoPanSensitivity") as? NSNumber,
              value.doubleValue.isFinite else { return 1 }
        return min(1.5, max(0.25, value.doubleValue))
    }()
    private var lastVideoZoomScale: Double = 1
    private let thumbnailGenerator = ThumbnailGenerator()
    private let thumbnailPreview = ThumbnailPreviewView(frame: .zero)
    private var thumbnailHoverTime: Double?
    private var thumbnailBucket: Int?
    private var thumbnailRequestID: UInt64 = 0
    private var thumbnailReady = false
    private var thumbnailImage: NSImage?

    private let topBar = PlayerTitlebarView()
    private let bottomBar = PlayerChromeContainerView()
    private let brand = label("LPlayer", size: 11, color: .white, weight: .semibold)
    private let fileTitle = label(L10n.text("No video open", "未打开视频"), size: 13, color: .white, weight: .medium)
    private var brandMenuButton: NSButton!
    private var moreButton: NSButton!
    private var fileInfoButton: NSButton!
    private let topDivider = ChromeDivider()
    private let toolbarDivider = ChromeDivider()
    private let bottomDivider = ChromeDivider()
    private let emptyState = PlayerEmptyState(frame: .zero)
    private let mediaBadge = RoundedView(color: Palette.panel, radius: 5)
    private let mediaBadgeLabel = label("", size: 10, color: Palette.overlaySecondary, weight: .medium, overVideo: true)
    private var topOpenButton: NSButton!
    private var helpButton: NSButton!
    private var playlistButton: NSButton!
    private var privateButton: NSButton!
    private var recentMenu = NSMenu(title: L10n.text("Open Recent", "最近打开"))
    private var recentMenuSignature = ""
    private var playButton: NSButton!
    private var backwardButton: NSButton!
    private var forwardButton: NSButton!
    private var previousVideoButton: NSButton!
    private var nextVideoButton: NSButton!
    private var fullscreenButton: NSButton!
    private var subtitleButton: NSButton!
    private var panelButton: NSButton!
    private var speedButton: NSButton!
    private var volumeButton: NSButton!
    private let progress = SeekSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volume = NSSlider(value: 70, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let timeLabel = label("00:00 / 00:00", size: 10, color: Palette.overlaySecondary)
    private let hud = RoundedView(color: Palette.panel, radius: 12)
    private let hudLabel = label("", size: 15, color: .white, weight: .medium, overVideo: true)
    private var hudTimer: Timer?
    private var controlsTimer: Timer?
    private var controlsHideDeadline: TimeInterval = 0
    private var hudHideDeadline: TimeInterval = 0
    private let videoZoomHint = VideoZoomHintView(frame: .zero)
    private let help = LPlayerShortcutHelpView(frame: .zero)
    private let playlist = PlaylistView(frame: .zero)
    private var playlistSelection = 0
    private let panel = RoundedView(color: Palette.panel, radius: 13)
    private let panelTitle = label(L10n.text("Quick Controls", "快捷调节"), size: 13, color: .white, weight: .semibold, overVideo: true)
    private let panelHint = label("", size: 10, color: Palette.overlaySecondary, overVideo: true)
    private var panelCloseButton: NSButton!
    private var panelSettingsButton: NSButton!
    private let panelFooterLine = ChromeDivider()
    private let panelGroupLabels = (0..<4).map { _ in label("", size: 10, color: Palette.overlaySecondary, overVideo: true) }
    private let panelGroupLines = (0..<3).map { _ in ChromeDivider() }
    private let panelScroll = NSScrollView()
    private let panelDocument = FlippedView()
    private var panelRows: [QuickAdjustmentRow] = []
    private var selectedItem = 0
    private var panelItems: [QuickItem] = []
    private var presentedSpeedValues: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    private var lastPanelSignature = ""
    private let errorBox = RoundedView(color: Palette.panel, radius: 16)
    private let errorTitle = label(L10n.text("Unable to play this video", "这个视频暂时无法播放"), size: 18, color: .white, weight: .semibold, overVideo: true)
    private let errorMessage = label("", size: 13, color: Palette.overlaySecondary, overVideo: true)
    private var playbackError: String?
    private var playbackFailureReason: PlaybackFailureReason?
    private var pendingOpen: [URL] = []
    private var pendingSubtitleURLs: [URL] = []
    private var pendingSubtitleTarget: String?
    private var automaticSubtitleURLs: [URL] = []
    private var loadedSubtitlePaths = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > i + 1 {
            diagnosticsURL = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        }
        store.isPrivate = CommandLine.arguments.contains("--no-history")
        do { engine = try MPVEngine() }
        catch {
            let alert = NSAlert(); alert.messageText = L10n.text("Playback engine could not start", "播放引擎启动失败"); alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        shortcuts.onChange = { [weak self] in
            guard let self, self.surface != nil else { return }
            self.refreshShortcutPresentation()
        }
        buildMenu()
        buildWindow()
        configureEngine()
        engine.setDouble("volume", globalVolume)
        configureSystemEvents()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            // AppKit normally latches scroll events to their starting view.
            // Capture an owned stream before a control or sidebar can consume it.
            if event.type == .scrollWheel {
                guard event.window === self.window, self.isPanningVideo || self.allowsVideoPanMomentum else { return event }
                return self.panVideo(event) ? nil : event
            }
            return self.handleKey(event) ? nil : event
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(surface)
        if !pendingOpen.isEmpty { openURLs(pendingOpen); pendingOpen = [] }
        else {
            var files: [URL] = []
            var skip = false
            for arg in CommandLine.arguments.dropFirst() {
                if skip { skip = false; continue }
                if arg == "--diagnostics" { skip = true; continue }
                if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg) { files.append(URL(fileURLWithPath: arg)) }
            }
            if !files.isEmpty { openURLs(files) }
        }
        writeDiagnostics()
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "LPlayer"
        window.minSize = NSSize(width: 860, height: 550)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "LPlayer.WindowToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
        // Adding the native toolbar adjusts AppKit's stored frame limits.
        window.minSize = NSSize(width: 860, height: 550)
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.background
        window.delegate = self
        window.center()
        surface = PlayerSurface(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
        surface.autoresizingMask = [.width, .height]
        surface.onDrop = { [weak self] in self?.openURLs($0) }
        surface.onMovement = { [weak self] in self?.showControls() }
        surface.onMagnify = { [weak self] in self?.magnifyVideo($0) }
        surface.onSmartMagnify = { [weak self] in self?.smartMagnifyVideo($0) }
        surface.onPan = { [weak self] in self?.panVideo($0) ?? false }
        window.contentView = surface
        engine.videoView.frame = surface.bounds
        // The playback rectangle is explicitly laid out beside the help rail.
        engine.videoView.autoresizingMask = []
        surface.addSubview(engine.videoView)
        videoDoubleClick.numberOfClicksRequired = 2
        videoSingleClick.delegate = self
        engine.videoView.addGestureRecognizer(videoSingleClick)
        engine.videoView.addGestureRecognizer(videoDoubleClick)
        let overlays: [NSView] = [emptyState, mediaBadge, topBar, bottomBar, thumbnailPreview, hud, videoZoomHint, help, playlist, panel, errorBox]
        for view in overlays { surface.addSubview(view) }
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = Palette.chrome.cgColor
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = Palette.chrome.cgColor
        BrandTypography.applyWordmark(to: brand)
        [brand, fileTitle].forEach(topBar.addSubview)
        fileTitle.alignment = .center
        topBar.addSubview(topDivider); topBar.addSubview(toolbarDivider)
        brandMenuButton = symbolButton("chevron.down", label: L10n.text("LPlayer menu", "LPlayer 菜单"), target: self, action: #selector(showAppMenu))
        fileInfoButton = symbolButton("chevron.down", label: L10n.text("Video information", "视频信息"), target: self, action: #selector(showFileInformation))
        [brandMenuButton!, fileInfoButton!].forEach { button in
            button.image = button.image?.withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
            topBar.addSubview(button)
        }
        topOpenButton = symbolButton("folder", label: L10n.text("Open video or folder ⌘O", "打开视频或文件夹 ⌘O"), target: self, action: #selector(chooseFiles))
        topOpenButton.title = L10n.text("Open", "打开"); topOpenButton.imagePosition = .imageLeading
        topOpenButton.font = .systemFont(ofSize: 12); topOpenButton.imageHugsTitle = true
        helpButton = symbolButton("keyboard", label: L10n.text("Keyboard shortcuts V", "快捷键提醒 V"), target: self, action: #selector(toggleHelp))
        playlistButton = symbolButton("sidebar.right", label: L10n.text("Playlist T", "播放列表 T"), target: self, action: #selector(togglePlaylist))
        privateButton = NSButton(title: L10n.text("Private", "无痕"), target: self, action: #selector(togglePrivate))
        privateButton.isBordered = false; privateButton.font = .systemFont(ofSize: 11)
        [topOpenButton!, playlistButton!, privateButton!].forEach(topBar.addSubview)
        playButton = symbolButton("play.fill", label: L10n.text("Play / pause Space", "暂停或继续 Space"), target: self, action: #selector(togglePause))
        (playButton as? ChromeButton)?.treatment = .play
        playButton.contentTintColor = Palette.background
        backwardButton = symbolButton("gobackward.5", label: L10n.text("Back 5s A", "后退 5 秒 A"), target: self, action: #selector(backward))
        forwardButton = symbolButton("goforward.5", label: L10n.text("Forward 5s D", "前进 5 秒 D"), target: self, action: #selector(forward))
        previousVideoButton = symbolButton("backward.end.fill", label: ShortcutAction.previousFile.title, target: self, action: #selector(previousFile))
        nextVideoButton = symbolButton("forward.end.fill", label: ShortcutAction.nextFile.title, target: self, action: #selector(nextFile))
        fullscreenButton = symbolButton("arrow.up.left.and.arrow.down.right", label: L10n.text("Full screen F", "全屏 F"), target: self, action: #selector(fullscreen))
        subtitleButton = symbolButton("captions.bubble", label: L10n.text("Show / Hide subtitles", "显示 / 隐藏字幕"), target: self, action: #selector(toggleSubtitles))
        volumeButton = symbolButton("speaker.wave.2", label: L10n.text("Toggle mute", "静音"), target: self, action: #selector(toggleMute))
        speedButton = ChromeButton(title: "1×", target: self, action: #selector(showSpeedPanel)); speedButton.isBordered = false
        speedButton.font = .systemFont(ofSize: 12, weight: .medium)
        panelButton = symbolButton("slider.horizontal.3", label: L10n.text("Quick controls C", "快捷面板 C"), target: self, action: #selector(togglePanel))
        moreButton = symbolButton("ellipsis", label: L10n.text("More", "更多操作"), target: self, action: #selector(showMoreMenu))
        let controlViews: [NSView] = [previousVideoButton!, playButton!, backwardButton!, forwardButton!, nextVideoButton!, fullscreenButton!, subtitleButton!, volumeButton!, speedButton!, panelButton!, moreButton!, progress, volume, timeLabel, bottomDivider]
        for view in controlViews { bottomBar.addSubview(view) }
        // Keep the existing hit regions; draw compact hover/selection plates
        // and a smaller play circle inside those targets.
        for button in controlViews.compactMap({ $0 as? ChromeButton }) { button.visualInset = 2 }
        progress.cell = ChromeSliderCell(); progress.minValue = 0; progress.maxValue = 1
        progress.target = self; progress.action = #selector(scrub); progress.isContinuous = false
        progress.controlSize = .small; progress.setAccessibilityLabel(L10n.text("Playback position", "播放进度"))
        progress.onHover = { [weak self] time, point in self?.previewThumbnail(at: time, point: point) }
        progress.onHoverEnd = { [weak self] in self?.hideThumbnailPreview() }
        progress.onTrackingChange = { [weak self] tracking in
            guard let self else { return }
            self.showControls(scheduleHide: !tracking)
        }
        thumbnailPreview.isHidden = true
        volume.cell = ChromeSliderCell(); volume.minValue = 0; volume.maxValue = 100; volume.doubleValue = 70
        volume.target = self; volume.action = #selector(changeVolume); volume.isContinuous = true
        volume.controlSize = .small; volume.setAccessibilityLabel(L10n.text("Volume", "音量"))
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        hud.addSubview(hudLabel); hudLabel.alignment = .center
        hud.passesThroughEvents = true
        help.onClose = { [weak self] in self?.toggleHelp() }
        help.onOpenSettings = { [weak self] in self?.showShortcutEditor() }
        help.shortcuts = shortcuts
        playlist.onClose = { [weak self] in self?.togglePlaylist() }
        playlist.onActivate = { [weak self] index in self?.activatePlaylistSelection(index: index) }
        playlist.onSelectionChange = { [weak self] index in self?.playlistSelection = index; self?.writeDiagnostics() }
        playlist.onPreferredWidthChange = { [weak self] in self?.layoutWindow() }
        playlist.onOpenRequested = { [weak self] in self?.chooseFiles() }
        playlist.onHelpRequested = { [weak self] in self?.toggleHelp() }
        playlist.authorizePreviewURL = { [weak self] url in self?.fileAccess.authorizedURL(for: url) }
        hud.isHidden = true; videoZoomHint.isHidden = true; help.isHidden = true; playlist.isHidden = true; panel.isHidden = true; errorBox.isHidden = true
        emptyState.onOpen = { [weak self] in self?.chooseFiles() }
        emptyState.onDemo = { [weak self] in self?.openDemo() }
        mediaBadge.addSubview(mediaBadgeLabel); mediaBadge.passesThroughEvents = true
        panelCloseButton = symbolButton("xmark", label: L10n.text("Close quick controls", "关闭快捷调节"), target: self, action: #selector(togglePanel))
        panelSettingsButton = ChromeButton(title: L10n.text("Settings…", "设置…"), target: self, action: #selector(showSettings))
        panelSettingsButton.isBordered = false; panelSettingsButton.font = .systemFont(ofSize: 10.5)
        panelSettingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        panelSettingsButton.imagePosition = .imageTrailing; panelSettingsButton.contentTintColor = Palette.overlaySecondary
        panelHint.maximumNumberOfLines = 2; panelHint.lineBreakMode = .byWordWrapping
        let panelViews: [NSView] = [panelTitle, panelHint, panelScroll, panelCloseButton!, panelSettingsButton!, panelFooterLine]
        panelViews.forEach { panel.addSubview($0) }
        panelScroll.documentView = panelDocument; panelScroll.hasVerticalScroller = true
        panelScroll.drawsBackground = false; panelScroll.autohidesScrollers = true
        panelGroupLabels.forEach(panelDocument.addSubview); panelGroupLines.forEach(panelDocument.addSubview)
        errorBox.addSubview(errorTitle); errorBox.addSubview(errorMessage)
        errorMessage.maximumNumberOfLines = 3; errorMessage.lineBreakMode = .byWordWrapping
        updateQueueButtons()
        updateHandLabels()
        layoutWindow()
        observeTitlebarControls()
    }

    private func titlebarLeadingInset() -> CGFloat {
        var leading: CGFloat = 12
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            let buttonRect = topBar.convert(button.bounds, from: button)
            var visibleRect = buttonRect.intersection(topBar.bounds)
            var ancestor: NSView? = button
            while let view = ancestor, !visibleRect.isEmpty {
                if view.isHidden || view.alphaValue <= 0.01 {
                    visibleRect = .zero
                    break
                }
                visibleRect = visibleRect.intersection(topBar.convert(view.bounds, from: view))
                ancestor = view.superview
            }
            if !visibleRect.isEmpty { leading = max(leading, ceil(buttonRect.maxX) + 12) }
        }
        return leading
    }

    private func layoutTitlebar() {
        guard surface != nil else { return }
        let w = surface.bounds.width
        fileTitle.textColor = currentURL == nil ? Palette.muted : .white
        fileTitle.font = .systemFont(ofSize: 13, weight: currentURL == nil ? .regular : .medium)
        let leading = titlebarLeadingInset()
        let brandWidth = ceil(brand.fittingSize.width)
        let brandHeight = min(Self.topBarHeight - 4, max(18, ceil(brand.fittingSize.height)))
        brand.frame = NSRect(x: leading, y: floor((Self.topBarHeight - brandHeight) / 2), width: brandWidth, height: brandHeight)
        let chevronY = floor((Self.topBarHeight - 17) / 2)
        let buttonY = floor((Self.topBarHeight - 28) / 2)
        brandMenuButton.frame = NSRect(x: leading + brandWidth + 1, y: chevronY, width: 17, height: 17)
        let titleWidth = max(80, min(390, w - 2 * max(leading + brandWidth + 36, 190)))
        fileTitle.frame = NSRect(x: (w - titleWidth) / 2 - 8, y: floor((Self.topBarHeight - 21) / 2), width: titleWidth, height: 21)
        let measured = min(titleWidth, ceil(fileTitle.fittingSize.width))
        fileInfoButton.frame = NSRect(x: min(w / 2 + measured / 2 - 5, fileTitle.frame.maxX), y: chevronY, width: 16, height: 17)
        topOpenButton.frame = NSRect(x: w - 137, y: buttonY, width: 75, height: 28)
        playlistButton.frame = NSRect(x: w - 46, y: buttonY, width: 31, height: 28)
        privateButton.frame = NSRect(x: w - 202, y: floor((Self.topBarHeight - 25) / 2), width: 58, height: 25)
        toolbarDivider.frame = NSRect(x: w - 57, y: floor((Self.topBarHeight - 16) / 2), width: 1, height: 16)
        topDivider.frame = NSRect(x: 0, y: 0, width: w, height: 1)
    }

    private func observeTitlebarControls() {
        titlebarObservations.removeAll()
        var observed = Set<ObjectIdentifier>()
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            var ancestor: NSView? = window.standardWindowButton(type)
            while let view = ancestor {
                if observed.insert(ObjectIdentifier(view)).inserted {
                    titlebarObservations.append(view.observe(\.isHidden) { [weak self] _, _ in self?.scheduleTitlebarLayout() })
                    titlebarObservations.append(view.observe(\.alphaValue) { [weak self] _, _ in self?.scheduleTitlebarLayout() })
                    titlebarObservations.append(view.observe(\.frame) { [weak self] _, _ in self?.scheduleTitlebarLayout() })
                    titlebarObservations.append(view.observe(\.bounds) { [weak self] _, _ in self?.scheduleTitlebarLayout() })
                }
                ancestor = view.superview
            }
        }
    }

    private func scheduleTitlebarLayout() {
        guard !titlebarLayoutPending else { return }
        titlebarLayoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.titlebarLayoutPending = false
            if !self.terminated { self.layoutTitlebar() }
        }
    }

    private func layoutWindow() {
        guard surface != nil else { return }
        let w = surface.bounds.width, h = surface.bounds.height
        let topHeight = Self.topBarHeight
        let isFullscreen = window.styleMask.contains(.fullScreen)
        let hasMedia = currentURL != nil
        let bottomHeight: CGFloat = hasMedia ? Self.bottomBarHeight : 0
        let helpWidth = LPlayerShortcutHelpView.preferredWidth
        let sidebarOpen = !help.isHidden || !playlist.isHidden
        let sidebarWidth = playlist.isHidden ? helpWidth : playlist.sidebarWidth
        let playerWidth = max(1, w - (sidebarOpen && !isFullscreen ? sidebarWidth : 0))
        // Sidebars can cover the fullscreen picture, but must not cover
        // transport controls or their pointer and keyboard focus targets.
        let transportWidth = max(1, w - (sidebarOpen ? sidebarWidth : 0))
        // Fullscreen chrome floats over the picture. Fading the controls must
        // never leave their former layout space as black strips.
        let videoRect = isFullscreen ? NSRect(x: 0, y: 0, width: playerWidth, height: h)
            : NSRect(x: 0, y: bottomHeight, width: playerWidth, height: max(1, h - topHeight - bottomHeight))
        let overlayRect = NSRect(x: 0, y: bottomHeight, width: playerWidth, height: max(1, h - topHeight - bottomHeight))
        engine.videoView.frame = videoRect
        updateSubtitleSafeArea()
        let chromeColor = isFullscreen ? Palette.panel : Palette.chrome
        topBar.layer?.backgroundColor = chromeColor.cgColor
        bottomBar.layer?.backgroundColor = (isFullscreen ? Palette.transportOverlay : Palette.chrome).cgColor
        help.overlaysVideo = isFullscreen
        playlist.overlaysVideo = isFullscreen
        emptyState.frame = NSRect(x: 0, y: 0, width: playerWidth, height: h - topHeight)
        emptyState.isHidden = hasMedia
        bottomBar.isHidden = !hasMedia
        mediaBadge.isHidden = !hasMedia
        let badgeWidth = ceil(mediaBadgeLabel.fittingSize.width) + 22
        mediaBadge.frame = NSRect(x: 24, y: overlayRect.maxY - 53, width: badgeWidth, height: 27)
        mediaBadgeLabel.frame = NSRect(x: 11, y: 6, width: badgeWidth - 22, height: 16)
        updateVideoZoomPresentation()
        topBar.frame = NSRect(x: 0, y: h - topHeight, width: w, height: topHeight)
        bottomBar.frame = NSRect(x: 0, y: 0, width: transportWidth, height: Self.bottomBarHeight)
        layoutTitlebar()
        bottomDivider.frame = NSRect(x: 0, y: Self.bottomBarHeight - 1, width: transportWidth, height: 1)
        // A slim seek strip above one transport row. Its hit region stays
        // separate from the buttons, even when the sidebar narrows the bar.
        progress.frame = NSRect(x: 20, y: 42, width: max(1, transportWidth - 40), height: 14)
        volumeButton.frame = NSRect(x: 20, y: 8, width: 32, height: 32)
        volume.frame = NSRect(x: 60, y: 14, width: 68, height: 20)
        volume.isHidden = transportWidth < 700
        timeLabel.frame = NSRect(x: volume.isHidden ? 60 : 140, y: 16,
                                 width: transportWidth < 500 ? 34 : 120, height: 16)
        updatePlaybackTime(position: progress.doubleValue, duration: engine.snapshot.duration)
        let center = transportWidth / 2
        playButton.frame = NSRect(x: center - 18, y: 6, width: 36, height: 36)
        backwardButton.frame = NSRect(x: center - 62, y: 8, width: 32, height: 32)
        forwardButton.frame = NSRect(x: center + 30, y: 8, width: 32, height: 32)
        previousVideoButton.frame = NSRect(x: center - 102, y: 8, width: 32, height: 32)
        nextVideoButton.frame = NSRect(x: center + 70, y: 8, width: 32, height: 32)
        previousVideoButton.isHidden = transportWidth < 950; nextVideoButton.isHidden = transportWidth < 950
        speedButton.isHidden = transportWidth < 520
        subtitleButton.isHidden = transportWidth < 420
        panelButton.isHidden = transportWidth < 600
        fullscreenButton.isHidden = transportWidth < 420
        let trailingControls: [(NSButton, CGFloat)] = [(speedButton!, 40), (subtitleButton!, 32),
            (panelButton!, 32), (moreButton!, 32), (fullscreenButton!, 32)].filter { !$0.0.isHidden }
        let trailingWidth = trailingControls.reduce(CGFloat(0)) { $0 + $1.1 } + CGFloat(max(0, trailingControls.count - 1)) * 6
        var trailingX = transportWidth - 20 - trailingWidth
        for (button, width) in trailingControls {
            button.frame = NSRect(x: trailingX, y: 8, width: width, height: 32)
            trailingX += width + 6
        }
        hud.frame = NSRect(x: videoRect.midX - 165, y: h - topHeight - 72, width: 330, height: 52)
        hudLabel.frame = NSRect(x: 12, y: 15, width: 306, height: 23)
        help.frame = NSRect(x: w - helpWidth, y: 0, width: helpWidth, height: h - topHeight)
        playlist.frame = NSRect(x: w - playlist.sidebarWidth, y: 0, width: playlist.sidebarWidth, height: h - topHeight)
        let panelWidth: CGFloat = playerWidth < 900 ? 306 : 318
        let aspect = engine.snapshot.videoDisplayAspect ?? (16.0 / 9.0)
        let letterbox = aspect > 0 ? max(0, (overlayRect.height - playerWidth / aspect) / 2) : 0
        let subtitleBand = min(max(80, letterbox + 90), max(80, overlayRect.height - 194))
        let ph = max(180, min(454, overlayRect.height - subtitleBand - 14))
        panel.frame = NSRect(x: overlayRect.maxX - panelWidth - 18, y: overlayRect.minY + subtitleBand, width: panelWidth, height: ph)
        panelTitle.frame = NSRect(x: 18, y: ph - 39, width: panelWidth - 70, height: 20)
        panelCloseButton.frame = NSRect(x: panelWidth - 42, y: ph - 41, width: 27, height: 27)
        panelScroll.frame = NSRect(x: 11, y: 46, width: panelWidth - 22, height: max(1, ph - 99))
        panelFooterLine.frame = NSRect(x: 17, y: 41, width: panelWidth - 34, height: 1)
        panelHint.frame = NSRect(x: 18, y: 5, width: panelWidth - 110, height: 32)
        panelSettingsButton.frame = NSRect(x: panelWidth - 86, y: 9, width: 71, height: 25)
        layoutPanelRows()
        errorBox.frame = NSRect(x: videoRect.midX - min(250, (playerWidth - 32) / 2), y: videoRect.midY - 75, width: min(500, playerWidth - 32), height: 150)
        errorTitle.frame = NSRect(x: 24, y: 103, width: errorBox.bounds.width - 48, height: 26)
        errorMessage.frame = NSRect(x: 24, y: 22, width: errorBox.bounds.width - 48, height: 72)
    }

    private func configureEngine() {
        engine.onUpdate = { [weak self] state in self?.update(state) }
        engine.onSeekStateChange = { [weak self] active in
            guard let self else { return }
            self.updatePlaylistPreviewPriority()
            if active { self.hideThumbnailPreview(scheduleHide: false) }
            else { self.resumeHoveredThumbnail() }
        }
        engine.onVideoZoomChange = { [weak self] scale in
            guard let self else { return }
            let scaleChanged = abs(scale - self.lastVideoZoomScale) > 0.001
            self.lastVideoZoomScale = scale
            self.updateVideoZoomPresentation()
            if scaleChanged && !self.isZooming { self.showControls() }
            if scaleChanged && !self.panel.isHidden { self.refreshPanel(force: true) }
            if !self.isZooming { self.writeDiagnostics() }
        }
        engine.onFileLoaded = { [weak self] in
            guard let self else { return }
            guard self.engine.snapshot.mediaPath == self.currentURL?.path else { return }
            self.fileReady = true
            self.playbackError = nil
            self.playbackFailureReason = nil
            self.errorBox.isHidden = true
            self.updatePlaylistPreviewPriority()
            self.applyAutomaticSubtitles(self.automaticSubtitleURLs)
            self.automaticSubtitleURLs = []
            if self.pendingSubtitleTarget == self.currentURL?.path {
                for url in self.pendingSubtitleURLs { self.addSubtitle(url, flags: "cached") }
            }
            self.pendingSubtitleURLs = []
            self.pendingSubtitleTarget = nil
            self.engine.setDouble("volume", self.globalVolume)
            if let entry = self.pendingRestore {
                if !self.editedControlsDuringLoad.contains("speed") { self.engine.setDouble("speed", entry.speed) }
                if !self.editedControlsDuringLoad.contains("sub-delay") { self.engine.setDouble("sub-delay", entry.subtitleDelay) }
                if !self.editedControlsDuringLoad.contains("sub-visibility") { self.engine.setFlag("sub-visibility", entry.subtitlesVisible) }
                if !self.editedControlsDuringLoad.contains("aid"), let id = entry.audioID { self.engine.setString("aid", String(id)) }
                if !self.editedControlsDuringLoad.contains("sid"), let id = entry.subtitleID { self.engine.setString("sid", String(id)) }
                self.pendingRestore = nil
                if entry.position > 3 && entry.position < entry.duration - 2 { self.showHUD(L10n.text("Resuming · \(clockText(entry.position))", "继续观看 · \(clockText(entry.position))")) }
            }
            self.showControls()
        }
        engine.onEndFile = { [weak self] natural, error in
            guard let self else { return }
            guard self.engine.snapshot.mediaPath == self.currentURL?.path else { return }
            if let error {
                self.hideThumbnailPreview()
                self.playbackError = error
                self.playbackFailureReason = self.engine.failureReason
                self.refreshPlaybackError()
                self.errorBox.isHidden = false; self.updatePlaylistPreviewPriority(); self.showControls()
            } else if natural {
                self.saveProgress()
                // A user-selected folder may still be enumerating. Keep its
                // pending open ahead of the previous queue's automatic next.
                if self.pendingExplicitQueueOpen != nil {
                    self.finished = true
                    self.engine.setFlag("pause", true)
                    self.showControls()
                    return
                }
                if self.queueIndex + 1 < self.queue.count { self.loadIndex(self.queueIndex + 1) }
                else { self.finished = true; self.engine.setFlag("pause", true); self.showHUD(L10n.text("Finished · Space to replay", "已播放完毕 · 空格重播")) }
            }
        }
    }

    private func updatePlaybackTime(position: Double, duration: Double) {
        let elapsed = clockText(position), total = clockText(duration)
        let text = bottomBar.bounds.width < 500 ? elapsed : elapsed + " / " + total
        if timeLabel.stringValue != text { timeLabel.stringValue = text }
        let description = L10n.format("Playback time · %@ / %@", "播放时间 · %@ / %@", elapsed, total)
        if timeLabel.toolTip != description {
            timeLabel.toolTip = description
            timeLabel.setAccessibilityLabel(description)
        }
    }

    private func update(_ state: EngineSnapshot) {
        let previous = lastPresentedState
        if previous?.videoDisplayAspect != state.videoDisplayAspect { layoutWindow() }
        let labelsChanged = lastPresentationLanguage != L10n.language
        updatePlaylistPreviewPriority()
        let displayPosition = (state.seeking || seekScheduler.hasPending || Date().timeIntervalSince(lastSeekDate) < 0.15)
            ? (seekTarget ?? state.position) : state.position
        if !progress.isTracking {
            let maximum = max(1, state.duration)
            if progress.maxValue != maximum { progress.maxValue = maximum }
            if progress.doubleValue != displayPosition { progress.doubleValue = displayPosition }
        }
        updatePlaybackTime(position: displayPosition, duration: state.duration)
        if let currentURL, state.duration > 0 { playlist.updateDuration(state.duration, for: currentURL) }
        let shownVolume = globalVolume
        if volume.doubleValue != shownVolume { volume.doubleValue = shownVolume }
        if previous?.speed != state.speed { speedButton.title = String(format: "%g×", speedTarget ?? state.speed) }
        if previous?.paused != state.paused || labelsChanged {
            playButton.image = NSImage(systemSymbolName: state.paused ? "play.fill" : "pause.fill", accessibilityDescription: state.paused ? L10n.text("Play", "继续播放") : L10n.text("Pause", "暂停播放"))?.withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))
        }
        if previous?.subtitlesVisible != state.subtitlesVisible {
            subtitleButton.contentTintColor = state.subtitlesVisible ? Palette.accent : Palette.muted
            (subtitleButton as? ChromeButton)?.active = state.subtitlesVisible
        }
        lastPresentedState = state
        lastPresentationLanguage = L10n.language
        if currentURL != nil && Date().timeIntervalSince(lastSaved) > 3 { saveProgress() }
        if !panel.isHidden { refreshPanel() }
        if state.paused && previous?.paused != true { showControls(scheduleHide: false) }
        writeDiagnostics()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        application(sender, open: urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Capture the original Finder URLs while their implicit scope is
        // available, including events delivered before the engine is ready.
        if engine == nil { pendingOpen += fileAccess.rememberSelection(urls, persist: !store.isPrivate) }
        else { openURLs(urls) }
    }

    private func openURLs(_ urls: [URL], userSelected: Bool = true) {
        let authorized = userSelected
            ? fileAccess.rememberSelection(urls, persist: !store.isPrivate)
            : urls.compactMap { fileAccess.authorizedURL(for: $0) }
        guard !authorized.isEmpty else {
            showHUD(L10n.text("Select the file again with ⌘O to allow access", "请按 ⌘O 重新选择文件以允许访问"))
            return
        }
        let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "sup"]
        let subtitleFiles = authorized.filter { subtitleExtensions.contains($0.pathExtension.lowercased()) }
        let mediaInputs = authorized.filter { !subtitleExtensions.contains($0.pathExtension.lowercased()) }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(surface)
        if fileAccess.couldNotPersistSelection {
            showHUD(L10n.text("Access works now · Select the file again next launch", "本次可访问 · 下次启动需重新选择文件"))
        }
        guard !mediaInputs.isEmpty else {
            if currentURL != nil && fileReady {
                for url in subtitleFiles { addSubtitle(url, flags: "cached") }
                if !subtitleFiles.isEmpty { showHUD(L10n.text("Subtitles loaded: \(subtitleFiles.count)", "已载入字幕 · \(subtitleFiles.count) 个")) }
            } else if currentURL != nil {
                pendingSubtitleURLs += subtitleFiles; pendingSubtitleTarget = currentURL?.path
                automaticSubtitleMaySelect = false
                pendingAutomaticSubtitleID = nil
                editedControlsDuringLoad.insert("sid")
            } else if !subtitleFiles.isEmpty {
                showHUD(L10n.text("Open a video before adding subtitles", "请先打开视频，再拖入字幕"))
            }
            return
        }
        mediaRequestID &+= 1
        pendingExplicitQueueOpen = nil
        mediaDiscovery.cancelQueue()
        // Start an explicitly selected video immediately. Its folder can be
        // large or on a slow drive; discovery must not delay its first frame.
        if mediaInputs.count == 1, let selected = mediaInputs.first?.standardizedFileURL, LibraryStore.isVideoURL(selected),
           (try? selected.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            fileAccess.preparePlaylistDirectory(for: selected)
            pendingSubtitleURLs = subtitleFiles
            pendingSubtitleTarget = selected.path
            queue = [selected]
            loadIndex(0)
            let request = mediaRequestID
            mediaDiscovery.discoverQueue(from: mediaInputs, access: fileAccess.readSnapshot()) { [weak self] initial in
                guard let self, self.mediaRequestID == request, self.currentURL == selected,
                      !initial.urls.isEmpty else { return }
                self.queue = initial.urls; self.queueIndex = initial.index; self.playlistSelection = initial.index
                self.fileTitle.stringValue = selected.deletingPathExtension().lastPathComponent
                self.refreshPlaylist(); self.updateQueueButtons(); self.refreshPanel()
                self.writeDiagnostics()
                if self.finished && initial.index + 1 < self.queue.count { self.loadIndex(initial.index + 1) }
            }
            return
        }
        let request = mediaRequestID
        pendingExplicitQueueOpen = request
        mediaDiscovery.discoverQueue(from: mediaInputs, access: fileAccess.readSnapshot()) { [weak self] initial in
            guard let self, self.mediaRequestID == request else { return }
            self.pendingExplicitQueueOpen = nil
            guard !initial.urls.isEmpty else {
                self.showHUD(L10n.text("No playable videos found", "没有找到可播放的视频")); return
            }
            self.pendingSubtitleURLs = subtitleFiles
            self.pendingSubtitleTarget = initial.urls[initial.index].path
            self.queue = initial.urls
            self.loadIndex(initial.index)
        }
    }

    private func loadIndex(_ index: Int, resume: Bool = true) {
        guard queue.indices.contains(index) else { return }
        saveProgress()
        seekScheduler.cancel(); seekTarget = nil; undoPosition = nil
        lastSeekDate = .distantPast
        thumbnailResumeWork?.cancel(); thumbnailPauseUntil = .distantPast
        guard let url = fileAccess.authorizedURL(for: queue[index]) else {
            showHUD(L10n.text("File access expired · Select it again with ⌘O", "文件访问权限已失效 · 请按 ⌘O 重新选择"))
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            showHUD(L10n.text("File unavailable · Check its location", "文件暂时不可用 · 检查外置硬盘或文件位置"))
            return
        }
        mediaRequestID &+= 1; subtitleRequestID &+= 1
        pendingExplicitQueueOpen = nil
        mediaDiscovery.cancelAll()
        speedTarget = nil; subtitleDelayTarget = nil
        for name in ["speed", "sub-delay"] { controlRevisions[name, default: 0] &+= 1 }
        editedControlsDuringLoad.removeAll(keepingCapacity: true)
        currentFolderAccess = fileAccess.hasDirectoryAccess(to: url.deletingLastPathComponent())
        playlist.stopMotionPreview()
        fileReady = false; finished = false; isZooming = false
        cancelVideoPan()
        updateVideoZoomPresentation()
        loadedSubtitlePaths.removeAll()
        playlist.setPreviewsSuspended(true)
        hideThumbnailPreview(scheduleHide: false)
        thumbnailGenerator.reset()
        queueIndex = index; currentURL = url
        playlistSelection = index
        refreshPlaylist()
        if pendingSubtitleTarget != url.path { pendingSubtitleURLs = []; pendingSubtitleTarget = nil }
        automaticSubtitleURLs = []
        pendingRestore = store.isPrivate || !resume ? nil : store.entry(for: url)
        automaticSubtitleMaySelect = pendingRestore?.subtitleID == nil && pendingSubtitleURLs.isEmpty
        pendingAutomaticSubtitleID = pendingSubtitleURLs.isEmpty ? pendingRestore?.subtitleID : nil
        if !pendingSubtitleURLs.isEmpty { editedControlsDuringLoad.insert("sid") }
        let entry = pendingRestore
        let start = (entry != nil && entry!.position < entry!.duration - 2) ? entry!.position : 0
        errorBox.isHidden = true
        fileTitle.stringValue = url.deletingPathExtension().lastPathComponent
        mediaBadgeLabel.stringValue = url.deletingLastPathComponent().lastPathComponent == "Demo" ? L10n.text("DEMO FILM", "演示影片") : url.pathExtension.uppercased() + L10n.text(" · Local", " · 本地影片")
        window.title = "\(url.lastPathComponent) — LPlayer"
        window.representedURL = url
        engine.setDouble("sub-delay", 0)
        engine.setFlag("sub-visibility", true)
        engine.setString("sid", "auto"); engine.setString("aid", "auto")
        // The app performs authorized, filtered subtitle discovery. mpv must
        // not scan arbitrary sibling paths or follow subtitle symlinks itself.
        engine.setString("sub-auto", "no")
        engine.load(url, start: start)
        engine.setFlag("pause", false)
        discoverSubtitles(for: url)
        lastSaved = Date()
        updateQueueButtons()
        layoutWindow()
        refreshPanel(force: true)
        showControls()
    }

    private func discoverSubtitles(for video: URL) {
        subtitleRequestID &+= 1
        let request = subtitleRequestID
        let explicitPaths = Set(pendingSubtitleURLs.map { $0.standardizedFileURL.path })
        mediaDiscovery.discoverSubtitles(for: video, access: fileAccess.readSnapshot()) { [weak self] urls in
            guard let self, self.subtitleRequestID == request, self.currentURL == video else { return }
            let automatic = urls.filter { !explicitPaths.contains($0.standardizedFileURL.path) }
            if self.fileReady { self.applyAutomaticSubtitles(automatic) }
            else { self.automaticSubtitleURLs = automatic }
        }
    }

    private func applyAutomaticSubtitles(_ urls: [URL]) {
        for url in urls { addSubtitle(url, flags: "auto") }
        if !urls.isEmpty, let id = pendingAutomaticSubtitleID {
            // The saved external track may not exist until this worker result.
            // Manual choices clear this pending restoration before it arrives.
            engine.setString("sid", String(id))
            pendingAutomaticSubtitleID = nil
        }
        if automaticSubtitleMaySelect, let preferred = LibraryStore.preferredSubtitle(in: urls, languages: L10n.mediaPreferredLanguages + ["en"]) {
            addSubtitle(preferred, flags: "cached")
        }
    }

    private func addSubtitle(_ url: URL, flags: String) {
        if flags != "auto" { automaticSubtitleMaySelect = false; pendingAutomaticSubtitleID = nil }
        let path = url.standardizedFileURL.path
        if flags == "auto", loadedSubtitlePaths.contains(path) { return }
        loadedSubtitlePaths.insert(path)
        engine.command(["sub-add", url.path, flags, url.deletingPathExtension().lastPathComponent, LibraryStore.subtitleLanguage(for: url)])
    }

    private func saveProgress() {
        guard let url = currentURL, engine != nil, fileReady, engine.snapshot.mediaPath == url.path else { return }
        let state = engine.snapshot
        guard state.duration > 0 else { return }
        store.save(PlaybackBookmark(path: url.path, name: url.lastPathComponent, position: state.position, duration: state.duration, speed: speedTarget ?? state.speed, volume: globalVolume, subtitleDelay: subtitleDelayTarget ?? state.subtitleDelay, subtitleID: state.tracks.first { $0.type == "sub" && $0.selected }?.id, audioID: state.tracks.first { $0.type == "audio" && $0.selected }?.id, updatedAt: Date(), subtitlesVisible: state.subtitlesVisible))
        lastSaved = Date()
        refreshRecentMenu()
    }

    private func seek(by delta: Double) {
        guard fileReady, currentURL != nil, engine.snapshot.duration > 0 else { return }
        let now = Date()
        if seekTarget == nil || (now.timeIntervalSince(lastSeekDate) > 0.45 && !engine.snapshot.seeking && !seekScheduler.hasPending) {
            undoPosition = engine.snapshot.position; seekTarget = nil
        }
        let base = seekTarget ?? engine.snapshot.position
        let target = max(0, min(engine.snapshot.duration - 0.05, base + delta))
        seekTarget = target; lastSeekDate = now
        seekScheduler.request(target)
        showSeekProgress(at: target)
    }

    private func showSeekProgress(at target: Double) {
        progress.doubleValue = target
        updatePlaybackTime(position: target, duration: engine.snapshot.duration)
        showControls()
    }

    private func submitSeek(to target: Double) {
        hideThumbnailPreview(scheduleHide: false)
        thumbnailGenerator.suspend()
        playlist.setPreviewsSuspended(true)
        thumbnailPauseUntil = Date(timeIntervalSinceNow: 0.25)
        thumbnailResumeWork?.cancel()
        let resume = DispatchWorkItem { [weak self] in self?.resumeHoveredThumbnail() }
        thumbnailResumeWork = resume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: resume)
        engine.seek(to: target)
    }

    private func resumeHoveredThumbnail() {
        updatePlaylistPreviewPriority()
        guard !terminated, window.isKeyWindow, !engine.snapshot.seeking,
              Date() >= thumbnailPauseUntil, let point = progress.hoverPoint else { return }
        if let time = progress.hoverTime(at: point) { previewThumbnail(at: time, point: point) }
    }

    private func updatePlaylistPreviewPriority() {
        guard engine != nil else { return }
        let loading = currentURL != nil && !fileReady && errorBox.isHidden && !finished
        playlist.setPreviewsSuspended(terminated || loading || engine.snapshot.seeking || seekScheduler.hasPending || Date() < thumbnailPauseUntil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard NSApp.keyWindow === window else { return false }
        guard event.window === window else { return false }
        guard window.attachedSheet == nil else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        guard let chord = KeyChord(event: event) else { return false }
        // Visible modes own their fixed navigation keys. Playlist and Quick
        // Controls are mutually exclusive, so confirmation cannot silently
        // transfer the same one-hand keys to playback.
        let context: ShortcutContext = !playlist.isHidden ? .playlist : (!panel.isHidden ? .panel : .playback)
        guard let command = shortcuts.command(for: chord, hand: hand, context: context) else { return false }
        if event.isARepeat {
            switch command { case .seek, .volume, .speed, .zoom, .subtitleDelay, .panelMove, .panelAdjust, .playlistMove: break; default: return true }
        }
        perform(command)
        return true
    }

    private func perform(_ command: PlayerCommand) {
        switch command {
        case .togglePause: togglePause()
        case .seek(let value): seek(by: value)
        case .volume(let value): setVolume(globalVolume + value)
        case .speed(let value): setSpeed((speedTarget ?? engine.snapshot.speed) + value)
        case .resetSpeed: setSpeed(1)
        case .resetZoom: resetVideoZoom()
        case .previousFile: previousFile()
        case .nextFile: nextFile()
        case .fullscreen: fullscreen()
        case .subtitles: toggleSubtitles()
        case .mute: toggleMute()
        case .openFiles: chooseFiles()
        case .privatePlayback: togglePrivate()
        case .customizeShortcuts: showShortcutEditor()
        case .zoom(let delta):
            adjustVideoZoom(by: delta)
        case .subtitleDelay(let delta):
            setSubtitleDelay((subtitleDelayTarget ?? engine.snapshot.subtitleDelay) + delta)
        case .cycleTrack(let type): cycleTrack(type, delta: 1)
        case .undoSeek:
            if let target = undoPosition {
                let before = engine.snapshot.position; seekScheduler.cancel(); seekTarget = target
                lastSeekDate = Date()
                submitSeek(to: target); undoPosition = before
                showSeekProgress(at: target)
            } else { showHUD(L10n.text("No seek to undo yet", "还没有可撤销的跳转")) }
        case .panel: togglePanel()
        case .help: toggleHelp()
        case .playlist: togglePlaylist()
        case .playlistMove(let delta): movePlaylistSelection(by: delta)
        case .playlistBoundary(let last): selectPlaylist(index: last ? queue.count - 1 : 0)
        case .playlistActivate: activatePlaylistSelection(index: playlistSelection)
        case .escape:
            if !panel.isHidden { panel.isHidden = true; showControls() }
            else if !help.isHidden { setHelpVisible(false); showControls() }
            else if !playlist.isHidden { setPlaylistVisible(false); showControls() }
            else if window.styleMask.contains(.fullScreen) { fullscreen() }
        case .panelMove(let delta):
            guard !panelItems.isEmpty else { return }
            let count = panelItems.count + 1 // the fixed Settings footer is navigable too
            selectedItem = (selectedItem + delta + count) % count
            updatePanelSelection()
        case .panelAdjust(let delta):
            guard panelItems.indices.contains(selectedItem) else { return }
            panelItems[selectedItem].adjust?(delta); refreshPanel(force: true)
        case .panelActivate:
            if selectedItem == panelItems.count { showSettings(); return }
            guard panelItems.indices.contains(selectedItem) else { return }
            panelItems[selectedItem].action(); refreshPanel(force: true)
        }
        writeDiagnostics()
    }

    private func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        let value = max(0, min(100, value))
        globalVolume = value
        UserDefaults.standard.set(value, forKey: "playbackVolume")
        volume.doubleValue = value
        setPlaybackControl("volume", value)
        engine.setFlag("mute", false)
        showHUD(L10n.text("Volume  \(Int(value))%", "音量  \(Int(value))%"))
    }

    private func setSpeed(_ value: Double) {
        guard value.isFinite else { return }
        let value = max(0.25, min(3, (value * 100).rounded() / 100))
        speedTarget = value
        if !fileReady { editedControlsDuringLoad.insert("speed") }
        speedButton.title = String(format: "%g×", value)
        setPlaybackControl("speed", value)
        showHUD(L10n.format("Speed  %g×", "播放速度  %g×", value))
    }

    private func setSubtitleDelay(_ value: Double) {
        guard value.isFinite else { return }
        subtitleDelayTarget = value
        if !fileReady { editedControlsDuringLoad.insert("sub-delay") }
        setPlaybackControl("sub-delay", value)
        showHUD(L10n.format("Subtitle delay  %+.1fs", "字幕延迟  %+.1f 秒", value))
    }

    private func setPlaybackControl(_ name: String, _ value: Double) {
        controlRevisions[name, default: 0] &+= 1
        let revision = controlRevisions[name]!
        engine.setDouble(name, value) { [weak self] _ in
            guard let self, self.controlRevisions[name] == revision else { return }
            // This acknowledgment follows the engine's observed publication.
            // An arbitrary old snapshot equal to the target cannot clear it.
            switch name {
            case "speed": self.speedTarget = nil
            case "sub-delay": self.subtitleDelayTarget = nil
            default: break
            }
            self.update(self.engine.snapshot)
        }
    }

    private func previewThumbnail(at time: Double, point: NSPoint) {
        guard fileReady, let url = currentURL, engine.snapshot.duration.isFinite,
              engine.snapshot.duration > 0, time.isFinite, errorBox.isHidden,
              help.isHidden, panel.isHidden, window.attachedSheet == nil,
              !engine.snapshot.seeking, Date() >= thumbnailPauseUntil,
              engine.snapshot.tracks.contains(where: { $0.type == "video" && $0.selected }) else {
            hideThumbnailPreview(); return
        }
        let target = max(0, min(engine.snapshot.duration - 0.05, time))
        thumbnailHoverTime = target
        positionThumbnailPreview(at: point)
        thumbnailPreview.isHidden = false
        showControls(scheduleHide: false)
        let bucket = Int(floor(target))
        guard thumbnailBucket != bucket else { return }
        thumbnailBucket = bucket
        thumbnailRequestID &+= 1
        let request = thumbnailRequestID
        thumbnailReady = false
        thumbnailPreview.setPreview(time: target, image: thumbnailImage, state: .loading)
        thumbnailGenerator.request(url: url, time: target) { [weak self] result in
            guard let self, self.thumbnailRequestID == request,
                  self.thumbnailHoverTime != nil, self.currentURL == url else { return }
            self.thumbnailReady = result != nil
            self.thumbnailImage = result?.image
            self.thumbnailPreview.setPreview(time: self.thumbnailHoverTime ?? target, image: result?.image,
                                             state: result == nil ? .unavailable : .ready)
            self.writeDiagnostics()
        }
        writeDiagnostics()
    }

    private func positionThumbnailPreview(at point: NSPoint) {
        let anchor = progress.convert(point, to: surface)
        let size = ThumbnailPreviewView.preferredSize
        let x = max(14, min(bottomBar.bounds.width - size.width - 14, anchor.x - size.width / 2))
        let topOfTrack = progress.convert(NSPoint(x: point.x, y: progress.bounds.maxY), to: surface).y
        thumbnailPreview.frame = NSRect(x: x, y: topOfTrack + 8, width: size.width, height: size.height)
        thumbnailPreview.pointerX = anchor.x - x
    }

    private func hideThumbnailPreview(scheduleHide: Bool = true) {
        let wasVisible = thumbnailHoverTime != nil
        thumbnailRequestID &+= 1
        thumbnailHoverTime = nil; thumbnailBucket = nil; thumbnailReady = false; thumbnailImage = nil
        thumbnailPreview.isHidden = true
        thumbnailPreview.setPreview(time: 0, image: nil, state: .loading)
        thumbnailGenerator.cancel()
        if wasVisible && scheduleHide { showControls() }
        writeDiagnostics()
    }

    private var canTransformVideo: Bool {
        guard fileReady, !finished, errorBox.isHidden, panel.isHidden,
              engine.snapshot.tracks.contains(where: { $0.type == "video" && $0.selected }),
              window.attachedSheet == nil else { return false }
        return true
    }

    private func canZoomVideo(at point: NSPoint) -> Bool {
        guard canTransformVideo else { return false }
        return surface.hitTest(surface.convert(point, from: nil)) === engine.videoView
    }

    private func updateVideoZoomPresentation() {
        guard surface != nil, engine != nil else { return }
        let visible = canTransformVideo && engine.videoZoomScale > 1.001
        let zoomKeys = shortcutLabel(.zoomOut) + " / " + shortcutLabel(.zoomIn)
        let presentation = ZoomPresentation(visible: visible, scale: engine.videoZoomScale,
            videoFrame: engine.videoView.frame, surfaceSize: surface.bounds.size,
            resetKey: shortcutLabel(.resetZoom), zoomKeys: zoomKeys, language: L10n.language, panning: isPanningVideo)
        guard presentation != zoomPresentation else { return }
        zoomPresentation = presentation
        videoZoomHint.isHidden = !visible
        if visible {
            videoZoomHint.refresh(scale: engine.videoZoomScale, resetKey: shortcutLabel(.resetZoom), zoomKeys: zoomKeys)
            let video = engine.videoView.frame
            let safeArea = NSRect(x: 0, y: Self.bottomBarHeight, width: surface.bounds.width,
                                  height: max(0, surface.bounds.height - Self.topBarHeight - Self.bottomBarHeight))
            let available = video.intersection(safeArea)
            videoZoomHint.frame = NSRect(x: available.minX + 12, y: available.minY + 10,
                width: min(videoZoomHint.preferredWidth, max(0, available.width - 24)), height: 30)
            surface.videoPanCursorRect = available
        } else {
            surface.videoPanCursorRect = nil
        }
        surface.isVideoPanCursorClosed = isPanningVideo
    }

    private func magnifyVideo(_ event: NSEvent) {
        cancelVideoPan()
        if event.phase.contains(.began) {
            isZooming = canZoomVideo(at: event.locationInWindow)
            if isZooming {
                showControls(scheduleHide: false)
                engine.beginVideoZoom(at: engine.videoView.convert(event.locationInWindow, from: nil))
            }
        }
        // Some drivers deliver an unphased magnify event. Treat it as one
        // complete gesture, while phased gestures keep their original anchor.
        let standalone = event.phase.isEmpty
        if standalone { isZooming = canZoomVideo(at: event.locationInWindow) }
        if isZooming {
            if event.phase.contains(.cancelled) {
                engine.endVideoZoom()
            } else {
                engine.updateVideoZoom(magnification: Double(event.magnification), at: engine.videoView.convert(event.locationInWindow, from: nil))
            }
        }
        if standalone || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            engine.endVideoZoom(); isZooming = false
            showControls(); writeDiagnostics()
        }
    }

    private func smartMagnifyVideo(_ event: NSEvent) {
        guard canZoomVideo(at: event.locationInWindow) else { return }
        cancelVideoPan()
        isZooming = false
        if engine.videoZoomScale > 1.001 { engine.resetVideoZoom() }
        else { engine.setVideoZoomScale(2, at: engine.videoView.convert(event.locationInWindow, from: nil)) }
    }

    @objc private func zoomIn() { adjustVideoZoom(by: 0.25) }
    @objc private func zoomOut() { adjustVideoZoom(by: -0.25) }

    private func adjustVideoZoom(by delta: Double) {
        guard fileReady, engine.snapshot.tracks.contains(where: { $0.type == "video" && $0.selected }) else { return }
        isZooming = false
        cancelVideoPan()
        engine.setVideoZoomScale(engine.videoZoomScale + delta)
        showHUD(L10n.format("Video zoom  %.0f%%", "画面缩放  %.0f%%", engine.videoZoomScale * 100))
        writeDiagnostics()
    }

    @objc private func resetVideoZoom() {
        isZooming = false
        cancelVideoPan()
        engine.resetVideoZoom()
        if fileReady { showHUD(L10n.text("Fit to window", "画面已复原 · 适应窗口")) }
    }

    private func cancelVideoPan() {
        isPanningVideo = false
        allowsVideoPanMomentum = false
        surface?.isVideoPanCursorClosed = false
    }

    private func panVideo(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas, engine.videoZoomScale > 1,
              !isZooming, canTransformVideo else {
            cancelVideoPan()
            return false
        }
        let phase = event.phase, momentum = event.momentumPhase
        if phase.contains(.cancelled) || momentum.contains(.cancelled) {
            let owned = isPanningVideo || allowsVideoPanMomentum
            cancelVideoPan()
            if owned { showControls() }
            return owned
        }
        if !momentum.isEmpty {
            guard allowsVideoPanMomentum else { return false }
            // Moving an enlarged picture is direct manipulation. Consume the
            // owned inertia without moving, so lifting fingers stops the crop.
            if momentum.contains(.ended) { cancelVideoPan() }
            return true
        }
        if phase.contains(.mayBegin) {
            cancelVideoPan()
            return false
        }
        if phase.contains(.began) {
            guard canZoomVideo(at: event.locationInWindow) else { cancelVideoPan(); return false }
            isPanningVideo = true
            allowsVideoPanMomentum = false
            surface.isVideoPanCursorClosed = true
            showControls(scheduleHide: false)
        }
        // Drivers without phases deliver individual precise scroll events.
        // A changed event cannot take ownership of a gesture begun in a panel.
        let standalone = phase.isEmpty
        if standalone && !isPanningVideo && !canZoomVideo(at: event.locationInWindow) { return false }
        guard isPanningVideo || standalone else { return false }
        // Always move the picture with the fingers, including when the system
        // scroll-bar preference reverses deltas. Keep gain independent of zoom
        // and Retina scaling; these values are already view points.
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let gain = direction * CGFloat(videoPanSensitivity)
        engine.panVideo(by: NSPoint(x: event.scrollingDeltaX * gain, y: -event.scrollingDeltaY * gain))
        if phase.contains(.ended) {
            isPanningVideo = false
            allowsVideoPanMomentum = true
            surface.isVideoPanCursorClosed = false
            showControls()
        } else if standalone {
            cancelVideoPan()
            showControls()
        }
        return true
    }

    private func setVideoPanSensitivity(_ proposed: Double) {
        guard proposed.isFinite else { return }
        videoPanSensitivity = min(1.5, max(0.25, proposed))
        UserDefaults.standard.set(videoPanSensitivity, forKey: "videoPanSensitivity")
        showHUD(L10n.format("Pan sensitivity  %.0f%%", "拖动灵敏度  %.0f%%", videoPanSensitivity * 100))
    }

    @objc private func chooseFiles() {
        guard window.attachedSheet == nil else { return }
        cancelVideoPan()
        hideThumbnailPreview(scheduleHide: false)
        let picker = NSOpenPanel()
        picker.title = L10n.text("Open Videos, Folders or Subtitles", "打开视频、文件夹或字幕")
        picker.prompt = L10n.text("Open", "打开")
        picker.message = fileAccess.requiresExplicitDirectorySelection
            ? L10n.text("Select a video to play it. Select its folder to also load nearby videos and matching subtitles.", "选择视频即可播放。选择所在文件夹后，还可读取同目录视频和匹配的外挂字幕。")
            : L10n.text("Opening one video loads all videos in its folder. Select multiple files to make a custom playlist.", "打开一个视频即可自动加载同目录的所有视频；多选文件可按选择顺序组成播放列表。")
        picker.canChooseFiles = true; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        picker.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.openURLs(picker.urls) }
            self?.window.makeFirstResponder(self?.surface)
            self?.showControls()
        }
        updateVideoZoomPresentation()
    }

    @objc private func allowFolderAccess() {
        cancelVideoPan()
        guard window.attachedSheet == nil else { return }
        hideThumbnailPreview(scheduleHide: false)
        let picker = NSOpenPanel()
        picker.title = L10n.text("Allow Folder Access", "允许访问文件夹")
        picker.prompt = L10n.text("Allow Access", "允许访问")
        picker.message = L10n.text("Choose the video's folder to enable its playlist and matching subtitles. Selecting a folder is optional for playing a single file.", "选择视频所在文件夹，即可使用同目录播放列表和匹配字幕。仅播放单个视频时无需授权整个文件夹。")
        picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = false
        picker.directoryURL = currentURL?.deletingLastPathComponent()
        picker.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            defer { self.window.makeFirstResponder(self.surface); self.showControls() }
            guard response == .OK, let folder = picker.url,
                  !self.fileAccess.rememberSelection([folder], persist: !self.store.isPrivate).isEmpty else { return }
            if let current = self.currentURL, self.fileAccess.hasDirectoryAccess(to: current.deletingLastPathComponent()) {
                self.currentFolderAccess = true
                self.mediaRequestID &+= 1
                self.pendingExplicitQueueOpen = nil
                let request = self.mediaRequestID
                self.mediaDiscovery.discoverQueue(from: [current], access: self.fileAccess.readSnapshot()) { [weak self] initial in
                    guard let self, self.mediaRequestID == request, self.currentURL == current,
                          !initial.urls.isEmpty else { return }
                    self.queue = initial.urls; self.queueIndex = initial.index; self.playlistSelection = initial.index
                    self.refreshPlaylist(); self.updateQueueButtons()
                    self.fileTitle.stringValue = current.deletingPathExtension().lastPathComponent
                    self.refreshPanel()
                }
                self.discoverSubtitles(for: current)
                self.showHUD(L10n.text("Folder access allowed · Loading playlist and subtitles…", "已允许访问文件夹 · 正在加载播放列表和字幕…"))
                self.refreshPanel(force: true)
            } else { self.openURLs([folder], userSelected: false) }
        }
        updateVideoZoomPresentation()
    }
    @objc private func togglePause() {
        guard currentURL != nil else { chooseFiles(); return }
        if finished { loadIndex(queueIndex, resume: false); return }
        let state = engine.snapshot
        engine.setFlag("pause", !state.paused)
        showHUD(state.paused ? L10n.text("Playing", "继续播放") : L10n.text("Paused", "已暂停"))
        showControls()
    }
    @objc private func videoClicked() { window.makeFirstResponder(surface); togglePause() }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer === videoSingleClick && otherGestureRecognizer === videoDoubleClick
    }
    @objc private func backward() { seek(by: -5) }
    @objc private func forward() { seek(by: 5) }
    @objc private func fullscreen() { window.toggleFullScreen(nil); window.makeFirstResponder(surface) }
    @objc private func toggleSubtitles() {
        if !fileReady { editedControlsDuringLoad.insert("sub-visibility") }
        automaticSubtitleMaySelect = false
        pendingAutomaticSubtitleID = nil
        engine.setFlag("sub-visibility", !engine.snapshot.subtitlesVisible)
        showHUD(engine.snapshot.subtitlesVisible ? L10n.text("Subtitles off", "字幕已关闭") : L10n.text("Subtitles on", "字幕已开启"))
    }
    @objc private func toggleMute() { engine.command(["cycle", "mute"]); showHUD(L10n.text("Mute toggled", "已切换静音")) }
    @objc private func scrub() {
        undoPosition = engine.snapshot.position; seekScheduler.cancel()
        seekTarget = progress.doubleValue; lastSeekDate = Date()
        submitSeek(to: progress.doubleValue)
        showSeekProgress(at: progress.doubleValue)
        window.makeFirstResponder(surface)
    }
    @objc private func changeVolume() { setVolume(volume.doubleValue) }
    private func setHelpVisible(_ visible: Bool) {
        guard help.isHidden == visible else { return }
        cancelVideoPan()
        if visible {
            playlist.isHidden = true
            playlist.setPreviewsEnabled(false)
            playlistButton.contentTintColor = .white
            (playlistButton as? ChromeButton)?.active = false
        }
        help.isHidden = !visible
        progress.endHover()
        hideThumbnailPreview(scheduleHide: false)
        layoutWindow()
        playlist.setPreviewsEnabled(!playlist.isHidden)
        updatePlaylistPreviewPriority()
        writeDiagnostics()
    }
    private func refreshPlaylist() {
        playlistSelection = queue.isEmpty ? 0 : max(0, min(queue.count - 1, playlistSelection))
        playlist.update(urls: queue, currentIndex: queue.isEmpty ? -1 : queueIndex,
                        selectedIndex: queue.isEmpty ? -1 : playlistSelection, hand: hand)
        for url in queue { if let duration = store.entry(for: url)?.duration { playlist.updateDuration(duration, for: url) } }
    }

    private func selectPlaylist(index: Int) {
        guard !queue.isEmpty else { return }
        playlistSelection = max(0, min(queue.count - 1, index))
        playlist.select(index: playlistSelection)
        writeDiagnostics()
    }

    private func movePlaylistSelection(by delta: Int) {
        guard delta != 0 else { return }
        selectPlaylist(index: playlistSelection + delta)
    }

    private func activatePlaylistSelection(index: Int) {
        guard queue.indices.contains(index) else {
            showHUD(L10n.text("Playlist empty · ⌘O to open", "播放列表为空 · 按 ⌘O 打开视频")); return
        }
        playlistSelection = index
        playlist.select(index: index)
        playlist.stopMotionPreview()
        if index == queueIndex, currentURL == queue[index], fileReady, !finished, errorBox.isHidden {
            engine.setFlag("pause", false)
            refreshPlaylist()
        } else if index != queueIndex || fileReady || currentURL != queue[index] || !errorBox.isHidden {
            loadIndex(index, resume: !finished || index != queueIndex)
        }
        showControls(scheduleHide: false)
        window.makeFirstResponder(surface)
        writeDiagnostics()
    }

    private func setPlaylistVisible(_ visible: Bool) {
        guard playlist.isHidden == visible else { return }
        cancelVideoPan()
        if visible {
            help.isHidden = true
            panel.isHidden = true
            playlistSelection = queue.isEmpty ? 0 : queueIndex
            refreshPlaylist()
        }
        playlist.isHidden = !visible
        playlistButton.contentTintColor = visible ? Palette.accent : .white
        (playlistButton as? ChromeButton)?.active = visible
        progress.endHover()
        hideThumbnailPreview(scheduleHide: false)
        layoutWindow()
        playlist.setPreviewsEnabled(visible)
        updatePlaylistPreviewPriority()
        writeDiagnostics()
    }

    @objc private func togglePlaylist() {
        guard window.attachedSheet == nil else { return }
        let open = playlist.isHidden
        setPlaylistVisible(open)
        showControls(scheduleHide: !open)
        window.makeFirstResponder(surface)
    }
    @objc private func toggleHelp() {
        hideThumbnailPreview(scheduleHide: false)
        let open = help.isHidden
        if open { panel.isHidden = true }
        setHelpVisible(open)
        if open { showControls(scheduleHide: false) }
        else { showControls() }
        window.makeFirstResponder(surface)
    }
    @objc private func togglePanel() {
        cancelVideoPan()
        hideThumbnailPreview(scheduleHide: false)
        panel.isHidden.toggle()
        layoutWindow()
        if !panel.isHidden { setHelpVisible(false); setPlaylistVisible(false); refreshPanel(force: true); showControls(scheduleHide: false) }
        else { showControls() }
        window.makeFirstResponder(surface)
    }
    @objc private func showSpeedPanel() {
        cancelVideoPan()
        hideThumbnailPreview(scheduleHide: false)
        panel.isHidden = false; setHelpVisible(false); setPlaylistVisible(false); selectedItem = 0
        layoutWindow()
        refreshPanel(force: true); showControls(scheduleHide: false); window.makeFirstResponder(surface)
    }

    private func presentMenu(_ menu: NSMenu, from button: NSView) {
        showControls(scheduleHide: false)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -5), in: button)
        showControls()
    }
    private func addMenuItem(_ title: String, to menu: NSMenu, action: Selector, value: Any? = nil, checked: Bool = false) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.representedObject = value; item.state = checked ? .on : .off
        menu.addItem(item)
    }
    @objc private func showAppMenu() {
        let menu = NSMenu()
        addMenuItem(L10n.text("Settings…", "设置…"), to: menu, action: #selector(showSettings))
        addMenuItem(L10n.text("Keyboard Shortcuts", "快捷键"), to: menu, action: #selector(toggleHelp))
        menu.addItem(.separator())
        addMenuItem(L10n.text("Open Demo Films", "体验演示影片"), to: menu, action: #selector(openDemo))
        addMenuItem(L10n.text("About LPlayer", "关于 LPlayer"), to: menu, action: #selector(about))
        presentMenu(menu, from: brandMenuButton)
    }
    @objc private func showMoreMenu() {
        presentMenu(makeMoreMenu(), from: moreButton)
    }
    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        if panelButton.isHidden {
            addMenuItem(L10n.text("Quick Controls", "快捷面板"), to: menu, action: #selector(togglePanel))
        }
        if speedButton.isHidden {
            addMenuItem(L10n.text("Playback Speed…", "播放速度…"), to: menu, action: #selector(showSpeedPanel))
        }
        if subtitleButton.isHidden {
            addMenuItem(L10n.text("Show Subtitles", "显示字幕"), to: menu, action: #selector(toggleSubtitles), checked: engine.snapshot.subtitlesVisible)
        }
        if fullscreenButton.isHidden {
            addMenuItem(L10n.text("Full Screen", "全屏"), to: menu, action: #selector(fullscreen))
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        addMenuItem(L10n.text("Settings…", "设置…"), to: menu, action: #selector(showSettings))
        addMenuItem(L10n.text("Keyboard Shortcuts", "快捷键"), to: menu, action: #selector(toggleHelp))
        menu.addItem(.separator())
        addMenuItem(L10n.text("Private Playback", "无痕播放"), to: menu, action: #selector(togglePrivate), checked: store.isPrivate)
        addMenuItem(L10n.text("Allow Folder Access…", "允许访问文件夹…"), to: menu, action: #selector(allowFolderAccess))
        menu.addItem(.separator())
        addMenuItem(L10n.text("Close Video", "关闭视频"), to: menu, action: #selector(closeMedia))
        return menu
    }
    @objc private func showFileInformation() {
        let menu = NSMenu()
        var details = [currentURL?.lastPathComponent ?? L10n.text("No video open", "未打开视频"),
                       currentURL == nil ? "LPlayer" : L10n.text("Duration", "时长") + "  " + clockText(engine.snapshot.duration)]
        if let url = currentURL { details.append(url.pathExtension.uppercased() + L10n.text(" · Local video", " · 本地影片")) }
        for text in details {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item)
        }
        if currentURL != nil { menu.addItem(.separator()); addMenuItem(L10n.text("Show in Finder", "在 Finder 中显示"), to: menu, action: #selector(revealCurrentFile)) }
        presentMenu(menu, from: fileInfoButton)
    }
    @objc private func revealCurrentFile() { if let currentURL { NSWorkspace.shared.activateFileViewerSelecting([currentURL]) } }
    @objc private func showSpeedMenu() {
        let menu = NSMenu(title: L10n.text("Playback Speed", "播放速度"))
        let speed = speedTarget ?? engine.snapshot.speed
        for value in [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3] {
            addMenuItem(String(format: "%g×", value) + (value == 1 ? L10n.text("  Normal", "  正常") : ""), to: menu, action: #selector(selectPlaybackSpeed(_:)), value: value, checked: abs(value - speed) < 0.001)
        }
        presentMenu(menu, from: speedButton)
    }
    @objc private func selectPlaybackSpeed(_ sender: NSMenuItem) { if let speed = sender.representedObject as? Double { setSpeed(speed) } }
    @objc private func showTracksMenu() {
        let menu = NSMenu()
        for type in ["sub", "audio"] {
            if type == "audio" { menu.addItem(.separator()) }
            let heading = NSMenuItem(title: type == "sub" ? L10n.text("Subtitles", "字幕") : L10n.text("Audio", "音轨"), action: nil, keyEquivalent: "")
            heading.isEnabled = false; menu.addItem(heading)
            if type == "sub" { addMenuItem(L10n.text("Off", "关闭字幕"), to: menu, action: #selector(selectMediaTrack(_:)), value: "off", checked: !engine.snapshot.subtitlesVisible) }
            let tracks = engine.snapshot.tracks.filter { $0.type == type }
            for track in tracks { addMenuItem(trackName(track), to: menu, action: #selector(selectMediaTrack(_:)), value: track, checked: track.selected && (type == "audio" || engine.snapshot.subtitlesVisible)) }
            if tracks.isEmpty { let item = NSMenuItem(title: L10n.text("No tracks available", "没有可用轨道"), action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        }
        presentMenu(menu, from: subtitleButton)
    }
    @objc private func selectMediaTrack(_ sender: NSMenuItem) {
        if let track = sender.representedObject as? MediaTrack { selectTrack(track) }
        else {
            automaticSubtitleMaySelect = false; pendingAutomaticSubtitleID = nil
            editedControlsDuringLoad.insert("sub-visibility"); engine.setFlag("sub-visibility", false)
        }
    }
    @objc private func openDemo() {
        let folder = Bundle.main.url(forResource: "Demo", withExtension: nil)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Demo")
        let names = ["北岸 · 冰岛海岸", "在路上 · 雾中的公路", "高地 · 瀑布与苔原"]
        let urls = names.map { folder.appendingPathComponent($0).appendingPathExtension("mp4") }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { showHUD(L10n.text("Demo films are unavailable", "演示影片暂时不可用")); return }
        _ = fileAccess.rememberSelection([folder], persist: false)
        openURLs(urls)
    }
    @objc private func closeMedia() {
        saveProgress(); mediaRequestID &+= 1; subtitleRequestID &+= 1
        mediaDiscovery.cancelAll(); seekScheduler.cancel(); seekTarget = nil
        pendingExplicitQueueOpen = nil; pendingRestore = nil
        currentURL = nil; queue = []; queueIndex = 0; fileReady = false; finished = false
        engine.command(["stop"]); engine.resetVideoZoom()
        playlist.isHidden = true; playlist.setPreviewsEnabled(false); help.isHidden = true; panel.isHidden = true
        errorBox.isHidden = true; hideThumbnailPreview(scheduleHide: false)
        thumbnailGenerator.reset(); pendingSubtitleURLs = []; automaticSubtitleURLs = []
        fileTitle.stringValue = L10n.text("No video open", "未打开视频")
        window.title = "LPlayer"; window.representedURL = nil
        refreshPlaylist(); updateQueueButtons(); layoutWindow(); showControls(scheduleHide: false)
    }
    @objc private func togglePrivate() {
        if !store.isPrivate { saveProgress() }
        store.isPrivate.toggle()
        updateHandLabels()
        refreshRecentMenu()
        showHUD(store.isPrivate ? L10n.text("Private playback · History off", "无痕播放 · 不记录本次观看") : L10n.text("Watch history enabled", "观看记录已开启"))
    }
    @objc private func recentClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        guard let resolved = fileAccess.authorizedURL(for: url) else {
            chooseRecentFile(url)
            return
        }
        if resolved.standardizedFileURL.path != url.standardizedFileURL.path { store.relocate(path: url.path, to: resolved) }
        openURLs([resolved], userSelected: false)
    }

    private func chooseRecentFile(_ previousURL: URL) {
        guard window.attachedSheet == nil else { return }
        cancelVideoPan()
        let picker = NSOpenPanel()
        picker.title = L10n.text("Allow Access to Recent Video", "允许访问最近的视频")
        picker.prompt = L10n.text("Open", "打开")
        picker.message = L10n.text("Select \(previousURL.lastPathComponent) again to restore access and resume its saved position.", "请重新选择 \(previousURL.lastPathComponent)，以恢复访问权限并继续原来的观看进度。")
        picker.canChooseFiles = true; picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.directoryURL = previousURL.deletingLastPathComponent()
        picker.nameFieldStringValue = previousURL.lastPathComponent
        picker.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .OK { self.openURLs(picker.urls) }
            self.window.makeFirstResponder(self.surface)
            self.showControls()
        }
        updateVideoZoomPresentation()
    }
    @objc private func nextFile() { switchFile(by: 1) }
    @objc private func previousFile() { switchFile(by: -1) }
    private func switchFile(by delta: Int) {
        guard !queue.isEmpty else { showHUD(L10n.text("Open a video or folder first", "请先打开视频或文件夹")); return }
        let next = queueIndex + delta
        guard queue.indices.contains(next) else {
            showHUD(delta < 0 ? L10n.text("First video in playlist", "已是第一个视频") : L10n.text("Last video in playlist", "已是最后一个视频"))
            return
        }
        loadIndex(next)
        let direction = delta < 0 ? L10n.text("Previous", "上一个") : L10n.text("Next", "下一个")
        showHUD("\(direction) · \(next + 1) / \(queue.count)")
        window.makeFirstResponder(surface)
    }
    private func updateQueueButtons() {
        previousVideoButton?.isEnabled = !queue.isEmpty && queueIndex > 0
        nextVideoButton?.isEnabled = !queue.isEmpty && queueIndex + 1 < queue.count
    }
    @objc private func clearHistory() {
        guard !store.isPrivate else { showHUD(L10n.text("Leave private mode to clear history", "先退出无痕模式，再清空观看历史")); return }
        store.clear(); fileAccess.clearSavedBookmarks(); refreshRecentMenu()
        showHUD(L10n.text("Watch history and saved file access cleared", "观看历史与保存的文件授权已清空"))
    }

    @objc private func clearSavedFileAccess() {
        fileAccess.clearSavedBookmarks()
        showHUD(L10n.text("Saved access cleared · Open files stay available until quit", "已清除保存的授权 · 当前打开的文件可继续使用至退出"))
    }

    private func refreshRecentMenu() {
        let entries = store.isPrivate ? [] : store.recent
        let signature = L10n.language.rawValue + String(store.isPrivate) + entries.map(\.path).joined(separator: "|")
        guard signature != recentMenuSignature else { return }
        recentMenuSignature = signature
        recentMenu.removeAllItems()
        for entry in entries {
            let item = NSMenuItem(title: entry.name, action: #selector(recentClicked(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = URL(fileURLWithPath: entry.path)
            recentMenu.addItem(item)
        }
        if entries.isEmpty {
            let item = NSMenuItem(title: store.isPrivate ? L10n.text("Private playback is on", "无痕播放中") : L10n.text("No watch history", "暂无观看记录"), action: nil, keyEquivalent: "")
            item.isEnabled = false; recentMenu.addItem(item)
        }
    }

    private func refreshPanel(force: Bool = false) {
        guard !panel.isHidden else { panelPresentation = nil; return }
        var state = engine.snapshot
        state.volume = globalVolume
        state.speed = speedTarget ?? state.speed
        state.subtitleDelay = subtitleDelayTarget ?? state.subtitleDelay
        let presentation = PanelPresentation(speed: state.speed, volume: state.volume, subtitleDelay: state.subtitleDelay,
            subtitlesVisible: state.subtitlesVisible, tracks: state.tracks, zoom: engine.videoZoomScale,
            sensitivity: videoPanSensitivity, hand: hand, language: L10n.language, privateMode: store.isPrivate,
            folderAccess: currentFolderAccess, queueCount: queue.count, shortcutRevision: shortcutRevision)
        guard force || presentation != panelPresentation else { return }
        panelPresentation = presentation
        let subtitles = state.tracks.filter { $0.type == "sub" }
        let audio = state.tracks.filter { $0.type == "audio" }
        let adjust = hand.panelAdjustmentKeys
        let speedKeys = panelShortcutLabel(.speedDown, fallback: hand == .left ? "A" : "J") + "/" + panelShortcutLabel(.speedUp, fallback: hand == .left ? "D" : "L")
        let speedReset = panelShortcutLabel(.resetSpeed, fallback: "Space")
        let subtitleKey = panelShortcutLabel(.subtitles, fallback: "↩")
        let playlistKey = panelShortcutLabel(.playlist, fallback: "↩")
        let zoomReset = panelShortcutLabel(.resetZoom, fallback: "Space")
        let changeHint = L10n.text("Selected row: \(adjust) or ←/→ change · Enter/Space selects", "选中此行后：\(adjust) 或 ←/→ 调整 · 回车/空格确认")
        var items = [QuickItem]()
        items.append(QuickItem(L10n.text("Playback speed", "播放速度"), L10n.format("%g× · ←/→ adjust · Space resets", "%g×  ·  左右调整，空格恢复 1×", state.speed), shortcut: speedKeys + " · " + speedReset, shortcutHelp: changeHint + L10n.text(" · Enter/Space reset to 1×. Outside this panel: ", " · 回车/空格恢复 1×。面板收起后：") + shortcutDescription(.speedDown) + " / " + shortcutDescription(.speedUp) + " · " + shortcutLabel(.resetSpeed), action: { [weak self] in self?.setSpeed(1) }, adjust: { [weak self] in guard let self else { return }; self.setSpeed((self.speedTarget ?? self.engine.snapshot.speed) + Double($0) * 0.1) }))
        items.append(QuickItem(L10n.text("Volume", "音量"), L10n.text("\(Int(state.volume))% · ←/→ adjust", "\(Int(state.volume))%  ·  左右调整"), shortcut: adjust, shortcutHelp: changeHint + L10n.text(" · Enter/Space mute. Outside this panel: ", " · 回车/空格静音。面板收起后：") + shortcutDescription(.volumeUp) + " / " + shortcutDescription(.volumeDown), action: { [weak self] in self?.toggleMute() }, adjust: { [weak self] in guard let self else { return }; self.setVolume(self.globalVolume + Double($0) * 5) }))
        items.append(QuickItem(L10n.text("Video zoom", "画面缩放"), L10n.format("%.0f%% · ←/→ adjust · Space resets", "%.0f%% · 左右调整，空格复原", engine.videoZoomScale * 100), shortcut: adjust + " · " + zoomReset, shortcutHelp: L10n.text("Selected row: \(adjust) or ←/→ zoom · \(zoomReset) or Enter/Space fit to window", "选中此行：\(adjust) 或 ←/→ 缩放 · \(zoomReset) 或回车/空格复原") + " · " + ShortcutAction.zoomOut.title + ": " + shortcutDescription(.zoomOut) + " · " + ShortcutAction.zoomIn.title + ": " + shortcutDescription(.zoomIn), action: { [weak self] in self?.resetVideoZoom() }, adjust: { [weak self] in self?.adjustVideoZoom(by: Double($0) * 0.25) }))
        items.append(QuickItem(L10n.text("Pan sensitivity", "拖动灵敏度"), L10n.format("%.0f%% · ←/→ adjust · Space resets", "%.0f%% · 左右调整，空格恢复", videoPanSensitivity * 100), shortcut: adjust + " · ↩ / Space", shortcutHelp: L10n.text("Selected row: \(adjust) or ←/→ adjust from 25% to 150% · Enter/Space reset to 100%. Lower values move the picture more slowly.", "选中此行：\(adjust) 或 ←/→ 调整 25%–150% · 回车/空格恢复 100%。数值越小，画面移动越慢。"), action: { [weak self] in self?.setVideoPanSensitivity(1) }, adjust: { [weak self] in guard let self else { return }; self.setVideoPanSensitivity(self.videoPanSensitivity + Double($0) * 0.25) }))
        items.append(QuickItem(L10n.text("Subtitles", "显示字幕"), state.subtitlesVisible ? L10n.text("On · Space to toggle", "已开启 · 空格切换") : L10n.text("Off · Space to toggle", "已关闭 · 空格切换"), shortcut: subtitleKey, shortcutHelp: L10n.text("Enter/Space toggle subtitles. Outside this panel: ", "回车/空格切换字幕。面板收起后：") + shortcutDescription(.subtitles), action: { [weak self] in self?.toggleSubtitles() }, adjust: { [weak self] _ in self?.toggleSubtitles() }))
        items.append(QuickItem(L10n.text("Subtitle timing", "字幕时间"), L10n.format("%+.1fs · ←/→ adjust by 0.1s", "%+.1f 秒 · 左右每次调整 0.1 秒", state.subtitleDelay), shortcut: adjust, shortcutHelp: L10n.text("Selected row: \(adjust) or ←/→ adjust by 0.1s · Enter/Space reset timing", "选中此行：\(adjust) 或 ←/→ 每次调整 0.1 秒 · 回车/空格复原"), action: { [weak self] in self?.setSubtitleDelay(0) }, adjust: { [weak self] in guard let self else { return }; self.setSubtitleDelay((self.subtitleDelayTarget ?? self.engine.snapshot.subtitleDelay) + Double($0) * 0.1) }))
        for type in ["audio", "sub"] {
            let tracks = state.tracks.filter { $0.type == type }
            let selected = tracks.first { $0.selected }
            let title = type == "audio" ? L10n.text("Audio track", "音轨") : L10n.text("Subtitle track", "字幕轨道")
            let detail = selected.map { trackName($0) } ?? (tracks.isEmpty ? L10n.text("No tracks available", "没有可用轨道") : L10n.text("Off", "已关闭"))
            items.append(QuickItem(title, detail, shortcut: adjust, shortcutHelp: changeHint, action: { [weak self] in self?.cycleTrack(type, delta: 1) }, adjust: { [weak self] in self?.cycleTrack(type, delta: $0) }))
        }
        items.append(QuickItem(L10n.text("Keyboard layout", "单手布局"), hand.title + L10n.text(" · ←/→ switch", " · 左右切换"), shortcut: adjust, shortcutHelp: changeHint, action: { [weak self] in self?.switchHand() }, adjust: { [weak self] _ in self?.switchHand() }))
        items.append(QuickItem(L10n.text("Private playback", "无痕播放"), store.isPrivate ? L10n.text("On · Watch history is off", "已开启 · 本次观看不写入历史") : L10n.text("Off · History stays on this Mac", "已关闭 · 观看记录仅保存在本机"), shortcut: panelShortcutLabel(.privatePlayback, fallback: "↩"), shortcutHelp: L10n.text("Enter/Space toggle private playback. Outside this panel: ", "回车/空格切换无痕播放。面板收起后：") + shortcutDescription(.privatePlayback), action: { [weak self] in self?.togglePrivate() }, adjust: { [weak self] _ in self?.togglePrivate() }))
        items.append(QuickItem(L10n.text("Open video or folder", "打开文件或文件夹"), L10n.text("Space to open · Or drop files", "空格选择 · 也可拖入窗口"), shortcut: panelShortcutLabel(.openFiles, fallback: "↩"), shortcutHelp: L10n.text("Enter/Space open videos or folders. Outside this panel: ", "回车/空格打开视频或文件夹。面板收起后：") + shortcutDescription(.openFiles), action: { [weak self] in self?.chooseFiles() }))
        let hasFolderAccess = currentFolderAccess
        let folderDetail = hasFolderAccess
            ? L10n.text("Current folder · Videos and matching subtitles available", "当前文件夹 · 已加载同目录视频和匹配字幕")
            : (fileAccess.requiresExplicitDirectorySelection
               ? L10n.text("Allow to load nearby videos and matching subtitles", "授权后读取同目录视频和匹配字幕")
               : L10n.text("Open a video to load its folder automatically", "打开视频后自动加载同目录视频"))
        items.append(QuickItem(L10n.text("Folder access", "文件夹访问"), folderDetail, shortcut: "⌘⇧O", shortcutHelp: L10n.text("Choose a folder to allow read-only access", "选择文件夹，允许只读访问"), action: { [weak self] in self?.allowFolderAccess() }))
        items.append(QuickItem(L10n.text("Playlist", "播放列表"), L10n.text("Queue: \(queue.count) · \(playlistKey) to browse", "\(queue.count) 个视频 · \(playlistKey) 打开选集"), shortcut: playlistKey, shortcutHelp: shortcutDescription(.playlist) + L10n.text(" · Enter/Space open the playlist", " · 回车/空格打开播放列表"), action: { [weak self] in self?.togglePlaylist() }))
        items.append(QuickItem(L10n.text("Language", "语言"), L10n.language.nativeName + L10n.text(" · ←/→ switch", " · 左右切换"), shortcut: adjust, shortcutHelp: changeHint, action: { [weak self] in self?.cycleLanguage(by: 1) }, adjust: { [weak self] in self?.cycleLanguage(by: $0) }))
        items.append(QuickItem(ShortcutAction.customizeShortcuts.title, L10n.text("Record keys · Changes save automatically", "按键录制 · 修改自动保存"), shortcut: panelShortcutLabel(.customizeShortcuts, fallback: "↩"), shortcutHelp: L10n.text("Enter/Space customize shortcuts. Outside this panel: ", "回车/空格自定义快捷键。面板收起后：") + shortcutDescription(.customizeShortcuts), action: { [weak self] in self?.showShortcutEditor() }))
        panelItems = items
        if panelRows.isEmpty {
            let kinds: [QuickAdjustmentRow.Kind] = [.popup, .slider, .slider, .slider, .toggle, .stepper, .popup, .popup, .popup, .toggle, .button, .button, .button, .popup, .button]
            for (index, kind) in kinds.enumerated() {
                let row = QuickAdjustmentRow(kind: kind)
                row.onFocus = { [weak self] in
                    guard let self else { return }
                    self.selectedItem = index; self.updatePanelSelection()
                    self.window.makeFirstResponder(self.surface)
                }
                row.onActivate = { [weak self] in
                    guard let self, self.panelItems.indices.contains(index) else { return }
                    self.panelItems[index].action(); self.refreshPanel(force: true)
                }
                row.onNumber = { [weak self] number in
                    guard let self else { return }
                    if index == 1 { self.setVolume(number) }
                    else if index == 2, self.fileReady { self.engine.setVideoZoomScale(number / 100) }
                    else if index == 3 { self.setVideoPanSensitivity(number / 100) }
                    self.refreshPanel(force: true)
                }
                row.onOption = { [weak self] option in
                    guard let self else { return }
                    switch index {
                    case 0:
                        if self.presentedSpeedValues.indices.contains(option) { self.setSpeed(self.presentedSpeedValues[option]) }
                    case 6:
                        let tracks = self.engine.snapshot.tracks.filter { $0.type == "audio" }
                        if tracks.indices.contains(option) { self.selectTrack(tracks[option]) }
                    case 7:
                        let tracks = self.engine.snapshot.tracks.filter { $0.type == "sub" }
                        if option == 0 { self.engine.setFlag("sub-visibility", false); self.editedControlsDuringLoad.insert("sub-visibility") }
                        else if tracks.indices.contains(option - 1) { self.selectTrack(tracks[option - 1]) }
                    case 8:
                        let selected: HandLayout = option == 0 ? .left : .right
                        if selected != self.hand { self.switchHand() }
                    case 13:
                        if AppLanguage.allCases.indices.contains(option) { self.setLanguage(AppLanguage.allCases[option]) }
                    default: break
                    }
                    self.refreshPanel(force: true)
                }
                row.onToggle = { [weak self] in
                    guard let self else { return }
                    if index == 9 { self.togglePrivate() } else { self.toggleSubtitles() }
                    self.refreshPanel(force: true)
                }
                row.onStep = { [weak self] delta in
                    guard let self else { return }
                    self.setSubtitleDelay((self.subtitleDelayTarget ?? self.engine.snapshot.subtitleDelay) + Double(delta) * 0.1)
                    self.refreshPanel(force: true)
                }
                panelDocument.addSubview(row); panelRows.append(row)
            }
        }
        for (index, item) in panelItems.enumerated() { panelRows[index].setTitle(item.title, help: item.shortcutHelp) }
        presentedSpeedValues = Array(Set([0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, state.speed])).sorted()
        panelRows[0].setOptions(presentedSpeedValues.map { String(format: "%g×", $0) }, selected: presentedSpeedValues.firstIndex { abs($0 - state.speed) < 0.001 } ?? 0)
        panelRows[1].setNumber(state.volume, min: 0, max: 100, text: "\(Int(state.volume))%")
        panelRows[2].setNumber(engine.videoZoomScale * 100, min: 100, max: 500, text: engine.videoZoomScale < 1.01 ? L10n.text("Fit", "适应") : String(format: "%.0f%%", engine.videoZoomScale * 100))
        panelRows[3].setNumber(videoPanSensitivity * 100, min: 25, max: 150, text: String(format: "%.0f%%", videoPanSensitivity * 100))
        panelRows[4].setToggle(state.subtitlesVisible)
        panelRows[5].setStepText(String(format: "%+.1f s", state.subtitleDelay))
        panelRows[6].setOptions(audio.isEmpty ? [L10n.text("No audio", "无音轨")] : audio.map(trackName), selected: audio.firstIndex { $0.selected } ?? 0, enabled: !audio.isEmpty)
        panelRows[7].setOptions([L10n.text("Off", "关闭字幕")] + subtitles.map(trackName), selected: state.subtitlesVisible ? ((subtitles.firstIndex { $0.selected }).map { $0 + 1 } ?? 0) : 0, enabled: !subtitles.isEmpty)
        panelRows[8].setOptions([HandLayout.left.title, HandLayout.right.title], selected: hand == .left ? 0 : 1)
        panelRows[9].setToggle(store.isPrivate)
        for index in [10, 11, 12, 14] { panelRows[index].setActionTitle(L10n.text("Open…", "打开…")) }
        panelRows[13].setOptions(AppLanguage.allCases.map(\.nativeName), selected: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
        panelGroupLabels[0].stringValue = L10n.text("PLAYBACK", "播放")
        panelGroupLabels[1].stringValue = L10n.text("PICTURE", "画面")
        panelGroupLabels[2].stringValue = L10n.text("SUBTITLES & AUDIO", "字幕与音轨")
        panelGroupLabels[3].stringValue = L10n.text("GENERAL", "通用")
        selectedItem = min(selectedItem, panelItems.count)
        layoutPanelRows(); updatePanelSelection()
    }

    private func selectTrack(_ track: MediaTrack) {
        if track.type == "sub" { automaticSubtitleMaySelect = false; pendingAutomaticSubtitleID = nil }
        if !fileReady {
            editedControlsDuringLoad.insert(track.type == "sub" ? "sid" : "aid")
            if track.type == "sub" { editedControlsDuringLoad.insert("sub-visibility") }
        }
        engine.setString(track.type == "sub" ? "sid" : "aid", String(track.id))
        if track.type == "sub" { engine.setFlag("sub-visibility", true) }
        showHUD(trackName(track))
    }

    private func trackName(_ track: MediaTrack) -> String {
        let name = [track.title, track.language].filter { !$0.isEmpty }.joined(separator: " · ")
        return name.isEmpty ? L10n.text("Track \(track.id)", "轨道 \(track.id)") : name
    }
    private func cycleTrack(_ type: String, delta: Int) {
        if type == "sub" { automaticSubtitleMaySelect = false; pendingAutomaticSubtitleID = nil }
        let tracks = engine.snapshot.tracks.filter { $0.type == type }
        guard !tracks.isEmpty else { showHUD(type == "sub" ? L10n.text("No subtitle tracks", "没有可用的字幕") : L10n.text("No audio tracks", "没有可用的音轨")); return }
        let current = tracks.firstIndex { $0.selected } ?? (delta > 0 ? -1 : 0)
        let next = (current + delta + tracks.count) % tracks.count
        if !fileReady {
            editedControlsDuringLoad.insert(type == "sub" ? "sid" : "aid")
            if type == "sub" { editedControlsDuringLoad.insert("sub-visibility") }
        }
        engine.setString(type == "sub" ? "sid" : "aid", String(tracks[next].id))
        if type == "sub" { engine.setFlag("sub-visibility", true) }
        showHUD(trackName(tracks[next]))
    }
    private func switchHand() {
        hand = hand == .left ? .right : .left
        UserDefaults.standard.set(hand.rawValue, forKey: "handLayout")
        refreshShortcutPresentation(); showHUD(L10n.text("Layout · \(hand.title)", "已切换 · \(hand.title)"))
    }

    /// Compact badges favor nearby zoom keys and otherwise show the editable
    /// primary; tooltips list all active alternatives.
    private func shortcutLabel(_ action: ShortcutAction) -> String {
        shortcuts.hintBinding(for: action, hand: hand)?.display ?? "—"
    }

    private func shortcutDescription(_ action: ShortcutAction) -> String {
        var bindings = shortcuts.aliases(for: action, hand: hand)
        if let primary = shortcuts.binding(for: action, hand: hand) { bindings.insert(primary, at: 0) }
        var seen = Set<KeyChord>()
        return bindings.filter { seen.insert($0).inserted }.map(\.display).joined(separator: " / ")
    }

    private func panelShortcutLabel(_ action: ShortcutAction, fallback: String) -> String {
        var bindings = shortcuts.aliases(for: action, hand: hand)
        if let primary = shortcuts.binding(for: action, hand: hand) { bindings.insert(primary, at: 0) }
        // A customized playback key may be fixed navigation inside this panel.
        // Advertise a working alternative for this context, or the row's own
        // adjustment/activation key, while tooltips explain the playback key.
        return bindings.first { chord in
            let playback = shortcuts.command(for: chord, hand: hand, context: .playback)
            return playback != nil && playback == shortcuts.command(for: chord, hand: hand, context: .panel)
        }?.display ?? fallback
    }

    private func refreshShortcutPresentation() {
        shortcutRevision &+= 1
        updateHandLabels()
        updateVideoZoomPresentation()
        refreshPanel(force: true)
        buildMenu()
        writeDiagnostics()
    }

    @objc private func showSettings() { presentSettings(section: .general) }
    @objc private func showShortcutEditor() { presentSettings(section: .shortcuts) }

    private func presentSettings(section: ShortcutEditor.Section) {
        guard window.attachedSheet == nil else { return }
        cancelVideoPan()
        videoZoomHint.isHidden = true
        // Only one panel background may cover a given part of the picture.
        // Stacking two translucent panels makes both appear almost opaque.
        panel.isHidden = true
        hideThumbnailPreview()
        showControls(scheduleHide: false)
        let editor = ShortcutEditor(store: shortcuts, hand: hand, panSensitivity: videoPanSensitivity)
        editor.onLanguageChange = { [weak self] in self?.setLanguage($0) }
        editor.onPanSensitivityChange = { [weak self] in self?.setVideoPanSensitivity($0) }
        editor.onHandChange = { [weak self] selected in
            guard let self else { return }
            self.hand = selected
            UserDefaults.standard.set(selected.rawValue, forKey: "handLayout")
            self.refreshShortcutPresentation()
        }
        editor.onClose = { [weak self] in
            guard let self else { return }
            self.shortcutEditor = nil
            self.window.makeFirstResponder(self.surface)
            self.showControls()
        }
        shortcutEditor = editor
        editor.presentSettings(asSheetFor: window, section: section)
        updateVideoZoomPresentation()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // A sheet owns its text/recording input. Menu commands must not change
        // playback behind it or replace the active recorder with another sheet.
        window?.attachedSheet == nil
    }

    private func updateHandLabels() {
        help.hand = hand
        playlist.closeShortcut = shortcutLabel(.playlist)
        refreshPlaylist()
        let closeKey = shortcutLabel(.panel)
        panelHint.stringValue = L10n.text("\(hand.movement)\nSpace · \(closeKey) / Esc close", "\(hand.movement)\n空格确认 · \(closeKey) / Esc 收起")
        panelHint.toolTip = L10n.text("\(hand.movement) · Space · \(closeKey) / Esc close", "\(hand.movement) · 空格确认 · \(closeKey) / Esc 收起")
        privateButton?.contentTintColor = store.isPrivate ? Palette.accent : Palette.muted
        privateButton?.title = L10n.text("Private", "无痕")
        privateButton?.isHidden = !store.isPrivate
        let hints: [(NSButton?, String)] = [
            (backwardButton, ShortcutAction.seekBackward.title + " · " + shortcutDescription(.seekBackward)),
            (forwardButton, ShortcutAction.seekForward.title + " · " + shortcutDescription(.seekForward)),
            (previousVideoButton, ShortcutAction.previousFile.title + " · " + shortcutDescription(.previousFile)),
            (nextVideoButton, ShortcutAction.nextFile.title + " · " + shortcutDescription(.nextFile)),
            (helpButton, ShortcutAction.help.title + " · " + shortcutDescription(.help)),
            (playlistButton, ShortcutAction.playlist.title + " · " + shortcutDescription(.playlist)),
            (fullscreenButton, ShortcutAction.fullscreen.title + " · " + shortcutDescription(.fullscreen)),
            (subtitleButton, ShortcutAction.subtitles.title + " · " + shortcutDescription(.subtitles)),
            (speedButton, L10n.text("Playback speed", "倍速") + " · " + shortcutLabel(.speedDown) + " / " + shortcutLabel(.speedUp)),
            (panelButton, ShortcutAction.panel.title + " · " + shortcutDescription(.panel)),
            (playButton, ShortcutAction.playPause.title + " · " + shortcutDescription(.playPause)),
            (topOpenButton, ShortcutAction.openFiles.title + " · " + shortcutDescription(.openFiles)),
            (volumeButton, ShortcutAction.mute.title + (shortcutDescription(.mute).isEmpty ? "" : " · " + shortcutDescription(.mute))),
            (privateButton, (store.isPrivate ? L10n.text("Private playback on", "无痕播放已开启") : L10n.text("Private playback off", "无痕播放已关闭")) + " · " + shortcutDescription(.privatePlayback))
        ]
        for (button, text) in hints { button?.toolTip = text; button?.setAccessibilityLabel(text) }
    }
    private func layoutPanelRows() {
        let width = max(220, panelScroll.contentSize.width)
        var y: CGFloat = 0
        for (section, indices) in [[0, 1], [2, 3], [4, 5, 6, 7], Array(8..<15)].enumerated() {
            if section > 0 {
                panelGroupLines[section - 1].frame = NSRect(x: 7, y: y + 4, width: width - 14, height: 1)
                y += 17
            }
            panelGroupLabels[section].frame = NSRect(x: 7, y: y, width: width - 14, height: 17)
            y += 20
            for index in indices where panelRows.indices.contains(index) {
                panelRows[index].frame = NSRect(x: 0, y: y, width: width, height: 35)
                y += 35
            }
        }
        panelDocument.frame = NSRect(x: 0, y: 0, width: width, height: y + 4)
    }
    private func updatePanelSelection() {
        for (i, row) in panelRows.enumerated() { row.selected = i == selectedItem }
        (panelSettingsButton as? ChromeButton)?.active = selectedItem == panelItems.count
        panelSettingsButton?.contentTintColor = selectedItem == panelItems.count ? Palette.accent : Palette.overlaySecondary
        if panelRows.indices.contains(selectedItem) { panelDocument.scrollToVisible(panelRows[selectedItem].frame) }
        writeDiagnostics()
    }

    private func showHUD(_ text: String) {
        if hudLabel.stringValue != text { hudLabel.stringValue = text }
        hud.isHidden = false
        hudHideDeadline = ProcessInfo.processInfo.systemUptime + 1.4
        if hudTimer == nil { scheduleHUDHide(after: 1.4) }
    }
    private func scheduleHUDHide(after delay: TimeInterval) {
        let timer = Timer(timeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.hudTimer = nil
            let remaining = self.hudHideDeadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { self.scheduleHUDHide(after: remaining) }
            else { self.hud.isHidden = true }
        }
        hudTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private var canHideControls: Bool {
        thumbnailHoverTime == nil && !progress.isTracking && currentURL != nil
            && panel.isHidden && help.isHidden && playlist.isHidden && !engine.snapshot.paused
            && errorBox.isHidden && !isZooming && !isPanningVideo && !window.inLiveResize
    }
    private func updateSubtitleSafeArea() {
        guard engine != nil, surface != nil else { return }
        let controlsOverlayVideo = window.styleMask.contains(.fullScreen) && !bottomBar.isHidden && bottomBar.alphaValue > 0.01
        let inset: CGFloat = 20 + (controlsOverlayVideo ? Self.bottomBarHeight : 0)
        let margin = Int(ceil(720 * inset / max(1, engine.videoView.frame.height)))
        if margin != subtitleMargin { subtitleMargin = margin; engine.setDouble("sub-margin-y", Double(margin)) }
    }
    private func scheduleControlsHide(after delay: TimeInterval) {
        let timer = Timer(timeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.controlsTimer = nil
            guard self.canHideControls else { return }
            let remaining = self.controlsHideDeadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { self.scheduleControlsHide(after: remaining); return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.topBar.animator().alphaValue = 0
                self.bottomBar.animator().alphaValue = 0
                self.videoZoomHint.animator().alphaValue = 0
                self.mediaBadge.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.updateSubtitleSafeArea()
                self?.writeDiagnostics()
            }
        }
        controlsTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func showControls(scheduleHide: Bool = true) {
        (panelButton as? ChromeButton)?.active = !panel.isHidden
        (playlistButton as? ChromeButton)?.active = !playlist.isHidden
        if topBar.alphaValue < 1 || bottomBar.alphaValue < 1 {
            topBar.alphaValue = 1; bottomBar.alphaValue = 1
            layoutTitlebar()
        }
        updateVideoZoomPresentation()
        if videoZoomHint.alphaValue < 1 { videoZoomHint.alphaValue = 1 }
        if mediaBadge.alphaValue < 1 { mediaBadge.alphaValue = 1 }
        updateSubtitleSafeArea()
        if scheduleHide && canHideControls {
            controlsHideDeadline = ProcessInfo.processInfo.systemUptime + 2.8
            if controlsTimer == nil { scheduleControlsHide(after: 2.8) }
        } else {
            controlsTimer?.invalidate(); controlsTimer = nil
        }
    }

    private func configureSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.currentURL != nil, !self.engine.snapshot.paused else { return }
            self.engine.setFlag("pause", true); self.showHUD(L10n.text("Audio output changed · Paused", "音频输出已切换 · 已暂停"))
        }
        audioListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    @objc private func willSleep() {
        cancelVideoPan()
        seekScheduler.cancel(); thumbnailResumeWork?.cancel()
        hideThumbnailPreview(scheduleHide: false); engine.setFlag("pause", true); saveProgress()
        store.flush()
    }
    func windowDidResize(_ notification: Notification) { cancelVideoPan(); progress.endHover(); layoutWindow() }
    func windowDidBecomeKey(_ notification: Notification) {
        layoutTitlebar()
        playlist.setPreviewsEnabled(!playlist.isHidden)
        updatePlaylistPreviewPriority()
    }
    func windowDidResignKey(_ notification: Notification) { cancelVideoPan(); progress.endHover(); hideThumbnailPreview(); playlist.setPreviewsEnabled(false) }
    func windowWillMiniaturize(_ notification: Notification) { cancelVideoPan(); progress.endHover(); hideThumbnailPreview(); playlist.setPreviewsEnabled(false) }
    func windowDidDeminiaturize(_ notification: Notification) {
        playlist.setPreviewsEnabled(!playlist.isHidden)
        updatePlaylistPreviewPriority()
    }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposedOptions.union([.autoHideToolbar, .autoHideMenuBar])
    }
    func windowDidEnterFullScreen(_ notification: Notification) { observeTitlebarControls(); layoutWindow(); showControls(); writeDiagnostics() }
    func windowDidExitFullScreen(_ notification: Notification) { observeTitlebarControls(); layoutWindow(); showControls(); writeDiagnostics() }
    func windowWillClose(_ notification: Notification) { saveProgress(); NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        guard !terminated else { return }; terminated = true
        titlebarObservations.removeAll()
        saveProgress(); store.flush(); mediaDiscovery.cancelAll()
        seekScheduler.cancel(); thumbnailResumeWork?.cancel(); hudTimer?.invalidate(); controlsTimer?.invalidate()
        thumbnailGenerator.shutdown()
        playlist.shutdownPreviews()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let audioListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, audioListener)
        }
        engine?.shutdown()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, let language = AppLanguage(rawValue: code) else { return }
        setLanguage(language)
    }

    private func cycleLanguage(by delta: Int) {
        let languages = AppLanguage.allCases
        guard let index = languages.firstIndex(of: L10n.language) else { return }
        setLanguage(languages[(index + delta % languages.count + languages.count) % languages.count])
    }

    private func setLanguage(_ language: AppLanguage) {
        guard language != L10n.language else { return }
        L10n.select(language)
        refreshLocalization()
        showHUD(L10n.text("Language: English", "语言：简体中文"))
        showControls()
        window.makeFirstResponder(surface)
        writeDiagnostics()
    }

    private func refreshLocalization() {
        buildMenu()
        if currentURL == nil { fileTitle.stringValue = L10n.text("No video open", "未打开视频") }
        panelTitle.stringValue = L10n.text("Quick Controls", "快捷调节")
        emptyState.refreshLocalization()
        topOpenButton.title = L10n.text("Open", "打开")
        panelSettingsButton.title = L10n.text("Settings…", "设置…")
        brandMenuButton.setAccessibilityLabel(L10n.text("LPlayer menu", "LPlayer 菜单"))
        fileInfoButton.setAccessibilityLabel(L10n.text("Video information", "视频信息"))
        moreButton.setAccessibilityLabel(L10n.text("More", "更多操作"))
        panelCloseButton.setAccessibilityLabel(L10n.text("Close quick controls", "关闭快捷调节"))
        progress.setAccessibilityLabel(L10n.text("Playback position", "播放进度"))
        volume.setAccessibilityLabel(L10n.text("Volume", "音量"))
        help.refreshLocalization()
        playlist.refreshLocalization()
        thumbnailPreview.refreshLocalization()
        shortcutEditor?.refreshLocalization()
        updateHandLabels()
        refreshPlaybackError()
        refreshPanel(force: true)
        layoutWindow()
    }

    private func refreshPlaybackError() {
        errorTitle.stringValue = L10n.text("Unable to play this video", "这个视频暂时无法播放")
        errorMessage.stringValue = (playbackFailureReason?.localizedDescription ?? playbackError).map {
            $0 + "\n" + L10n.text("Press ⌘O to reopen. Your saved position is kept.", "可按 ⌘O 重新选择文件，原来的观看进度已保留。")
        } ?? ""
    }

    private func buildMenu() {
        // Use a new recent submenu when rebuilding so the previous menu tree
        // never shares an NSMenu instance with the new one.
        recentMenu = NSMenu(title: L10n.text("Open Recent", "最近打开"))
        recentMenuSignature = ""
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("About LPlayer", "关于 LPlayer"), action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: L10n.text("Settings…", "设置…"), action: #selector(showSettings), keyEquivalent: ",")
        let languageItem = NSMenuItem(title: L10n.text("Language", "语言"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: languageItem.title)
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.nativeName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == L10n.language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        appMenu.addItem(languageItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("Hide LPlayer", "隐藏 LPlayer"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L10n.text("Quit LPlayer", "退出 LPlayer"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let file = NSMenuItem(); file.title = L10n.text("File", "文件"); let fileMenu = NSMenu(title: file.title)
        fileMenu.addItem(withTitle: L10n.text("Open Video or Folder…", "打开视频或文件夹…"), action: #selector(chooseFiles), keyEquivalent: "o")
        let folderAccessItem = fileMenu.addItem(withTitle: L10n.text("Allow Folder Access…", "允许访问文件夹…"), action: #selector(allowFolderAccess), keyEquivalent: "o")
        folderAccessItem.keyEquivalentModifierMask = [.command, .shift]
        let recent = NSMenuItem(title: L10n.text("Open Recent", "最近打开"), action: nil, keyEquivalent: "")
        recent.submenu = recentMenu; fileMenu.addItem(recent)
        refreshRecentMenu()
        fileMenu.addItem(withTitle: L10n.text("Private Playback", "无痕播放"), action: #selector(togglePrivate), keyEquivalent: "n")
        fileMenu.addItem(withTitle: L10n.text("Clear Watch History", "清空观看历史"), action: #selector(clearHistory), keyEquivalent: "")
        fileMenu.addItem(withTitle: L10n.text("Clear Saved File Access", "清除保存的文件授权"), action: #selector(clearSavedFileAccess), keyEquivalent: "")
        fileMenu.addItem(.separator()); fileMenu.addItem(withTitle: L10n.text("Close Window", "关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.submenu = fileMenu; menu.addItem(file)
        let playback = NSMenuItem(); playback.title = L10n.text("Playback", "播放"); let playbackMenu = NSMenu(title: playback.title)
        playbackMenu.addItem(withTitle: L10n.text("Play / Pause", "暂停 / 继续"), action: #selector(togglePause), keyEquivalent: "")
        playbackMenu.addItem(withTitle: L10n.text("Previous Video", "上一个视频"), action: #selector(previousFile), keyEquivalent: "[")
        playbackMenu.addItem(withTitle: L10n.text("Next Video", "下一个视频"), action: #selector(nextFile), keyEquivalent: "]")
        playbackMenu.addItem(withTitle: ShortcutAction.zoomOut.title, action: #selector(zoomOut), keyEquivalent: "")
        playbackMenu.addItem(withTitle: ShortcutAction.zoomIn.title, action: #selector(zoomIn), keyEquivalent: "")
        playbackMenu.addItem(withTitle: L10n.text("Fit Video to Window", "画面恢复适应窗口"), action: #selector(resetVideoZoom), keyEquivalent: "0")
        playbackMenu.addItem(withTitle: L10n.text("Full Screen", "全屏"), action: #selector(fullscreen), keyEquivalent: "")
        playbackMenu.addItem(withTitle: L10n.text("Quick Controls", "快捷面板"), action: #selector(togglePanel), keyEquivalent: "")
        playbackMenu.addItem(withTitle: L10n.text("Playlist", "播放列表"), action: #selector(togglePlaylist), keyEquivalent: "l")
        playback.submenu = playbackMenu; menu.addItem(playback)
        let edit = NSMenuItem(); edit.title = L10n.text("Edit", "编辑"); let editMenu = NSMenu(title: edit.title)
        editMenu.addItem(withTitle: L10n.text("Cut", "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.text("Copy", "复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("Paste", "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.text("Select All", "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; menu.addItem(edit)
        let helpItem = NSMenuItem(); helpItem.title = L10n.text("Help", "帮助"); let helpMenu = NSMenu(title: helpItem.title)
        helpMenu.addItem(withTitle: L10n.text("Keyboard Shortcuts", "单手快捷键说明"), action: #selector(toggleHelp), keyEquivalent: "/")
        helpMenu.addItem(withTitle: L10n.text("Privacy Policy", "隐私政策"), action: #selector(openPrivacyPolicy), keyEquivalent: "")
        helpItem.submenu = helpMenu; menu.addItem(helpItem)
        NSApp.mainMenu = menu
        for sub in [appMenu, fileMenu, playbackMenu, helpMenu] {
            for item in sub.items where item.action != #selector(NSApplication.terminate(_:)) && item.action != #selector(NSApplication.hide(_:)) && item.action != #selector(NSWindow.performClose(_:)) { item.target = self }
            for item in sub.items { updateMenuShortcut(item) }
        }
    }

    private func updateMenuShortcut(_ item: NSMenuItem) {
        let actions: [Selector: ShortcutAction] = [
            #selector(togglePause): .playPause, #selector(chooseFiles): .openFiles,
            #selector(togglePrivate): .privatePlayback, #selector(previousFile): .previousFile,
            #selector(nextFile): .nextFile, #selector(zoomOut): .zoomOut,
            #selector(zoomIn): .zoomIn, #selector(resetVideoZoom): .resetZoom,
            #selector(fullscreen): .fullscreen, #selector(togglePanel): .panel,
            #selector(togglePlaylist): .playlist, #selector(toggleHelp): .help,
            #selector(showShortcutEditor): .customizeShortcuts
        ]
        guard let selector = item.action, let action = actions[selector] else { return }
        let primary = shortcuts.binding(for: action, hand: hand)
        let chord = primary?.modifiers.contains(.command) == true ? primary
            : shortcuts.aliases(for: action, hand: hand).first { $0.modifiers.contains(.command) }
        // Bare playback keys belong to the focused video view, never to menus
        // that could intercept typing in a search field or native file dialog.
        item.keyEquivalent = chord?.key ?? ""
        var flags: NSEvent.ModifierFlags = []
        if let chord {
            if chord.modifiers.contains(.command) { flags.insert(.command) }
            if chord.modifiers.contains(.shift) { flags.insert(.shift) }
            if chord.modifiers.contains(.option) { flags.insert(.option) }
            if chord.modifiers.contains(.control) { flags.insert(.control) }
        }
        item.keyEquivalentModifierMask = flags
    }
    @objc private func openPrivacyPolicy() {
        let name = L10n.language == .english ? "PrivacyPolicy.en" : "PrivacyPolicy.zh-Hans"
        if let url = Bundle.main.url(forResource: name, withExtension: "html") { NSWorkspace.shared.open(url) }
    }
    @objc private func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.10.0"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "LPlayer", .applicationVersion: version, .credits: NSAttributedString(string: L10n.text("Local playback · One-hand control\nPowered by mpv / FFmpeg / libass. Licenses: Resources/licenses in the app.", "本地优先 · 单手掌控\n播放内核 mpv / FFmpeg / libass，许可证见应用 Resources/licenses。"))])
    }

    private func writeDiagnostics() {
        guard let url = diagnosticsURL, engine != nil else { return }
        let s = engine.snapshot
        var values: [String: Any] = ["path": currentURL?.path ?? "", "position": s.position, "duration": s.duration, "paused": s.paused, "volume": s.volume, "speed": s.speed, "videoZoomScale": engine.videoZoomScale, "subtitleDelay": s.subtitleDelay, "subtitlesVisible": s.subtitlesVisible, "trackCount": s.tracks.count, "panelOpen": !panel.isHidden, "selectedItem": selectedItem, "hand": hand.rawValue, "private": store.isPrivate, "helpOpen": !help.isHidden, "errorVisible": !errorBox.isHidden, "hud": hudLabel.stringValue, "queueCount": queue.count, "queueIndex": queueIndex, "fullscreen": window.styleMask.contains(.fullScreen), "thumbnailVisible": !thumbnailPreview.isHidden, "thumbnailTime": thumbnailHoverTime ?? 0, "thumbnailReady": thumbnailReady]
        values["seeking"] = s.seeking
        values["seekInputPending"] = seekScheduler.hasPending
        values["playlistOpen"] = !playlist.isHidden
        values["playlistSelection"] = playlistSelection
        values["language"] = L10n.language.rawValue
        values["surfaceFrame"] = NSStringFromRect(surface.bounds)
        values["windowFrame"] = NSStringFromRect(window.frame)
        values["screenFrame"] = window.screen.map { NSStringFromRect($0.frame) }
        values["surfaceFrameInWindow"] = NSStringFromRect(surface.convert(surface.bounds, to: nil))
        values["videoFrame"] = NSStringFromRect(engine.videoView.frame)
        values["controlsAlpha"] = bottomBar.alphaValue
        values["subtitleMargin"] = subtitleMargin
        values["directoryAccess"] = currentURL.map { fileAccess.hasDirectoryAccess(to: $0.deletingLastPathComponent()) } ?? false
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
}
