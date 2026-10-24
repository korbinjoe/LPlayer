import Foundation
import Darwin

/// Runs the real, platform-independent application logic without XCTest or Xcode.
/// Every fixture lives in a temporary folder and is removed even on failure.
@main
enum CoreChecks {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    private static func fixture(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PalmPlayer-CoreChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static func check(_ name: String, _ body: () throws -> Void) throws {
        try body()
        print("PASS \(name)")
    }

    static func main() {
        do {
            try check("playback preferences and subtitle visibility round-trip", restoration)
            try check("legacy history without subtitle visibility", legacyHistory)
            try check("private sessions leave memory and disk untouched", privateHistory)
            try check("bounded history, deduplication, removal and clearing", boundedHistory)
            try check("invalid numbers and damaged history recovery", damagedHistory)
            try check("non-recursive natural folder order and explicit file order", queues)
            try check("left/right keyboard layouts and panel navigation", keyboard)
            try check("playlist keyboard focus, selection and playback shortcuts", playlistKeyboard)
            try check("shortcut modifier matching and fixed navigation", shortcutModifiers)
            try check("custom shortcut validation, clearing and defaults", shortcutCustomization)
            try check("shortcut persistence and damaged configuration recovery", shortcutPersistence)
            try check("one-hand video defaults and lossless v1 shortcut migration", shortcutPresetMigration)
            try check("zoom defaults, remapping and lossless v1/v2 migration", zoomShortcuts)
            try check("playback time formatting", timeFormatting)
            try check("immediate and sustained seek input without stale trailing work", seekScheduling)
            print("All 15 core check groups passed.")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func restoration() throws {
        try fixture { directory in
            let video = directory.appendingPathComponent("Movie.mkv")
            let bookmark = PlaybackBookmark(
                path: video.path, name: "Movie", position: 125.5, duration: 4_000,
                speed: 1.25, volume: 47, subtitleDelay: -0.25, subtitleID: 2, audioID: 3,
                updatedAt: Date(), subtitlesVisible: false
            )
            LibraryStore(directory: directory).save(bookmark)
            let restored = LibraryStore(directory: directory).entry(for: video)
            try require(restored == bookmark, "Saved progress and playback preferences did not round-trip exactly")
            try require(restored?.subtitlesVisible == false, "Disabled subtitles were re-enabled")
            try require(PlaybackBookmark(path: video.path).subtitlesVisible, "New bookmarks should show subtitles by default")
        }
    }

    private static func legacyHistory() throws {
        try fixture { directory in
            let video = directory.appendingPathComponent("Older.mkv")
            let bookmark = PlaybackBookmark(path: video.path, position: 45)
            var records = try JSONSerialization.jsonObject(with: JSONEncoder().encode([bookmark])) as! [[String: Any]]
            records[0].removeValue(forKey: "subtitlesVisible")
            try JSONSerialization.data(withJSONObject: records)
                .write(to: directory.appendingPathComponent("history.json"))
            let restored = LibraryStore(directory: directory).entry(for: video)
            try require(restored == bookmark, "An older history entry could not be restored")
            try require(restored?.subtitlesVisible == true, "Missing subtitle visibility must default to true")
        }
    }

    private static func privateHistory() throws {
        try fixture { directory in
            let fresh = LibraryStore(directory: directory)
            fresh.isPrivate = true
            fresh.save(PlaybackBookmark(path: directory.appendingPathComponent("Private.mp4").path))
            let history = directory.appendingPathComponent("history.json")
            try require(fresh.recent.isEmpty, "A private-only session created an in-memory history entry")
            try require(!FileManager.default.fileExists(atPath: history.path), "A private-only session created a history file")

            let store = LibraryStore(directory: directory)
            let original = PlaybackBookmark(path: directory.appendingPathComponent("Original.mp4").path, position: 12)
            store.save(original)
            let before = try Data(contentsOf: history)
            store.isPrivate = true
            store.save(PlaybackBookmark(path: original.path, position: 90))
            store.remove(path: original.path)
            store.clear()
            let after = try Data(contentsOf: history)
            try require(store.recent == [original], "Private operations changed the existing in-memory history")
            try require(after == before, "Private operations changed the history file")
            try require(LibraryStore(directory: directory).recent == [original], "Private operations changed restored history")
        }
    }

    private static func boundedHistory() throws {
        try fixture { directory in
            let store = LibraryStore(directory: directory)
            for index in 0..<35 {
                store.save(PlaybackBookmark(
                    path: directory.appendingPathComponent("Episode \(index).mkv").path,
                    updatedAt: Date(timeIntervalSince1970: Double(index))
                ))
            }
            try require(store.recent.count == 30, "History exceeded its 30-entry limit")
            try require(store.recent.first?.name == "Episode 34.mkv", "Newest history entry was not first")
            try require(store.recent.last?.name == "Episode 5.mkv", "History retained the wrong oldest entry")
            let existing = directory.appendingPathComponent("Episode 10.mkv")
            store.save(PlaybackBookmark(path: existing.path, position: 42, updatedAt: Date(timeIntervalSince1970: 100)))
            try require(store.recent.count == 30 && store.recent.first?.path == existing.path, "Reopened video was not promoted without duplicating it")
            try require(LibraryStore(directory: directory).recent == store.recent, "History order changed after reopening")
            store.remove(path: existing.path)
            try require(LibraryStore(directory: directory).entry(for: existing) == nil, "Removed video reappeared after reopening")
            store.clear()
            try require(LibraryStore(directory: directory).recent.isEmpty, "Cleared history reappeared after reopening")
        }
    }

    private static func damagedHistory() throws {
        try fixture { directory in
            let history = directory.appendingPathComponent("history.json")
            try Data("invalid or interrupted JSON".utf8).write(to: history)
            let store = LibraryStore(directory: directory)
            try require(store.recent.isEmpty, "Damaged history must be ignored")
            let valid = PlaybackBookmark(path: directory.appendingPathComponent("Recovered.mp4").path, position: 20)
            store.save(valid)
            for position in [Double.nan, Double.infinity, -Double.infinity, -1] {
                var invalid = valid; invalid.position = position; store.save(invalid)
            }
            for keyPath in [\PlaybackBookmark.duration, \.speed, \.volume, \.subtitleDelay] {
                var invalid = valid; invalid[keyPath: keyPath] = .infinity; store.save(invalid)
            }
            var zeroSpeed = valid; zeroSpeed.speed = 0; store.save(zeroSpeed)
            try require(store.recent == [valid], "An invalid playback value replaced a valid entry")
            try require(LibraryStore(directory: directory).recent == [valid], "History did not recover after the next valid save")
        }
    }

    private static func queues() throws {
        try fixture { directory in
            let folder = directory.appendingPathComponent("Season", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["Episode 10.mkv", "Episode 2.MP4", "Episode 1.mov", "notes.txt", ".hidden.mp4"] {
                try Data().write(to: folder.appendingPathComponent(name))
            }
            let nested = folder.appendingPathComponent("Nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data().write(to: nested.appendingPathComponent("Episode 3.mp4"))
            let natural = LibraryStore.playableURLs(from: [folder])
            try require(natural.map(\.lastPathComponent) == ["Episode 1.mov", "Episode 2.MP4", "Episode 10.mkv"], "Folder queue was recursive or not naturally sorted")
            let first = natural[0], second = natural[1]
            let explicit = LibraryStore.playableURLs(from: [second, first, second, folder.appendingPathComponent("notes.txt"), URL(string: "https://example.com/movie.mp4")!])
            try require(explicit == [second, first], "Explicit file order, video filtering or deduplication failed")

            let episodes = directory.appendingPathComponent("Episodes", isDirectory: true)
            try FileManager.default.createDirectory(at: episodes, withIntermediateDirectories: true)
            let episode1 = episodes.appendingPathComponent("Episode 1.mkv")
            let episode2 = episodes.appendingPathComponent("Episode 2.mkv")
            let episode10 = episodes.appendingPathComponent("Episode 10.mkv")
            for url in [episode10, episode2, episode1] { try Data().write(to: url) }
            let extraFolder = episodes.appendingPathComponent("Other season", isDirectory: true)
            try FileManager.default.createDirectory(at: extraFolder, withIntermediateDirectories: true)
            try Data().write(to: extraFolder.appendingPathComponent("Episode 3.mkv"))

            let single = LibraryStore.initialQueue(from: [episode2])
            try require(single.urls == [episode2] && single.index == 0, "A single file unexpectedly enumerated its parent directory")
            let authorizedSingle = LibraryStore.initialQueue(from: [episode2], allowSiblingAccess: { $0 == episodes })
            try require(authorizedSingle.urls == [episode1, episode2, episode10] && authorizedSingle.index == 1, "Directory-authorized episode did not discover naturally sorted siblings at the selected index")
            let multiple = LibraryStore.initialQueue(from: [episode2, episode1])
            try require(multiple.urls == [episode2, episode1] && multiple.index == 0, "Explicit multiple selections were reordered or expanded")
            let selectedFolder = LibraryStore.initialQueue(from: [episodes])
            try require(selectedFolder.urls == [episode1, episode2, episode10] && selectedFolder.index == 0, "Opening a folder did not start at its first immediate video")
        }
    }

    private static func keyboard() throws {
        let layouts: [(HandLayout, [(String, PlayerCommand)], [String])] = [
            (.left, [(" ", .togglePause), ("a", .seek(-5)), ("d", .seek(5)), ("w", .previousFile), ("s", .nextFile), ("q", .speed(-0.1)), ("e", .speed(0.1)), ("r", .resetSpeed), ("f", .fullscreen), ("g", .subtitles), ("z", .undoSeek), ("c", .panel), ("v", .help), ("t", .playlist)], ["w", "s", "a", "d"]),
            (.right, [(" ", .togglePause), ("j", .seek(-5)), ("l", .seek(5)), ("i", .previousFile), ("k", .nextFile), ("u", .speed(-0.1)), ("o", .speed(0.1)), ("p", .resetSpeed), ("h", .fullscreen), (";", .subtitles), ("m", .undoSeek), (",", .panel), ("y", .help), ("b", .playlist)], ["i", "k", "j", "l"])
        ]
        for (layout, mappings, navigation) in layouts {
            for (key, expected) in mappings {
                try require(layout.command(for: key) == expected, "Incorrect \(layout.rawValue) shortcut for \(key)")
            }
            try require(layout.command(for: "\u{f700}") == .previousFile, "Up should play the previous video")
            try require(layout.command(for: "\u{f701}") == .nextFile, "Down should play the next video")
            try require(layout.command(for: "\u{f700}", shift: true) == .volume(5) && layout.command(for: "\u{f701}", shift: true) == .volume(-5), "Shift arrows should adjust volume")
            try require(layout.command(for: navigation[2].uppercased(), shift: true) == .seek(-30), "Shift + backward should seek 30 seconds")
            try require(layout.command(for: navigation[3], shift: true) == .seek(30), "Shift + forward should seek 30 seconds")
            let expected: [PlayerCommand] = [.panelMove(-1), .panelMove(1), .panelAdjust(-1), .panelAdjust(1)]
            for (key, command) in zip(navigation, expected) {
                try require(layout.command(for: key, panelOpen: true) == command, "Panel keys leaked into playback controls")
            }
            for key in [" ", "\r"] {
                try require(layout.command(for: key, panelOpen: true) == .panelActivate, "Panel confirmation key failed")
            }
            for (key, command) in [("\u{f700}", PlayerCommand.panelMove(-1)), ("\u{f701}", .panelMove(1)), ("\u{f702}", .panelAdjust(-1)), ("\u{f703}", .panelAdjust(1))] {
                try require(layout.command(for: key, panelOpen: true) == command, "Panel arrow navigation failed")
            }
            try require(layout.command(for: "\u{1b}") == .escape, "Escape key failed")
            try require(layout.command(for: "?") == .help, "Help key failed")
            try require(layout.command(for: "/") == .help, "Slash help alias failed")
            try require(layout.command(for: "0") == .resetZoom, "Fit-window reset key failed")
            try require(layout.command(for: "0", panelOpen: true) == .resetZoom, "Fit-window reset failed with panel open")
            for (key, command) in [(layout.helpKey, PlayerCommand.help)] {
                try require(layout.command(for: key) == command, "Shortcut label does not match its command")
                try require(layout.command(for: key, panelOpen: true) == command, "Global reminder or video shortcut failed with panel open")
            }
            try require(layout.command(for: "2") == nil, "Unknown key triggered an action")
        }
    }

    private static func playlistKeyboard() throws {
        let layouts: [(HandLayout, String, String)] = [(.left, "w", "s"), (.right, "i", "k")]
        for (layout, up, down) in layouts {
            try require(layout.command(for: layout.playlistKey) == .playlist, "Playlist hint does not match its toggle")
            try require(layout.command(for: layout.playlistKey, panelOpen: true) == .playlist, "Quick panel trapped the playlist toggle")
            try require(layout.command(for: layout.playlistKey, playlistOpen: true) == .playlist, "Playlist toggle could not close its own panel")
            for (key, command) in [(up, PlayerCommand.playlistMove(-1)), (down, .playlistMove(1)), ("\u{f700}", .playlistMove(-1)), ("\u{f701}", .playlistMove(1))] {
                try require(layout.command(for: key.uppercased(), shift: true, playlistOpen: true) == command, "Playlist selection leaked into volume control")
                try require(layout.command(for: key, panelOpen: true, playlistOpen: true) == command, "Playlist context did not take priority over quick-panel focus")
            }
            let back = layout == .left ? "a" : "j", forward = layout == .left ? "d" : "l"
            for (key, delta) in [(back, -5.0), (forward, 5.0), ("\u{f702}", -5.0), ("\u{f703}", 5.0)] {
                try require(layout.command(for: key, panelOpen: true, playlistOpen: true) == .seek(delta), "Playlist trapped horizontal playback seeking")
                try require(layout.command(for: key.uppercased(), shift: true, panelOpen: true, playlistOpen: true) == .seek(delta * 6), "Playlist trapped Shift horizontal seeking")
            }
            for key in [" ", "\r", "\u{3}"] {
                try require(layout.command(for: key, panelOpen: true, playlistOpen: true) == .playlistActivate, "Playlist confirmation paused playback or changed the quick panel")
            }
            try require(layout.command(for: "\u{f729}", playlistOpen: true) == .playlistBoundary(false), "Home did not select the first video")
            try require(layout.command(for: "\u{f72b}", playlistOpen: true) == .playlistBoundary(true), "End did not select the last video")
            for (key, command) in [(layout.helpKey, PlayerCommand.help), (layout.panelKey, .panel), ("\u{1b}", .escape), ("0", .resetZoom)] {
                try require(layout.command(for: key, playlistOpen: true) == command, "An existing global shortcut was trapped by the playlist")
            }
            try require(layout.command(for: up) == .previousFile && layout.command(for: down) == .nextFile, "Closing the playlist did not restore video keys")
            try require(layout.command(for: up, shift: true) == .volume(5) && layout.command(for: down, shift: true) == .volume(-5), "Closing the playlist did not restore shifted volume keys")
            try require(layout.command(for: " ") == .togglePause, "Closing the playlist did not restore pause")
        }
        try require(HandLayout.left.command(for: "s", playlistOpen: true) == .playlistMove(1), "Left-hand next-video key did not become playlist navigation")
        try require(HandLayout.right.command(for: "p", playlistOpen: true) == .resetSpeed, "Right-hand reset-speed key changed")
        try shortcutFixture { defaults in
            let store = ShortcutStore(defaults: defaults)
            for hand in [HandLayout.left, .right] {
                let back = hand == .left ? "a" : "j", forward = hand == .left ? "d" : "l"
                for (action, key, command) in [
                    (ShortcutAction.seekBackward, "2", PlayerCommand.seek(-5)),
                    (.seekForward, "3", .seek(5)), (.seekBackwardLarge, "4", .seek(-30)), (.seekForwardLarge, "5", .seek(30))
                ] {
                    try require(store.setBinding(KeyChord(key), for: action, hand: hand) == nil, "Could not remap a seek action")
                    try require(store.command(for: KeyChord(key), hand: hand, context: .playlist) == command, "Playlist did not honor a customized seek key")
                }
                try require(store.setBinding(KeyChord(back), for: .mute, hand: hand) == nil, "Could not borrow the freed backward key")
                try require(store.setBinding(KeyChord(forward), for: .resetSpeed, hand: hand) == nil, "Could not borrow the freed forward key")
                try require(store.command(for: KeyChord(back), hand: hand, context: .playlist) == .mute, "Playlist hardcoded seeking over a borrowed horizontal key")
                try require(store.command(for: KeyChord(forward), hand: hand, context: .playlist) == .resetSpeed, "Playlist ignored a customized horizontal action")
                try require(store.command(for: KeyChord(back, modifiers: .shift), hand: hand, context: .playlist) == nil && store.command(for: KeyChord(forward, modifiers: .shift), hand: hand, context: .playlist) == nil, "Playlist revived removed Shift seeking bindings")
                try require(store.command(for: KeyChord("Left"), hand: hand, context: .playlist) == .seek(-5) && store.command(for: KeyChord("Right", modifiers: .shift), hand: hand, context: .playlist) == .seek(30), "Customizing seek keys disabled fixed arrow aliases in the playlist")
                try require(store.command(for: KeyChord(back), hand: hand, context: .panel) == .panelAdjust(-1) && store.command(for: KeyChord(forward), hand: hand, context: .panel) == .panelAdjust(1), "Playlist seeking change displaced Quick Controls adjustment")
            }
        }
    }

    private static func shortcutFixture(_ body: (UserDefaults) throws -> Void) throws {
        let name = "LPlayer-ShortcutChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private static func shortcutModifiers() throws {
        try require(KeyChord("?") == KeyChord("/", modifiers: .shift), "Question mark was not normalized")
        try require(KeyChord("A") == KeyChord("a"), "Uppercase synthesized a modifier")
        try require(KeyChord("+", modifiers: .option) == KeyChord("=", modifiers: [.shift, .option]), "Shifted punctuation did not normalize")
        try require(KeyChord("\u{3}") == KeyChord("\r"), "Keypad Enter differed from Return")
        try require(KeyChord("F7").display == "F7", "Function-key normalization failed")
        try require(KeyChord("l", modifiers: [.command, .shift]).display == "⇧⌘L", "Modifier display order changed")
        try shortcutFixture { defaults in
            let store = ShortcutStore(defaults: defaults)
            for hand in [HandLayout.left, .right] {
                for action in ShortcutAction.allCases {
                    if let key = ShortcutStore.defaultBinding(for: action, hand: hand) {
                        try require(store.command(for: key, hand: hand, context: .playback) != nil, "A shipped default did not resolve: \(action)")
                    }
                    for key in store.aliases(for: action, hand: hand) {
                        try require(store.command(for: key, hand: hand, context: .playback) != nil, "A fixed alias did not resolve: \(action)")
                    }
                }
                let previous = hand == .left ? "w" : "i", next = hand == .left ? "s" : "k"
                let back = hand == .left ? "a" : "j", forward = hand == .left ? "d" : "l"
                for (key, arrow) in [(previous, "Up"), (next, "Down"), (back, "Left"), (forward, "Right")] {
                    for context in [ShortcutContext.playback, .panel, .playlist] {
                        try require(store.command(for: KeyChord(key), hand: hand, context: context) == store.command(for: KeyChord(arrow), hand: hand, context: context), "The hand navigation cluster differed from its corresponding arrow in \(context)")
                        try require(store.command(for: KeyChord(key, modifiers: .shift), hand: hand, context: context) == store.command(for: KeyChord(arrow, modifiers: .shift), hand: hand, context: context), "The shifted hand navigation cluster differed from its corresponding shifted arrow in \(context)")
                    }
                }
                for (key, volume, direction) in [(previous, PlayerCommand.volume(5), -1), (next, .volume(-5), 1)] {
                    try require(store.command(for: KeyChord(key, modifiers: .shift), hand: hand, context: .playback) == volume, "Shift did not distinguish volume from video switching")
                    try require(store.command(for: KeyChord(key, modifiers: .shift), hand: hand, context: .panel) == .panelMove(direction), "Shift volume displaced quick-panel navigation")
                    try require(store.command(for: KeyChord(key, modifiers: .shift), hand: hand, context: .playlist) == .playlistMove(direction), "Shift volume displaced playlist navigation")
                    for modifier: ShortcutModifiers in [.option, .control, .command, [.shift, .option], [.shift, .control], [.shift, .command]] {
                        try require(store.command(for: KeyChord(key, modifiers: modifier), hand: hand, context: .playback) == nil, "Video and volume keys ignored exact modifiers")
                    }
                }
                for (key, speed) in [(hand == .left ? "q" : "u", PlayerCommand.speed(-0.1)), (hand == .left ? "e" : "o", .speed(0.1))] {
                    for context in [ShortcutContext.playback, .panel, .playlist] {
                        try require(store.command(for: KeyChord(key), hand: hand, context: context) == speed, "Original plain speed keys changed with context")
                        try require(store.command(for: KeyChord(key, modifiers: .shift), hand: hand, context: context) == nil, "A shifted speed key triggered a plain command")
                    }
                }
                for key in hand == .left ? ["x", "b"] : ["n", "."] {
                    try require(store.command(for: KeyChord(key), hand: hand, context: .playback) == nil, "Retired video keys remained reserved")
                }
                try require(store.command(for: KeyChord("?"), hand: hand, context: .playback) == .help, "Question-mark help failed")
                for (key, playback, panel, playlist) in [
                    (KeyChord("Up"), PlayerCommand.previousFile, PlayerCommand.panelMove(-1), PlayerCommand.playlistMove(-1)),
                    (KeyChord("Down"), .nextFile, .panelMove(1), .playlistMove(1))
                ] {
                    try require(store.command(for: key, hand: hand, context: .playback) == playback, "Playback arrows did not switch video")
                    try require(store.command(for: key, hand: hand, context: .panel) == panel, "Video arrows displaced quick-panel navigation")
                    try require(store.command(for: key, hand: hand, context: .playlist) == playlist, "Video arrows displaced playlist navigation")
                    try require(store.setBinding(key, for: .volumeUp, hand: hand) != nil, "Volume reclaimed a reserved video arrow")
                }
                try require(store.setBinding(nil, for: .previousFile, hand: hand) == nil && store.setBinding(nil, for: .nextFile, hand: hand) == nil, "Could not clear editable video bindings")
                try require(store.command(for: KeyChord("Up"), hand: hand, context: .playback) == .previousFile && store.command(for: KeyChord("Down"), hand: hand, context: .playback) == .nextFile, "Customizing video bindings removed shared arrows")
                try require(store.command(for: KeyChord("[", modifiers: .command), hand: hand, context: .playback) == .previousFile && store.command(for: KeyChord("]", modifiers: .command), hand: hand, context: .playback) == .nextFile, "Command-bracket video aliases changed")
                try require(store.command(for: KeyChord("\u{f702}", modifiers: .shift), hand: hand, context: .playback) == .seek(-30), "Shift-arrow large seek failed")
                try require(store.command(for: KeyChord("o", modifiers: [.command, .shift]), hand: hand, context: .playback) == nil, "Folder-access menu shortcut was intercepted")
            }
            try require(store.binding(for: .playlist, hand: .right) == KeyChord("'"), "Right-hand playlist was not moved near the hand cluster")
            try require(store.command(for: KeyChord("b"), hand: .right, context: .playback) == .playlist, "Right-hand legacy playlist alias was lost")
            try require(store.setBinding(KeyChord("2"), for: .volumeUp, hand: .left) == nil, "Volume remap failed")
            try require(store.setBinding(KeyChord("w"), for: .mute, hand: .left) == nil, "Reusing a freed primary failed")
            try require(store.command(for: KeyChord("w"), hand: .left, context: .playback) == .mute, "Playback did not honor the remapped key")
            try require(store.command(for: KeyChord("w"), hand: .left, context: .panel) == .panelMove(-1), "Custom playback key displaced panel navigation")
            try require(store.command(for: KeyChord("w", modifiers: .shift), hand: .left, context: .playlist) == .playlistMove(-1), "Shift navigation changed playback inside playlist")
            try require(store.command(for: KeyChord("a"), hand: .left, context: .playlist) == .seek(-5), "Playlist horizontal key did not seek the video")
            try require(store.command(for: KeyChord(" "), hand: .left, context: .playlist) == .playlistActivate, "Space did not activate selected video")
        }
    }

    private static func shortcutCustomization() throws {
        try shortcutFixture { defaults in
            let store = ShortcutStore(defaults: defaults)
            var notifications = 0
            store.onChange = { notifications += 1 }
            try require(!store.hasCustomizations(hand: .left), "New configuration was already customized")
            try require(store.setBinding(nil, for: .volumeUp, hand: .left) == nil, "Navigation-key fixture could not clear volume")
            try require(store.setBinding(KeyChord("w"), for: .playlist, hand: .left) != nil, "Playlist accepted a toggle key that its own navigation consumes")
            try require(store.setBinding(KeyChord("w", modifiers: .shift), for: .playlist, hand: .left) != nil, "Playlist accepted a Shift navigation toggle")
            try require(store.setBinding(nil, for: .playPause, hand: .left) == nil, "Space fixture could not clear playback")
            try require(store.setBinding(KeyChord(" "), for: .panel, hand: .left) != nil, "Quick Controls accepted a toggle key consumed by activation")
            try require(store.setBinding(KeyChord("w", modifiers: .option), for: .playlist, hand: .left) == nil, "Option navigation key was unnecessarily reserved")
            try require(store.command(for: KeyChord("w", modifiers: .option), hand: .left, context: .playlist) == .playlist, "Modified playlist toggle could not close its own sidebar")
            try require(store.setBinding(KeyChord("i", modifiers: .command), for: .panel, hand: .right) == nil, "Command navigation key was unnecessarily reserved")
            try require(store.command(for: KeyChord("i", modifiers: .command), hand: .right, context: .panel) == .panel, "Modified panel toggle could not close its own panel")
            store.resetAll(hand: .left)
            store.resetAll(hand: .right)
            try require(store.setBinding(KeyChord("2", modifiers: .option), for: .mute, hand: .left) == nil, "An available key could not be assigned")
            try require(store.label(for: .mute, hand: .left) == "⌥2", "Shortcut label did not reflect the edit")
            try require(store.command(for: KeyChord("2", modifiers: .option), hand: .left, context: .playback) == .mute, "Customized command did not resolve")
            try require(store.command(for: KeyChord("2"), hand: .left, context: .playback) == nil, "Custom key ignored modifier exactness")
            let saved = defaults.data(forKey: ShortcutStore.storageKey), notice = notifications
            for bad in [KeyChord("a"), KeyChord("2", modifiers: .option), KeyChord("l", modifiers: .command), KeyChord("/"), KeyChord("?"), KeyChord("b")] {
                let hand: HandLayout = bad == KeyChord("b") ? .right : .left
                try require(store.setBinding(bad, for: .zoomIn, hand: hand) != nil, "A duplicate / alias key was assigned")
            }
            for key in ["q", "h", "w", "m", " ", "c", "x", "v", "a", "z"] {
                try require(store.validate(KeyChord(key, modifiers: .command), for: .mute, hand: .left) != nil, "A standard system / text command was stolen")
            }
            for chord in [KeyChord("3", modifiers: [.command, .shift]), KeyChord("d", modifiers: [.command, .option]), KeyChord("`", modifiers: .command)] {
                try require(store.validate(chord, for: .mute, hand: .left) != nil, "A global macOS shortcut was stolen")
            }
            try require(store.validate(KeyChord("z", modifiers: [.command, .shift]), for: .mute, hand: .left) != nil, "Redo was stolen")
            try require(store.validate(KeyChord("o", modifiers: [.command, .shift]), for: .mute, hand: .left) != nil, "Folder-access menu shortcut was stolen")
            for key in ["", "shift", "😀", "中", "\u{1b}", "\t", "\r", "\u{f700}", "\u{f729}", "\u{f72b}"] {
                try require(store.validate(KeyChord(key), for: .mute, hand: .left) != nil, "An unusable / navigation key was assigned")
            }
            try require(store.validate(KeyChord("2", modifiers: ShortcutModifiers(rawValue: 32)), for: .mute, hand: .left) != nil, "Unknown modifier bits were accepted")
            try require(defaults.data(forKey: ShortcutStore.storageKey) == saved && notifications == notice, "Failed assignments mutated preferences or notified observers")
            try require(store.setBinding(KeyChord("l", modifiers: .command), for: .playlist, hand: .left) == nil, "An action could not use its own standard alias")
            try require(store.setBinding(nil, for: .playlist, hand: .left) == nil, "Clearing the editable key failed")
            try require(store.binding(for: .playlist, hand: .left) == nil, "Cleared primary remained assigned")
            try require(store.command(for: KeyChord("t"), hand: .left, context: .playback) == nil, "Cleared primary still executed")
            try require(store.command(for: KeyChord("l", modifiers: .command), hand: .left, context: .playback) == .playlist, "Clearing a primary disabled its standard alias")
            try require(store.setBinding(KeyChord("3"), for: .mute, hand: .right) == nil, "Other-hand customization failed")
            try require(store.binding(for: .mute, hand: .left) == KeyChord("2", modifiers: .option), "Other-hand edit changed the active hand")
            store.resetAll(hand: .left)
            try require(!store.hasCustomizations(hand: .left) && store.hasCustomizations(hand: .right), "Reset-all affected the wrong hand")
            try require(store.binding(for: .playlist, hand: .left) == KeyChord("t"), "Reset-all did not restore the primary")
            try require(store.setBinding(KeyChord("2"), for: .seekBackward, hand: .left) == nil, "Freed-key fixture failed")
            try require(store.setBinding(KeyChord("a"), for: .mute, hand: .left) == nil, "Freed key could not be borrowed")
            store.reset(.seekBackward, hand: .left)
            try require(store.binding(for: .seekBackward, hand: .left) == KeyChord("a") && store.binding(for: .mute, hand: .left) == nil, "Per-action reset left a duplicate key")
            try require(!store.hasCustomizations(hand: .left), "Reset did not remove redundant overrides")
        }
    }

    private static func shortcutPersistence() throws {
        try shortcutFixture { defaults in
            let store = ShortcutStore(defaults: defaults)
            try require(defaults.data(forKey: ShortcutStore.storageKey) == nil, "Initialization wrote preferences")
            try require(store.setBinding(KeyChord("F7", modifiers: .option), for: .mute, hand: .left) == nil, "Function-key customization failed")
            try require(store.setBinding(nil, for: .playPause, hand: .right) == nil, "Cleared-key fixture failed")
            let data = defaults.data(forKey: ShortcutStore.storageKey)!
            let restored = ShortcutStore(defaults: defaults)
            try require(restored.binding(for: .mute, hand: .left) == KeyChord("F7", modifiers: .option), "Custom key did not persist")
            try require(restored.binding(for: .playPause, hand: .right) == nil, "Disabled primary did not persist")
            try require(defaults.data(forKey: ShortcutStore.storageKey) == data, "Loading valid preferences rewrote them")
            var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            var hands = object["hands"] as! [String: Any]
            var left = hands["left"] as! [String: Any]
            left["mute"] = ["chord": ["key": "c", "modifiers": 0]]
            hands["left"] = left; object["hands"] = hands
            let duplicate = try JSONSerialization.data(withJSONObject: object)
            defaults.set(duplicate, forKey: ShortcutStore.storageKey)
            let recovered = ShortcutStore(defaults: defaults)
            try require(recovered.binding(for: .mute, hand: .left) == nil && !recovered.hasCustomizations(hand: .left), "Conflicting persisted key did not fall back safely")
            try require(recovered.binding(for: .playPause, hand: .right) == nil, "One damaged hand discarded the valid other hand")
            try require(defaults.data(forKey: ShortcutStore.storageKey) == duplicate, "Recovering damaged preferences overwrote them during init")
            for bad in [Data("broken json".utf8), Data("{\"version\":99,\"hands\":{}}".utf8)] {
                defaults.set(bad, forKey: ShortcutStore.storageKey)
                let damaged = ShortcutStore(defaults: defaults)
                try require(!damaged.hasCustomizations(hand: .left) && damaged.binding(for: .playPause, hand: .right) == KeyChord(" "), "Damaged or future-version config did not fall back")
                try require(defaults.data(forKey: ShortcutStore.storageKey) == bad, "Damaged config recovery wrote user preferences")
            }
        }
    }

    private static func shortcutPresetMigration() throws {
        for hand in [HandLayout.left, .right] {
            let previous = hand == .left ? "w" : "i", next = hand == .left ? "s" : "k"
            let oldPrevious = hand == .left ? "x" : "n", oldNext = hand == .left ? "b" : "."
            let otherHand: HandLayout = hand == .left ? .right : .left
            let fixtures: [[ShortcutAction: KeyChord?]] = [
                [.mute: KeyChord("2", modifiers: .option)],
                [.volumeUp: KeyChord("2"), .mute: KeyChord(previous), .nextFile: nil],
                [.previousFile: KeyChord(previous), .volumeUp: nil, .volumeDown: nil, .mute: KeyChord(previous, modifiers: .shift)]
            ]
            for custom in fixtures {
                try shortcutFixture { defaults in
                    var records: [String: Any] = [:]
                    for (action, chord) in custom {
                        records[action.rawValue] = chord.map { ["chord": ["key": $0.key, "modifiers": $0.modifiers.rawValue]] } ?? [:]
                    }
                    let legacy = try JSONSerialization.data(withJSONObject: ["version": 1, "hands": [hand.rawValue: records, otherHand.rawValue: [:]]])
                    defaults.set(legacy, forKey: ShortcutStore.storageKey)
                    let migrated = ShortcutStore(defaults: defaults)
                    let saved = defaults.data(forKey: ShortcutStore.storageKey)!
                    let object = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
                    try require(object["version"] as? Int == 3, "Legacy custom shortcuts were not persisted as schema 3")
                    for store in [migrated, ShortcutStore(defaults: defaults)] {
                        for action in ShortcutAction.allCases {
                            let expected: KeyChord?
                            if let explicit = custom[action] { expected = explicit }
                            else {
                                switch action {
                                case .previousFile: expected = KeyChord(oldPrevious)
                                case .nextFile: expected = KeyChord(oldNext)
                                case .volumeUp: expected = KeyChord(previous)
                                case .volumeDown: expected = KeyChord(next)
                                default: expected = ShortcutStore.defaultBinding(for: action, hand: hand)
                                }
                            }
                            try require(store.binding(for: action, hand: hand) == expected, "Migration changed an effective custom-layout binding: \(hand.rawValue) \(action)")
                            try require(store.binding(for: action, hand: otherHand) == ShortcutStore.defaultBinding(for: action, hand: otherHand), "Migration changed the untouched hand")
                        }
                        if custom[.volumeUp] == nil {
                            try require(store.command(for: KeyChord(previous), hand: hand, context: .playback) == .volume(5), "The inherited legacy volume key became a video key")
                        } else if custom[.mute] == .some(KeyChord(previous)) {
                            try require(store.command(for: KeyChord(previous), hand: hand, context: .playback) == .mute, "A new default stole a borrowed custom key")
                        }
                    }
                    try require(defaults.data(forKey: ShortcutStore.storageKey) == saved, "Reloading schema 3 rewrote or migrated the layout twice")
                    migrated.resetAll(hand: hand)
                    let reset = ShortcutStore(defaults: defaults)
                    try require(!reset.hasCustomizations(hand: hand), "Reset retained the migration overrides")
                    try require(reset.command(for: KeyChord(previous), hand: hand, context: .playback) == .previousFile && reset.command(for: KeyChord(next), hand: hand, context: .playback) == .nextFile, "Reset did not select the new video preset")
                    try require(reset.command(for: KeyChord(previous, modifiers: .shift), hand: hand, context: .playback) == .volume(5), "Reset did not select the new volume preset")
                }
            }
        }
        try shortcutFixture { defaults in
            let empty = try JSONSerialization.data(withJSONObject: ["version": 1, "hands": ["left": [:], "right": [:]]])
            defaults.set(empty, forKey: ShortcutStore.storageKey)
            let store = ShortcutStore(defaults: defaults)
            try require(!store.hasCustomizations(hand: .left) && !store.hasCustomizations(hand: .right), "Empty legacy layouts became custom layouts")
            try require(store.command(for: KeyChord("w"), hand: .left, context: .playback) == .previousFile && store.command(for: KeyChord("k"), hand: .right, context: .playback) == .nextFile, "Untouched legacy layouts did not adopt the new defaults")
        }
    }

    private static func zoomShortcuts() throws {
        for hand in [HandLayout.left, .right] {
            try shortcutFixture { defaults in
                let store = ShortcutStore(defaults: defaults)
                for context in [ShortcutContext.playback, .panel, .playlist] {
                    for (key, command) in [(KeyChord("="), PlayerCommand.zoom(0.25)), (KeyChord("+"), .zoom(0.25)), (KeyChord("-"), .zoom(-0.25)), (KeyChord("0"), .resetZoom), (KeyChord("0", modifiers: .command), .resetZoom)] {
                        try require(store.command(for: key, hand: hand, context: context) == command, "Zoom shortcut changed or was trapped by an open panel")
                    }
                    for key in [KeyChord("=", modifiers: .command), KeyChord("-", modifiers: .option), KeyChord("-", modifiers: .shift), KeyChord("+", modifiers: .control)] {
                        try require(store.command(for: key, hand: hand, context: context) == nil, "Zoom shortcuts ignored exact modifiers")
                    }
                }
                try require(hand.command(for: "=") == .zoom(0.25) && hand.command(for: "+") == .zoom(0.25) && hand.command(for: "-") == .zoom(-0.25), "Stateless keyboard layout differed from the shortcut store")
                try require(store.setBinding(KeyChord("2"), for: .zoomIn, hand: hand) == nil, "Zoom-in could not be remapped")
                try require(store.command(for: KeyChord("2"), hand: hand, context: .playback) == .zoom(0.25), "Remapped zoom-in did not execute")
                for key in [KeyChord("="), KeyChord("+")] {
                    try require(store.command(for: key, hand: hand, context: .playback) == nil, "Remapping zoom-in retained its old default or convenience alias")
                }
                try require(store.setBinding(nil, for: .zoomIn, hand: hand) == nil && store.setBinding(nil, for: .zoomOut, hand: hand) == nil, "Zoom actions could not be disabled")
                let disabled = ShortcutStore(defaults: defaults)
                for key in [KeyChord("="), KeyChord("+"), KeyChord("-")] {
                    try require(disabled.command(for: key, hand: hand, context: .playback) == nil, "A disabled zoom action returned after reload")
                }
                try require(store.setBinding(KeyChord("+"), for: .mute, hand: hand) == nil, "Disabled zoom did not release '+'")
                store.reset(.zoomIn, hand: hand)
                try require(store.command(for: KeyChord("="), hand: hand, context: .playback) == .zoom(0.25), "Reset did not restore '=' zoom-in")
                try require(store.command(for: KeyChord("+"), hand: hand, context: .playback) == .mute, "Reset zoom-in stole a customized '+'")
                store.reset(.mute, hand: hand)
                try require(store.command(for: KeyChord("+"), hand: hand, context: .playback) == .zoom(0.25), "Freeing '+' did not restore the convenience alias")
            }
            let fixtures: [(custom: [ShortcutAction: KeyChord?], zoomIn: KeyChord?, zoomOut: KeyChord?)] = [
                ([.mute: KeyChord("=")], nil, KeyChord("-")),
                ([.mute: KeyChord("-")], KeyChord("="), nil),
                ([.mute: KeyChord("+")], KeyChord("="), KeyChord("-")),
                ([.mute: KeyChord("="), .subtitles: KeyChord("-")], nil, nil),
                ([.zoomIn: nil, .zoomOut: nil, .mute: KeyChord("2")], nil, nil),
                ([.zoomIn: KeyChord("2"), .zoomOut: KeyChord("3")], KeyChord("2"), KeyChord("3")),
                ([.zoomIn: KeyChord("-")], KeyChord("-"), nil),
                ([.zoomOut: KeyChord("=")], nil, KeyChord("="))
            ]
            for version in [1, 2] {
                for fixture in fixtures {
                    try shortcutFixture { defaults in
                        let otherHand: HandLayout = hand == .left ? .right : .left
                        var records: [String: Any] = [:]
                        for (action, chord) in fixture.custom {
                            records[action.rawValue] = chord.map { ["chord": ["key": $0.key, "modifiers": $0.modifiers.rawValue]] } ?? [:]
                        }
                        let legacy = try JSONSerialization.data(withJSONObject: ["version": version, "hands": [hand.rawValue: records]])
                        defaults.set(legacy, forKey: ShortcutStore.storageKey)
                        let migrated = ShortcutStore(defaults: defaults)
                        let saved = defaults.data(forKey: ShortcutStore.storageKey)!
                        let object = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
                        try require(object["version"] as? Int == 3, "Zoom migration did not persist schema 3")
                        for store in [migrated, ShortcutStore(defaults: defaults)] {
                            try require(store.binding(for: .zoomIn, hand: hand) == fixture.zoomIn && store.binding(for: .zoomOut, hand: hand) == fixture.zoomOut, "Zoom migration changed a remap, re-enabled a disabled action, or stole a borrowed key")
                            for (action, chord) in fixture.custom {
                                try require(store.binding(for: action, hand: hand) == chord, "Zoom migration discarded another custom binding")
                                if let chord {
                                    let expected: PlayerCommand
                                    switch action {
                                    case .zoomIn: expected = .zoom(0.25)
                                    case .zoomOut: expected = .zoom(-0.25)
                                    case .mute: expected = .mute
                                    case .subtitles: expected = .subtitles
                                    default: throw Failure(description: "Unexpected zoom migration fixture action")
                                    }
                                    try require(store.command(for: chord, hand: hand, context: .playback) == expected, "A migrated custom key resolved to a different action")
                                }
                            }
                            for action in ShortcutAction.allCases {
                                try require(store.binding(for: action, hand: otherHand) == ShortcutStore.defaultBinding(for: action, hand: otherHand), "Zoom migration customized the untouched hand")
                            }
                            if version == 1 {
                                try require(store.command(for: KeyChord(hand == .left ? "w" : "i"), hand: hand, context: .playback) == .volume(5), "Zoom migration lost the v1 navigation migration")
                            }
                        }
                        try require(defaults.data(forKey: ShortcutStore.storageKey) == saved, "Reloading migrated zoom bindings rewrote preferences")
                        migrated.resetAll(hand: hand)
                        try require(migrated.command(for: KeyChord("="), hand: hand, context: .playback) == .zoom(0.25) && migrated.command(for: KeyChord("+"), hand: hand, context: .playback) == .zoom(0.25) && migrated.command(for: KeyChord("-"), hand: hand, context: .playback) == .zoom(-0.25), "Reset-all did not adopt the complete zoom preset")
                    }
                }
            }
        }
    }

    private static func timeFormatting() throws {
        for (seconds, expected) in [(0.0, "00:00"), (9.9, "00:09"), (65, "01:05"), (3_661, "1:01:01"), (-12, "00:00")] {
            try require(clockText(seconds) == expected, "Incorrect clock text for \(seconds)")
        }
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            try require(clockText(invalid) == "00:00", "Non-finite clock input was not handled")
        }
    }

    private static func seekScheduling() throws {
        func pump(_ duration: TimeInterval) {
            let end = Date(timeIntervalSinceNow: duration)
            while Date() < end {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.003))
            }
        }
        var values = [Double]()
        let scheduler = SeekScheduler(interval: 0.04) { values.append($0) }
        scheduler.request(5)
        try require(values == [5], "The first key/button press was delayed")
        scheduler.request(10); scheduler.request(15)
        pump(0.09)
        try require(values == [5, 15], "A short burst did not retain the newest absolute target")
        scheduler.request(20); scheduler.request(25); scheduler.cancel()
        let beforeCancel = values
        pump(0.07)
        try require(values == beforeCancel, "Cancelled trailing work reached a replacement file")
        scheduler.request(30)
        try require(values.last == 30, "First input after a cancellation was not immediate")
        scheduler.request(.nan); scheduler.request(.infinity)
        try require(values.last == 30, "A malformed target changed playback input")

        var sustained = [Double]()
        let heldKey = SeekScheduler(interval: 0.05) { sustained.append($0) }
        var target = 0.0
        let end = Date(timeIntervalSinceNow: 0.22)
        while Date() < end {
            target += 5
            heldKey.request(target)
            pump(0.01)
        }
        try require(sustained.count >= 3, "Holding a key postponed all updates until release")
        pump(0.09)
        try require(sustained.last == target && !heldKey.hasPending, "Releasing a key lost the accumulated final target")
    }
}
