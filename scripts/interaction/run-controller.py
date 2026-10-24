"""Exercise the current controller through local NSEvent objects, with no UI input.

Every product Swift file is snapshotted before compilation. Only those disposable
copies redirect storage/preferences, suppress activation, and omit the key-window
gate for the owned hidden window. The handler's remaining guards and dispatch
are unchanged. No user media, window, screen or global event is used, and shared
application preferences are isolated from the test suite.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parents[2]
fixture = Path(__file__).resolve().parent
out = root / "artifacts/controller-check"
out.mkdir(parents=True, exist_ok=True)
suite = "LPlayer-NearbyVideo-" + str(uuid.uuid4())
scratch = Path(tempfile.mkdtemp(prefix="lplayer-nearby-video-"))
adaptations = [
    "All Swift sources copied before compilation; production files are untouched.",
    "Remove @main and window ordering/activation in the temporary App copy.",
    "All explicit and implicit UserDefaults.standard references use one disposable suite, removed on exit.",
    "LibraryStore and FileAccessStore use scratch directories.",
    "Omit only NSApp.keyWindow === window from handleKey; retain event.window ownership, sheet, editable-input and repeat guards.",
    "FixtureKey overrides window/characters/modifiers/repeat; handleKey is called directly, without NSApp.sendEvent or global input.",
    "Fixture setup/read hooks appended to the temporary App copy; no replacement command dispatcher.",
    "Volume regressions seed only scratch LibraryStore records with disparate legacy volumes, exercise the real slider action and resume=true routes, then restart an owned hidden controller in the same disposable preference suite.",
    "Playlist hover regressions use the production row/configure/scroll notification paths in an owned, never-ordered NSWindow. Only that fixture window's key status and local mouse position are overridden; no actual pointer, user window or global input is read or changed.",
    "Fullscreen geometry checks replace only window.styleMask.contains(.fullScreen) with a fixture boolean in the temporary App copy. AppKit rejects directly setting the fullscreen style bit outside a real Space transition. Production layout, controls, hide timer, subtitle margins and hit testing remain unchanged; physical fullscreen Spaces require separate UI verification.",
]
try:
    sources = sorted((root / "Sources/PalmPlayer").glob("*.swift"))
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (out / "source-hashes.json").write_text(json.dumps(hashes, indent=2, sort_keys=True) + "\n")
    (out / "test-adaptations.json").write_text(json.dumps(adaptations, indent=2) + "\n")
    for source in sources:
        text = source.read_text()
        text = text.replace("UserDefaults.standard", "InteractionFixture.preferences")
        text = text.replace("defaults: UserDefaults = .standard", "defaults: UserDefaults = InteractionFixture.preferences")
        if source.name == "L10n.swift":
            text = text.replace("AppLanguage.resolve(in: .standard)", "AppLanguage.resolve(in: InteractionFixture.preferences)")
        if source.name == "App.swift":
            replacements = [
                ("@main\n", ""),
                ("window.makeKeyAndOrderFront(nil)", "_ = window"),
                ("NSApp.activate(ignoringOtherApps: true)", "_ = NSApp"),
                ("let store = LibraryStore(persistence: .background)", 'let store = LibraryStore(directory: InteractionFixture.directory.appendingPathComponent("history"), persistence: .background)'),
                ("private let fileAccess = FileAccessStore()", 'private let fileAccess = FileAccessStore(directory: InteractionFixture.directory.appendingPathComponent("grants"), sandboxed: false)'),
                ("guard NSApp.keyWindow === window else { return false }", "// TEST ONLY: the owned controller window deliberately stays hidden."),
            ]
            for old, new in replacements:
                assert old in text, "production adapter pattern changed: " + old
                text = text.replace(old, new)
            assert "guard event.window === window else { return false }" in text
            assert "guard window.attachedSheet == nil else { return false }" in text
            assert "editor.isEditable { return false }" in text
            fullscreen_gate = "window.styleMask.contains(.fullScreen)"
            assert text.count(fullscreen_gate) >= 3, "production fullscreen layout gates changed"
            text = text.replace(fullscreen_gate, "InteractionFixture.fullscreenLayout")
            text += r'''
extension PlayerApp {
    var restoreWindow: NSWindow { window }
    var restoreEngine: MPVEngine { engine }
    var restoreSurface: PlayerSurface { surface }
    var restoreQueueIndex: Int { queueIndex }
    var restoreSelection: Int { playlistSelection }
    var restoreReady: Bool { fileReady }
    var restoreQueueCount: Int { queue.count }
    var restoreListOpen: Bool { !playlist.isHidden }
    var restorePanelOpen: Bool { !panel.isHidden }
    var restoreHelpOpen: Bool { !help.isHidden }
    var restorePanelIndex: Int { selectedItem }
    var restorePrivate: Bool { store.isPrivate }
    var restoreHistory: [PlaybackBookmark] { store.recent }
    var restoreGlobalVolume: Double { globalVolume }
    var restoreHand: HandLayout { hand }
    var restoreSensitivity: Double { videoPanSensitivity }
    var restoreSeekTarget: Double? { seekTarget }
    var restorePanelTitles: [String] { panelItems.map { $0.title } }
    var restorePanelLayoutValid: Bool {
        panelRows.count == 15 && panelGroupLabels.count == 4 && panelRows.allSatisfy {
            $0.frame.height == 35 && panelDocument.bounds.contains($0.frame)
        } && panel.bounds.contains(panelSettingsButton.frame)
    }
    var restoreFooterRoutesToSettings: Bool { panelSettingsButton.action == #selector(showSettings) }
    var restoreFooterSelected: Bool { (panelSettingsButton as? ChromeButton)?.active == true }
    var restoreVideoFrame: NSRect { engine.videoView.frame }
    var restoreTopBarFrame: NSRect { topBar.frame }
    var restoreBottomBarFrame: NSRect { bottomBar.frame }
    var restoreTransportFrames: [String: NSRect] {
        let controls: [(String, NSView)] = [
            ("play", playButton), ("backward", backwardButton), ("forward", forwardButton),
            ("previous", previousVideoButton), ("next", nextVideoButton),
            ("volumeButton", volumeButton), ("volumeSlider", volume), ("speed", speedButton),
            ("subtitle", subtitleButton), ("panel", panelButton), ("more", moreButton),
            ("fullscreen", fullscreenButton), ("time", timeLabel)
        ]
        return Dictionary(uniqueKeysWithValues: controls.filter { !$0.1.isHidden }.map { ($0.0, $0.1.frame) })
    }
    var restoreTransportVisualFrames: [String: NSRect] {
        let controls: [(String, NSButton)] = [
            ("play", playButton), ("backward", backwardButton), ("forward", forwardButton),
            ("previous", previousVideoButton), ("next", nextVideoButton),
            ("volumeButton", volumeButton), ("speed", speedButton), ("subtitle", subtitleButton),
            ("panel", panelButton), ("more", moreButton), ("fullscreen", fullscreenButton)
        ]
        return Dictionary(uniqueKeysWithValues: controls.compactMap { name, control -> (String, NSRect)? in
            guard !control.isHidden, let button = control as? ChromeButton else { return nil }
            let plate = control.bounds.insetBy(dx: button.visualInset, dy: button.visualInset)
            return (name, control.convert(plate, to: bottomBar))
        })
    }
    var restoreTimelineFrames: [String: NSRect] {
        ["progress": progress.frame]
    }
    var restoreMoreMenuActions: [String] {
        func actions(in menu: NSMenu) -> [String] {
            menu.items.flatMap { item -> [String] in
                let own = item.action.map { [NSStringFromSelector($0)] } ?? []
                return own + (item.submenu.map { actions(in: $0) } ?? [])
            }
        }
        return actions(in: makeMoreMenu())
    }
    var restoreHelpFrame: NSRect { help.frame }
    var restorePlaylistFrame: NSRect { playlist.frame }
    var restoreSubtitleMargin: Int { subtitleMargin }
    var restoreControlsVisible: Bool { topBar.alphaValue > 0.99 && bottomBar.alphaValue > 0.99 }
    var restoreControlsHidden: Bool { topBar.alphaValue <= 0.01 && bottomBar.alphaValue <= 0.01 }
    var restoreChromeAlpha: [CGFloat] { [topBar, bottomBar].map { $0.layer?.backgroundColor?.alpha ?? -1 } }
    var restoreHelpOverlays: Bool { help.overlaysVideo }
    var restorePlaylistOverlays: Bool { playlist.overlaysVideo }
    var restoreHiddenChromePassesHits: Bool {
        let top = NSPoint(x: topBar.frame.midX, y: topBar.frame.midY)
        let bottom = NSPoint(x: bottomBar.frame.midX, y: bottomBar.frame.midY)
        return topBar.hitTest(top) == nil && bottomBar.hitTest(bottom) == nil
            && surface.hitTest(surface.convert(top, to: surface.superview)) === engine.videoView
            && surface.hitTest(surface.convert(bottom, to: surface.superview)) === engine.videoView
    }
    var restoreVisibleChromeReceivesHits: Bool {
        let top = topBar.convert(NSPoint(x: topOpenButton.frame.midX, y: topOpenButton.frame.midY), to: surface)
        let bottom = bottomBar.convert(NSPoint(x: playButton.frame.midX, y: playButton.frame.midY), to: surface)
        return surface.hitTest(surface.convert(top, to: surface.superview)) === topOpenButton
            && surface.hitTest(surface.convert(bottom, to: surface.superview)) === playButton
    }
    func restoreFullscreenLayout(_ value: Bool) {
        InteractionFixture.fullscreenLayout = value; layoutWindow()
    }
    func restoreShowControls() { showControls(scheduleHide: false) }
    func restoreHideControlsSoon() {
        controlsTimer?.invalidate(); controlsTimer = nil
        controlsHideDeadline = ProcessInfo.processInfo.systemUptime
        scheduleControlsHide(after: 0.01)
    }
    func restoreHelpSetup(_ visible: Bool) { setHelpVisible(visible); showControls(scheduleHide: false) }
    func restorePlaylistSetup(_ visible: Bool) { setPlaylistVisible(visible); showControls(scheduleHide: false) }
    func restorePlaylistStyleSetup(_ style: PlaylistView.ViewStyle) { playlist.setViewStyle(style) }
    func restoreKey(_ event: NSEvent) -> Bool { handleKey(event) }
    func restoreOpen(_ urls: [URL]) { openURLs(urls) }
    func restoreHandSetup(_ value: HandLayout) { hand = value; updateHandLabels() }
    func restoreLoadSetup(_ index: Int) { loadIndex(index, resume: false) }
    func restoreMediaSetup() { setVolume(70); setSpeed(1); engine.setFlag("pause", true) }
    func restoreHistorySetup(_ records: [PlaybackBookmark]) {
        store.isPrivate = false
        for record in records { store.save(record) }
        store.flush()
    }
    func restoreFlushHistory() { store.flush() }
    func restorePrivateSetup(_ value: Bool) { store.isPrivate = value }
    func restoreVolumeSlider(_ value: Double) -> Bool {
        volume.doubleValue = value
        guard let action = volume.action else { return false }
        return volume.sendAction(action, to: volume.target)
    }
    func restoreClickSubtitle() { subtitleButton.performClick(nil) }
    func restoreClickSpeed() { speedButton.performClick(nil) }
    func restoreSize(_ size: NSSize) {
        window.setContentSize(size); surface.setFrameSize(size); layoutWindow()
        surface.layoutSubtreeIfNeeded()
    }
    func restoreClickRow(_ index: Int) -> Bool {
        func table(in view: NSView) -> NSTableView? {
            if let result = view as? NSTableView { return result }
            return view.subviews.compactMap { table(in: $0) }.first
        }
        guard let grid = table(in: playlist),
              let row = grid.view(atColumn: 0, row: index, makeIfNecessary: true) as? NSButton else { return false }
        row.performClick(nil); return true
    }
}
'''
        if source.name == "PlaylistView.swift":
            text += r'''
// TEST ONLY: expose the cue state without replacing production hover logic.
extension PlaylistRowButton {
    fileprivate var restorePlayCueVisible: Bool { !playButton.isHidden }
    fileprivate var restoreHovered: Bool { hovered }
}

private final class PlaylistHoverFixtureWindow: NSWindow {
    var fixtureKey = true
    var fixturePoint = NSPoint(x: -100, y: -100)
    override var isKeyWindow: Bool { fixtureKey }
    override var mouseLocationOutsideOfEventStream: NSPoint { fixturePoint }
}

extension PlaylistView {
    static func restoreHoverRegressions(clips: [URL]) -> [(Bool, String)] {
        var checks: [(Bool, String)] = []
        func check(_ value: Bool, _ description: String) { checks.append((value, description)) }
        let ownedWindow = PlaylistHoverFixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                                                     styleMask: [.titled], backing: .buffered, defer: false)
        ownedWindow.isReleasedWhenClosed = false
        defer { ownedWindow.close() }
        check(!ownedWindow.isVisible, "hover: the fixture window is never ordered or activated")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        scroll.borderType = .noBorder
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1200))
        scroll.documentView = document
        ownedWindow.contentView!.addSubview(scroll)
        let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: ownedWindow.windowNumber, context: nil,
                                          eventNumber: 0, trackingNumber: 0, userData: nil)!
        for style in [ViewStyle.compact, .gallery] {
            let row = PlaylistRowButton()
            let height = PlaylistRowButton.height(forWidth: 284, style: style)
            row.frame = NSRect(x: 0, y: 0, width: 284, height: height)
            document.addSubview(row)
            scroll.contentView.scroll(to: .zero)
            func configure(_ url: URL = clips[0], selected: Bool = false, current: Bool = false) {
                row.configure(url: url, index: 0, current: current, selected: selected, preview: nil, duration: nil, style: style)
                row.layoutSubtreeIfNeeded()
            }
            func point(_ local: NSPoint) { ownedWindow.fixturePoint = row.convert(local, to: nil) }
            func enter() {
                ownedWindow.fixtureKey = true
                point(NSPoint(x: 100, y: min(40, height / 2)))
                row.mouseEntered(with: event)
            }
            let label = "hover \(style.rawValue)"
            ownedWindow.fixturePoint = NSPoint(x: -100, y: -100)
            configure()
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): an idle unselected row starts without a play cue")
            enter()
            check(row.restorePlayCueVisible && row.restoreHovered, "\(label): the actual local pointer enables the hover cue")
            ownedWindow.fixturePoint = NSPoint(x: -100, y: -100)
            configure()
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): same-URL reload clears stale hover without a mouse-exit event")
            enter(); ownedWindow.fixturePoint = NSPoint(x: -100, y: -100)
            configure(clips[1])
            check(row.representedURL == clips[1] && !row.restorePlayCueVisible && !row.restoreHovered,
                  "\(label): row reuse for another URL clears the previous file's hover")
            enter(); row.frame.origin.y = 250; row.layout()
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): moving a hovered row away from a stationary pointer clears its cue")
            row.frame.origin.y = 0; scroll.contentView.scroll(to: .zero); enter()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: height + 10)); row.refreshHoverState()
            check(!row.restorePlayCueVisible && !row.restoreHovered && row.bounds.intersection(row.visibleRect).isEmpty,
                  "\(label): a card scrolled outside the clip loses hover without exit")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: height / 2))
            point(NSPoint(x: 100, y: height / 4)); row.refreshHoverState()
            check(row.bounds.contains(row.convert(ownedWindow.fixturePoint, from: nil)) && !row.visibleRect.contains(row.convert(ownedWindow.fixturePoint, from: nil))
                    && !row.restorePlayCueVisible && !row.restoreHovered,
                  "\(label): pointer over the clipped portion of a card cannot expose its cue")
            scroll.contentView.scroll(to: .zero); enter(); ownedWindow.fixtureKey = false; row.refreshHoverState()
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): loss of key-window status clears hover")
            ownedWindow.fixtureKey = true; enter(); document.isHidden = true; row.refreshHoverState()
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): a hidden ancestor clears hover")
            document.isHidden = false; enter(); row.removeFromSuperview()
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): detaching a recycled row clears hover")
            document.addSubview(row); ownedWindow.fixturePoint = NSPoint(x: -100, y: -100)
            configure(selected: true)
            check(row.restorePlayCueVisible && !row.restoreHovered, "\(label): the selected noncurrent row retains its single playback cue")
            configure(selected: true, current: true)
            check(!row.restorePlayCueVisible && !row.restoreHovered, "\(label): the current selected row relies on its current-video marker while idle")
            enter()
            check(row.restorePlayCueVisible && row.restoreHovered, "\(label): the current row can still expose a cue under the actual pointer")
            row.removeFromSuperview()
        }
        scroll.removeFromSuperview()

        // Exercise PlaylistView's real clip notification and recycling path.
        // Offscreen recycled views need not repaint until reuse; every visible
        // row must agree with the current pointer after each scroll.
        let list = PlaylistView(frame: NSRect(x: 0, y: 0, width: 284, height: 360))
        ownedWindow.contentView!.addSubview(list)
        let urls = (0..<30).map { clips[$0 % clips.count].deletingLastPathComponent().appendingPathComponent("Hover fixture \($0).mp4") }
        list.update(urls: urls, currentIndex: 0, selectedIndex: 0, hand: .left)
        list.layoutSubtreeIfNeeded()
        list.scrollAfterLayout = false
        list.scrollView.contentView.scroll(to: .zero)
        list.visibleRowsChanged()
        var touched: [PlaylistRowButton] = []
        var hoveredBeforeScroll = 0
        for index in 0..<8 {
            guard let row = list.tableView.view(atColumn: 0, row: index, makeIfNecessary: true) as? PlaylistRowButton else { continue }
            list.tableView.scrollRowToVisible(index)
            let visible = row.bounds.intersection(row.visibleRect)
            ownedWindow.fixturePoint = row.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
            row.mouseEntered(with: event)
            if row.restoreHovered && row.restorePlayCueVisible { hoveredBeforeScroll += 1 }
            touched.append(row)
            // Change the clip while deliberately omitting mouseExited.
            list.tableView.scrollRowToVisible(index + 3)
            list.visibleRowsChanged()
        }
        ownedWindow.fixturePoint = NSPoint(x: -100, y: -100)
        // A never-ordered table materializes row views only when explicitly
        // requested, whereas an on-screen table does so while displaying.
        let visibleCells = (list.visibleRows() ?? 0..<0).compactMap {
            list.tableView.view(atColumn: 0, row: $0, makeIfNecessary: true) as? PlaylistRowButton
        }
        list.visibleRowsChanged()
        check(touched.count == 8 && hoveredBeforeScroll == 8 && !visibleCells.isEmpty && visibleCells.allSatisfy { !$0.restoreHovered && !$0.restorePlayCueVisible },
              "hover: scrolling the real playlist cannot accumulate play cues across reused rows")
        if let index = list.visibleRows()?.first,
           let row = list.tableView.view(atColumn: 0, row: index, makeIfNecessary: true) as? PlaylistRowButton {
            let visible = row.bounds.intersection(row.visibleRect)
            ownedWindow.fixturePoint = row.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
            row.mouseEntered(with: event)
            let cueWasVisible = row.restoreHovered && row.restorePlayCueVisible
            ownedWindow.fixtureKey = false
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: ownedWindow)
            check(cueWasVisible && !row.restoreHovered && !row.restorePlayCueVisible,
                  "hover: the playlist's real window-resign observer clears visible hover cues")
        } else {
            check(false, "hover: a visible playlist row is available for the resign observer regression")
        }
        check(!ownedWindow.isVisible, "hover: all row and clip regressions finish without exposing a native window")
        list.removeFromSuperview()
        return checks
    }
}
'''
        assert "UserDefaults.standard" not in text
        (scratch / source.name).write_text(text)
    fixture_dir = scratch / "fixture"
    fixture_dir.mkdir()
    base = fixture_dir / "Synthetic Episode 1.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=12", "-t", "90", "-an", "-c:v", "libx264", "-preset", "ultrafast", "-g", "12", "-pix_fmt", "yuv420p", str(base)], check=True)
    for number in [2, 3]:
        shutil.copyfile(base, fixture_dir / ("Synthetic Episode %d.mp4" % number))
    for number in [1, 2, 3]:
        (fixture_dir / ("Synthetic Episode %d.en.srt" % number)).write_text("1\n00:00:00,000 --> 00:01:29,000\nSynthetic interaction fixture only.\n")
    include = subprocess.check_output(["pkg-config", "--variable=includedir", "mpv"], text=True).strip()
    lib = subprocess.check_output(["pkg-config", "--variable=libdir", "mpv"], text=True).strip()
    executable = scratch / "InteractionRestoreSmoke"
    args = ["swiftc", "-swift-version", "5", "-suppress-warnings", "-I", str(root / "Sources/CMpv"), "-Xcc", "-I" + include, "-L", lib, "-lmpv", "-framework", "AppKit", "-framework", "OpenGL", "-framework", "CoreAudio"]
    args += [str(scratch / p.name) for p in sources]
    args += [str(fixture / "Smoke.swift"), "-o", str(executable)]
    env = dict(os.environ, LPLAYER_RESTORE_ROOT=str(scratch), LPLAYER_RESTORE_SUITE=suite, LPLAYER_RESTORE_OUT=str(out))
    with (out / "check.log").open("w") as log:
        subprocess.run(args, check=True, stdout=log, stderr=subprocess.STDOUT)
        result = subprocess.run([str(executable), "--no-history"], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=80)
    after = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (out / "source-drift.json").write_text(json.dumps({"unchanged": hashes == after, "changed": [name for name in hashes if hashes[name] != after.get(name)]}, indent=2) + "\n")
    print((out / "check.log").read_text())
    raise SystemExit(result.returncode if hashes == after else 1)
finally:
    shutil.rmtree(scratch)
