import AppKit

enum InteractionFixture {
    static let suite = ProcessInfo.processInfo.environment["LPLAYER_RESTORE_SUITE"]!
    static let preferences = UserDefaults(suiteName: suite)!
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LPLAYER_RESTORE_ROOT"]!)
    static let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LPLAYER_RESTORE_OUT"]!)
}

private final class FixtureKey: NSEvent {
    private let ownedWindow: NSWindow
    private let text: String
    private let repeated: Bool
    private let flags: NSEvent.ModifierFlags
    init(_ text: String, window: NSWindow, repeatKey: Bool = false, modifiers: NSEvent.ModifierFlags = []) {
        self.text = text; ownedWindow = window; repeated = repeatKey; flags = modifiers; super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var type: NSEvent.EventType { .keyDown }
    override var window: NSWindow? { ownedWindow }
    override var characters: String? { text }
    override var charactersIgnoringModifiers: String? { text }
    override var modifierFlags: NSEvent.ModifierFlags { flags }
    override var keyCode: UInt16 { 0 }
    override var isARepeat: Bool { repeated }
}

@main enum InteractionRestoreSmoke {
    static var assertions = 0
    static var failures: [String] = []
    static var outcomes: [[String: Any]] = []
    static var controller: PlayerApp!
    static let up = "\u{f700}", down = "\u{f701}", left = "\u{f702}", right = "\u{f703}", escape = "\u{1b}"

    static func main() { exit(run()) }
    static func run() -> Int32 {
        defer { InteractionFixture.preferences.removePersistentDomain(forName: InteractionFixture.suite) }
        L10n.configure(defaults: InteractionFixture.preferences, applySystemLanguage: false)
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let app = PlayerApp(); controller = app; application.delegate = app
        app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let clips = (1...3).map { InteractionFixture.directory.appendingPathComponent("fixture/Synthetic Episode \($0).mp4") }
        app.restoreOpen(clips)
        wait(5) { app.restoreReady && app.restoreQueueCount == 3 }
        check(app.restoreReady && app.restoreQueueCount == 3, "real controller loads three generated silent fixtures")
        check(!app.restoreWindow.isVisible && application.activationPolicy() == .prohibited && !app.restoreListOpen,
              "controller stays hidden and the playlist starts closed")

        for hand in [HandLayout.left, .right] {
            clearModes()
            app.restoreHandSetup(hand); app.restoreLoadSetup(0)
            wait(3) { app.restoreReady && app.restoreQueueIndex == 0 }
            app.restoreMediaSetup(); wait(1) { app.restoreEngine.snapshot.paused && close(app.restoreEngine.snapshot.volume, 70) }
            let label = hand.rawValue
            let listKey = hand == .left ? "t" : "'"
            let panelKey = hand == .left ? "c" : ","
            let nextSelection = hand == .left ? "s" : "k"
            let moreSpeed = hand == .left ? "d" : "l"
            let helpKey = hand == .left ? "v" : "y"

            key(listKey)
            check(app.restoreListOpen && !app.restorePanelOpen, "\(label): list key opens the exclusive playlist")
            let beforeSelection = app.restoreEngine.snapshot
            key(nextSelection)
            check(app.restoreSelection == 1 && app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, beforeSelection.volume) && abs(app.restoreEngine.snapshot.position - beforeSelection.position) < 0.3 && app.restoreSeekTarget == nil,
                  "\(label): S/K selects silently without main volume or seek changes")
            key("\r"); wait(3) { app.restoreReady && app.restoreQueueIndex == 1 }
            check(app.restoreReady && app.restoreQueueIndex == 1 && app.restoreListOpen, "\(label): Enter plays the selection and keeps the list open")
            let afterPlay = app.restoreEngine.snapshot
            key(nextSelection)
            check(app.restoreSelection == 2 && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, afterPlay.volume) && abs(app.restoreEngine.snapshot.position - afterPlay.position) < 0.3 && app.restoreSeekTarget == nil,
                  "\(label): after Enter the same navigation still selects, never changes volume/seek")
            let clicked = app.restoreClickRow(0)
            wait(3) { app.restoreReady && app.restoreQueueIndex == 0 }
            check(clicked && app.restoreQueueIndex == 0 && app.restoreListOpen, "\(label): the actual row button single action formally plays")

            key(panelKey)
            check(app.restorePanelOpen && !app.restoreListOpen, "\(label): quick-panel key closes the playlist")
            key(listKey)
            check(app.restoreListOpen && !app.restorePanelOpen, "\(label): playlist key closes Quick Controls")
            key(listKey)
            let subtitleBefore = app.restoreEngine.snapshot.subtitlesVisible
            app.restoreClickSubtitle(); wait(1) { app.restoreEngine.snapshot.subtitlesVisible != subtitleBefore }
            check(app.restoreEngine.snapshot.subtitlesVisible != subtitleBefore && !app.restorePanelOpen,
                  "\(label): actual subtitle button toggles visibility directly")
            app.restoreClickSubtitle()
            app.restoreClickSpeed()
            check(app.restorePanelOpen && !app.restoreListOpen && app.restorePanelIndex == 0, "\(label): actual speed button opens Quick Controls at speed")
            key("\r"); wait(1) { close(app.restoreEngine.snapshot.speed, 1) }
            key(moreSpeed); wait(1) { close(app.restoreEngine.snapshot.speed, 1.1) }
            check(close(app.restoreEngine.snapshot.speed, 1.1), "\(label): D/L raises the speed row by 0.1")
            key("\r")

            let expected = ["Playback speed", "Volume", "Video zoom", "Pan sensitivity", "Subtitles", "Subtitle timing", "Audio track", "Subtitle track", "Keyboard layout", "Private playback", "Open video or folder", "Folder access", "Playlist", "Language", "Customize Shortcuts"]
            check(app.restorePanelTitles == expected, "\(label): all original 15 Quick Controls retain their exact order")
            app.restoreSize(NSSize(width: 860, height: 574))
            check(app.restorePanelLayoutValid, "\(label): all 15 rows, four groups and fixed Settings footer have valid minimum-size geometry")

            move(to: 3); key(right)
            check(close(app.restoreSensitivity, 1.25) && close(InteractionFixture.preferences.double(forKey: "videoPanSensitivity"), 1.25), "\(label): sensitivity is reachable and persists through real panel keys")
            key(" ")
            move(to: 8); key(" ")
            check(app.restoreHand != hand && InteractionFixture.preferences.string(forKey: "handLayout") == app.restoreHand.rawValue, "\(label): original layout row switches and persists the hand")
            key(" ")
            move(to: 9); let privateBefore = app.restorePrivate; key(" ")
            check(app.restorePrivate != privateBefore, "\(label): original private-playback row remains reachable")
            key(" ")
            move(to: 10)
            let openReachable = app.restorePanelIndex == 10 && app.restorePanelTitles[10] == "Open video or folder"
            move(to: 11)
            check(openReachable && app.restorePanelIndex == 11 && app.restorePanelTitles[11] == "Folder access", "\(label): file and folder-grant rows are navigable without presenting dialogs")
            move(to: 13); key(right)
            check(L10n.language == .simplifiedChinese && app.restorePanelIndex == 13 && app.restorePanelTitles[13] == "语言", "\(label): original language row changes the live UI")
            key(left)
            move(to: 14)
            check(app.restorePanelIndex == 14 && app.restorePanelTitles[14] == "Customize Shortcuts", "\(label): final original shortcut-editor row is still reachable")
            key(down); let footer = app.restorePanelIndex == 15 && app.restoreFooterSelected
            key(down); let wrapsFirst = app.restorePanelIndex == 0
            key(up)
            check(footer && wrapsFirst && app.restorePanelIndex == 15 && app.restoreFooterRoutesToSettings,
                  "\(label): Settings is the sixteenth target and navigation wraps in both directions")
            move(to: 12); key(" ")
            check(app.restoreListOpen && !app.restorePanelOpen, "\(label): original Playlist Quick action retains its route and exclusivity")
            key(listKey)

            app.restoreLoadSetup(0); wait(3) { app.restoreReady && app.restoreQueueIndex == 0 }
            key(down); wait(3) { app.restoreReady && app.restoreQueueIndex == 1 }
            check(app.restoreQueueIndex == 1, "\(label): playback Down alias switches exactly one video")
            key(down, repeatKey: true)
            let repeatStayed = app.restoreQueueIndex == 1
            key(up); wait(3) { app.restoreReady && app.restoreQueueIndex == 0 }
            key(up)
            check(repeatStayed && app.restoreQueueIndex == 0, "\(label): repeat does not skip files and previous boundary stays at zero")

            app.restoreMediaSetup(); wait(1) { app.restoreEngine.snapshot.paused && close(app.restoreEngine.snapshot.volume, 70) && close(app.restoreEngine.snapshot.speed, 1) }
            let previousVideo = hand == .left ? "w" : "i"
            let nextVideo = hand == .left ? "s" : "k"
            key(nextVideo); wait(3) { app.restoreReady && app.restoreQueueIndex == 1 }
            check(app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 70) && close(app.restoreEngine.snapshot.speed, 1), "\(label): nearby next-video key switches one clip without adjusting speed or volume")
            key(nextVideo, repeatKey: true)
            check(app.restoreQueueIndex == 1, "\(label): held nearby next-video key does not skip additional clips")
            key(previousVideo); wait(3) { app.restoreReady && app.restoreQueueIndex == 0 }
            key(previousVideo)
            check(app.restoreQueueIndex == 0, "\(label): nearby previous-video key returns and stays at first-clip boundary")
            key(nextVideo, modifiers: .shift); wait(1) { close(app.restoreEngine.snapshot.volume, 65) }
            check(app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 65) && close(app.restoreEngine.snapshot.speed, 1), "\(label): Shift plus down key lowers volume without switching video")
            key(previousVideo, modifiers: .shift); wait(1) { close(app.restoreEngine.snapshot.volume, 70) }
            check(app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 70), "\(label): Shift plus up key raises volume without switching video")
            key(down, modifiers: .shift); wait(1) { close(app.restoreEngine.snapshot.volume, 65) }
            key(up, modifiers: .shift); wait(1) { close(app.restoreEngine.snapshot.volume, 70) }
            check(app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 70), "\(label): Shift plus arrow volume mirrors the one-hand direction keys")
            let faster = hand == .left ? "e" : "o"
            let slower = hand == .left ? "q" : "u"
            key(faster); wait(1) { close(app.restoreEngine.snapshot.speed, 1.1) }
            key(slower); wait(1) { close(app.restoreEngine.snapshot.speed, 1) }
            check(app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.speed, 1), "\(label): original Q/E or U/O speed keys remain independent")
            let ignored = key(nextVideo, modifiers: .control)
            check(!ignored && app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 70), "\(label): unbound modifier cannot leak into video or volume action")
            app.restoreMediaSetup(); wait(1) { app.restoreEngine.snapshot.paused && close(app.restoreEngine.snapshot.volume, 70) }
            key(helpKey)
            check(app.restoreHelpOpen && !app.restoreListOpen && !app.restorePanelOpen, "\(label): V/Y opens the nonmodal shortcut reference")
            let referencePosition = app.restoreEngine.snapshot.position
            key(nextSelection, modifiers: .shift); key(moreSpeed)
            wait(2) { close(app.restoreEngine.snapshot.volume, 65) && abs(app.restoreEngine.snapshot.position - referencePosition - 5) < 0.3 }
            check(close(app.restoreEngine.snapshot.volume, 65) && abs(app.restoreEngine.snapshot.position - referencePosition - 5) < 0.3 && app.restoreHelpOpen,
                  "\(label): playback volume and seek remain active while help is visible")
            key(helpKey)
            let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 40)); input.isEditable = true
            app.restoreSurface.addSubview(input); app.restoreWindow.makeFirstResponder(input)
            let editableVolume = app.restoreEngine.snapshot.volume
            let consumed = key(nextSelection)
            check(app.restoreWindow.firstResponder === input && !consumed && close(app.restoreEngine.snapshot.volume, editableVolume), "\(label): editable-input guard rejects playback keys")
            app.restoreWindow.makeFirstResponder(app.restoreSurface); input.removeFromSuperview()
        }
        check(!app.restoreWindow.isVisible && application.activationPolicy() == .prohibited, "verification ends with no visible or activated test window")
        volumePersistence(app, clips: clips)
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let result: [String: Any] = ["allPassed": failures.isEmpty, "assertions": assertions, "failures": failures, "checks": outcomes,
            "scope": "Direct local FixtureKey events enter the actual handleKey. The key-window guard alone is omitted in temporary source; all remaining routing/guards are production code. No physical input or native window activation/Space/sheet positioning is claimed.",
            "privacy": "Three generated silent clips, isolated UserDefaults suite removed on exit, scratch history/grants, prohibited hidden owned window. No user media/screens/windows/global input."]
        try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: InteractionFixture.output.appendingPathComponent("results.json"))
        print("\(failures.isEmpty ? "PASS" : "FAIL") interaction restoration: \(assertions) assertions, \(failures.count) failures")
        return failures.isEmpty ? 0 : 1
    }

    static func volumePersistence(_ app: PlayerApp, clips: [URL]) {
        clearModes(); app.restoreHandSetup(.left)
        app.restoreLoadSetup(0)
        wait(3) { app.restoreReady && app.restoreQueueIndex == 0 }
        let legacyVolumes: [Double] = [11, 83, 26]
        let records = clips.enumerated().map { index, url in
            PlaybackBookmark(path: url.path, position: Double(7 + index * 5), duration: 30, speed: 1, volume: legacyVolumes[index])
        }
        app.restoreHistorySetup(records)
        check(!app.restorePrivate && app.restoreHistory.count == 3 && Set(app.restoreHistory.map { $0.volume }) == Set(legacyVolumes),
              "volume: normal history fixture contains three distinct per-file legacy volumes")
        let slider47 = app.restoreVolumeSlider(47)
        wait(1) { close(app.restoreEngine.snapshot.volume, 47) }
        check(slider47 && close(app.restoreGlobalVolume, 47) && close(app.restoreEngine.snapshot.volume, 47) && close(InteractionFixture.preferences.double(forKey: "playbackVolume"), 47),
              "volume: actual transport slider sets and persists the global 47 percent level")

        key("s"); wait(3) { app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 47) }
        check(app.restoreReady && app.restoreQueueIndex == 1 && app.restoreEngine.snapshot.position > 10 && close(app.restoreEngine.snapshot.volume, 47),
              "volume: S resumes the next history position without restoring its old 83 percent level")
        key("w"); wait(3) { app.restoreReady && app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 47) }
        check(app.restoreReady && app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 47),
              "volume: W returns to the previous video at the same global 47 percent level")
        key("t")
        let clicked = app.restoreClickRow(2)
        wait(3) { app.restoreReady && app.restoreQueueIndex == 2 && close(app.restoreEngine.snapshot.volume, 47) }
        check(clicked && app.restoreReady && app.restoreQueueIndex == 2 && app.restoreEngine.snapshot.position > 15 && close(app.restoreEngine.snapshot.volume, 47),
              "volume: actual playlist row action resumes history without restoring its old 26 percent level")
        key("w"); key("\r")
        wait(3) { app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 47) }
        check(app.restoreReady && app.restoreQueueIndex == 1 && app.restoreListOpen && close(app.restoreEngine.snapshot.volume, 47),
              "volume: playlist selection and Enter retain the global level and list mode")
        key("t")

        // Deliberately do not pump the run loop between these real commands:
        // the backend snapshot may still lag the latest accepted volume target.
        let raises = (0..<3).map { _ in app.restoreKey(FixtureKey("w", window: app.restoreWindow, modifiers: .shift)) }
        let switched = app.restoreKey(FixtureKey("s", window: app.restoreWindow))
        check(raises.allSatisfy { $0 } && switched && close(app.restoreGlobalVolume, 62) && close(InteractionFixture.preferences.double(forKey: "playbackVolume"), 62),
              "volume: rapid Shift-W commands persist 62 percent before an immediate S load")
        wait(3) { app.restoreReady && app.restoreQueueIndex == 2 && close(app.restoreEngine.snapshot.volume, 62) }
        check(app.restoreReady && app.restoreQueueIndex == 2 && close(app.restoreEngine.snapshot.volume, 62),
              "volume: immediate switching preserves the newest target rather than a stale engine snapshot")

        let slider0 = app.restoreVolumeSlider(0)
        wait(1) { close(app.restoreEngine.snapshot.volume, 0) }
        key("w"); wait(3) { app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 0) }
        check(slider0 && app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreGlobalVolume, 0) && close(app.restoreEngine.snapshot.volume, 0) && InteractionFixture.preferences.object(forKey: "playbackVolume") != nil && close(InteractionFixture.preferences.double(forKey: "playbackVolume"), 0),
              "volume: an explicit zero slider level survives switching and is stored as zero")

        key("n", modifiers: .command)
        app.restoreFlushHistory()
        let historyBefore = app.restoreHistory
        let historyURL = InteractionFixture.directory.appendingPathComponent("history/history.json")
        let bytesBefore = try? Data(contentsOf: historyURL)
        check(app.restorePrivate && bytesBefore != nil, "volume: private checks start after a flushed normal-history boundary")
        let privateSlider = app.restoreVolumeSlider(31)
        wait(1) { close(app.restoreEngine.snapshot.volume, 31) }
        key("s"); wait(3) { app.restoreReady && app.restoreQueueIndex == 2 && close(app.restoreEngine.snapshot.volume, 31) }
        key("w"); wait(3) { app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 31) }
        check(privateSlider && app.restorePrivate && app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 31),
              "volume: private playback keeps the global level through both S and W switching")
        key("t")
        let privateClick = app.restoreClickRow(0)
        wait(3) { app.restoreReady && app.restoreQueueIndex == 0 && close(app.restoreEngine.snapshot.volume, 31) }
        key("s"); key("\r")
        wait(3) { app.restoreReady && app.restoreQueueIndex == 1 && close(app.restoreEngine.snapshot.volume, 31) }
        check(privateClick && app.restoreReady && app.restoreQueueIndex == 1 && app.restoreListOpen && close(app.restoreEngine.snapshot.volume, 31),
              "volume: private mouse and Enter routes preserve the same 31 percent level")
        key("t")
        app.restoreFlushHistory()
        check(app.restoreHistory == historyBefore && (try? Data(contentsOf: historyURL)) == bytesBefore && close(InteractionFixture.preferences.double(forKey: "playbackVolume"), 31),
              "volume: private adjustments persist only the global preference, with history memory and file unchanged")
        _ = app.restoreVolumeSlider(0)
        wait(1) { close(app.restoreEngine.snapshot.volume, 0) }
        key("s"); wait(3) { app.restoreReady && app.restoreQueueIndex == 2 && close(app.restoreEngine.snapshot.volume, 0) }
        check(app.restoreReady && app.restoreQueueIndex == 2 && close(app.restoreEngine.snapshot.volume, 0),
              "volume: private switching also preserves an explicitly muted zero level")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        check(app.restoreHistory == historyBefore && (try? Data(contentsOf: historyURL)) == bytesBefore,
              "volume: terminating the private controller leaves media history unchanged")

        let restarted = PlayerApp(); controller = restarted; NSApplication.shared.delegate = restarted
        restarted.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        // Engine snapshots intentionally ignore property events while no media
        // is bound. Check the restored setting here, then the actual loaded
        // engine below rather than treating an idle snapshot as authoritative.
        check(close(restarted.restoreGlobalVolume, 0) && InteractionFixture.preferences.object(forKey: "playbackVolume") != nil && close(InteractionFixture.preferences.double(forKey: "playbackVolume"), 0),
              "volume: a fresh controller restores the saved zero level from the same isolated preference suite")
        restarted.restorePrivateSetup(false)
        let oldBookmark = restarted.restoreHistory.first { $0.path == clips[0].path }
        restarted.restoreOpen(clips)
        wait(3) { restarted.restoreReady && restarted.restoreQueueIndex == 0 && close(restarted.restoreEngine.snapshot.volume, 0) }
        check(oldBookmark != nil && oldBookmark!.volume > 0 && restarted.restoreReady && close(restarted.restoreEngine.snapshot.volume, 0),
              "volume: after restart, normal resume keeps zero even when the file history contains a nonzero legacy volume")
        check(!restarted.restoreWindow.isVisible && NSApplication.shared.activationPolicy() == .prohibited,
              "volume: restarting the owned controller never presents or activates a test window")
    }

    @discardableResult static func key(_ text: String, repeatKey: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        let consumed = controller.restoreKey(FixtureKey(text, window: controller.restoreWindow, repeatKey: repeatKey, modifiers: modifiers))
        pump(0.025); return consumed
    }
    static func clearModes() { for _ in 0..<3 { key(escape) } }
    static func move(to index: Int) {
        for _ in 0..<16 {
            if controller.restorePanelIndex == index { return }
            key(down)
        }
    }
    static func check(_ value: Bool, _ message: String) {
        assertions += 1; outcomes.append(["passed": value, "message": message])
        print("\(value ? "PASS" : "FAIL") \(message)")
        if !value { failures.append(message) }
    }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.02 }
    static func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01))) }
    }
    static func wait(_ seconds: Double, until predicate: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < end { pump(0.02) }
    }
}
