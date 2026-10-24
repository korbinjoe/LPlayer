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
        assert "UserDefaults.standard" not in text
        (scratch / source.name).write_text(text)
    fixture_dir = scratch / "fixture"
    fixture_dir.mkdir()
    base = fixture_dir / "Synthetic Episode 1.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=12", "-t", "30", "-an", "-c:v", "libx264", "-preset", "ultrafast", "-g", "12", "-pix_fmt", "yuv420p", str(base)], check=True)
    for number in [2, 3]:
        shutil.copyfile(base, fixture_dir / ("Synthetic Episode %d.mp4" % number))
    for number in [1, 2, 3]:
        (fixture_dir / ("Synthetic Episode %d.en.srt" % number)).write_text("1\n00:00:00,000 --> 00:00:29,000\nSynthetic interaction fixture only.\n")
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
