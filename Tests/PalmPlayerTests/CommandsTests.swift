import XCTest
@testable import PalmPlayer

final class CommandsTests: XCTestCase {
    func testVerticalArrowsSwitchVideosInPlaybackAndNavigatePanels() {
        for layout in [HandLayout.left, .right] {
            XCTAssertEqual(layout.command(for: "\u{f700}"), .previousFile)
            XCTAssertEqual(layout.command(for: "\u{f701}"), .nextFile)
            XCTAssertEqual(layout.command(for: "\u{f700}", shift: true), .volume(5))
            XCTAssertEqual(layout.command(for: "\u{f701}", shift: true), .volume(-5))
            XCTAssertEqual(layout.command(for: "\u{f700}", panelOpen: true), .panelMove(-1))
            XCTAssertEqual(layout.command(for: "\u{f701}", panelOpen: true), .panelMove(1))
            XCTAssertEqual(layout.command(for: "\u{f700}", playlistOpen: true), .playlistMove(-1))
            XCTAssertEqual(layout.command(for: "\u{f701}", playlistOpen: true), .playlistMove(1))
            let volumeKeys = layout == .left ? ["w", "s"] : ["i", "k"]
            XCTAssertEqual(layout.command(for: volumeKeys[0]), .previousFile)
            XCTAssertEqual(layout.command(for: volumeKeys[1]), .nextFile)
            XCTAssertEqual(layout.command(for: volumeKeys[0], shift: true), .volume(5))
            XCTAssertEqual(layout.command(for: volumeKeys[1], shift: true), .volume(-5))
        }
    }

    func testLeftHandReminderAndVideoKeys() {
        XCTAssertEqual(HandLayout.left.helpKey, "V")
        XCTAssertEqual(HandLayout.left.previousKey, "W")
        XCTAssertEqual(HandLayout.left.nextKey, "S")
        XCTAssertEqual(HandLayout.left.command(for: "v"), .help)
        XCTAssertEqual(HandLayout.left.command(for: "W"), .previousFile)
        XCTAssertEqual(HandLayout.left.command(for: "s"), .nextFile)
        XCTAssertNil(HandLayout.left.command(for: "x"))
        XCTAssertNil(HandLayout.left.command(for: "b"))
    }

    func testRightHandReminderAndVideoKeys() {
        XCTAssertEqual(HandLayout.right.helpKey, "Y")
        XCTAssertEqual(HandLayout.right.previousKey, "I")
        XCTAssertEqual(HandLayout.right.nextKey, "K")
        XCTAssertEqual(HandLayout.right.command(for: "y"), .help)
        XCTAssertEqual(HandLayout.right.command(for: "I"), .previousFile)
        XCTAssertEqual(HandLayout.right.command(for: "k"), .nextFile)
        XCTAssertNil(HandLayout.right.command(for: "n"))
        XCTAssertNil(HandLayout.right.command(for: "."))
    }

    func testReminderRemainsAvailableAndVideoKeysNavigateOpenPanel() {
        for layout in [HandLayout.left, .right] {
            XCTAssertEqual(layout.command(for: layout.helpKey, panelOpen: true), .help)
            XCTAssertEqual(layout.command(for: layout.previousKey, panelOpen: true), .panelMove(-1))
            XCTAssertEqual(layout.command(for: layout.nextKey, panelOpen: true), .panelMove(1))
            XCTAssertEqual(layout.command(for: "?", panelOpen: true), .help)
            XCTAssertEqual(layout.command(for: "/", panelOpen: true), .help)
        }
    }

    func testPanelNavigationTakesPriorityOverPlaybackActions() {
        let layouts: [(HandLayout, [String])] = [(.left, ["w", "s", "a", "d"]), (.right, ["i", "k", "j", "l"])]
        let commands: [PlayerCommand] = [.panelMove(-1), .panelMove(1), .panelAdjust(-1), .panelAdjust(1)]
        for (layout, keys) in layouts {
            for (key, command) in zip(keys, commands) {
                XCTAssertEqual(layout.command(for: key, panelOpen: true), command)
            }
            XCTAssertEqual(layout.command(for: " ", panelOpen: true), .panelActivate)
            XCTAssertEqual(layout.command(for: "\r", panelOpen: true), .panelActivate)
            XCTAssertEqual(layout.command(for: "\u{f702}", panelOpen: true), .panelAdjust(-1))
            XCTAssertEqual(layout.command(for: "\u{f703}", panelOpen: true), .panelAdjust(1))
        }
    }

    func testPlaybackNavigationAndSharedAliasesRemainAvailable() {
        XCTAssertEqual(HandLayout.left.command(for: "a"), .seek(-5))
        XCTAssertEqual(HandLayout.left.command(for: "D", shift: true), .seek(30))
        XCTAssertEqual(HandLayout.right.command(for: "j", shift: true), .seek(-30))
        XCTAssertEqual(HandLayout.right.command(for: "l"), .seek(5))
        for layout in [HandLayout.left, .right] {
            XCTAssertEqual(layout.command(for: " "), .togglePause)
            XCTAssertEqual(layout.command(for: "?"), .help)
            XCTAssertEqual(layout.command(for: "/"), .help)
            XCTAssertEqual(layout.command(for: "\u{1b}"), .escape)
            XCTAssertEqual(layout.command(for: "0"), .resetZoom)
            XCTAssertEqual(layout.command(for: "0", panelOpen: true), .resetZoom)
            XCTAssertNil(layout.command(for: "2"))
        }
    }

    func testPlaylistTogglePreservesExistingSingleHandShortcuts() {
        XCTAssertEqual(HandLayout.left.playlistKey, "T")
        XCTAssertEqual(HandLayout.right.playlistKey, "'")
        for layout in [HandLayout.left, .right] {
            XCTAssertEqual(layout.command(for: layout.playlistKey), .playlist)
            XCTAssertEqual(layout.command(for: layout.playlistKey, panelOpen: true), .playlist)
            XCTAssertEqual(layout.command(for: layout.playlistKey, playlistOpen: true), .playlist)
            XCTAssertEqual(layout.command(for: layout.previousKey, playlistOpen: true), .playlistMove(-1))
            XCTAssertEqual(layout.command(for: layout.nextKey, playlistOpen: true), .playlistMove(1))
            XCTAssertEqual(layout.command(for: layout.helpKey, playlistOpen: true), .help)
            XCTAssertEqual(layout.command(for: layout.panelKey, playlistOpen: true), .panel)
            XCTAssertEqual(layout.command(for: "\u{1b}", playlistOpen: true), .escape)
            XCTAssertEqual(layout.command(for: "0", playlistOpen: true), .resetZoom)
        }
        XCTAssertEqual(HandLayout.left.command(for: "s", playlistOpen: true), .playlistMove(1))
        XCTAssertEqual(HandLayout.right.command(for: "p", playlistOpen: true), .resetSpeed)
    }

    func testPlaylistSelectionTakesFocusOverPlaybackAndQuickPanel() {
        let layouts: [(HandLayout, [String])] = [(.left, ["w", "s"]), (.right, ["i", "k"])]
        for (layout, keys) in layouts {
            for (key, command) in [(keys[0], PlayerCommand.playlistMove(-1)), (keys[1], .playlistMove(1)), ("\u{f700}", .playlistMove(-1)), ("\u{f701}", .playlistMove(1))] {
                XCTAssertEqual(layout.command(for: key, playlistOpen: true), command)
                XCTAssertEqual(layout.command(for: key.uppercased(), shift: true, panelOpen: true, playlistOpen: true), command)
            }
            for key in ["\u{f702}", "\u{f703}"] {
                XCTAssertEqual(layout.command(for: key, playlistOpen: true), .playlistMove(0))
                XCTAssertEqual(layout.command(for: key, shift: true, panelOpen: true, playlistOpen: true), .playlistMove(0))
            }
            for key in [" ", "\r", "\u{3}"] {
                XCTAssertEqual(layout.command(for: key, playlistOpen: true), .playlistActivate)
                XCTAssertEqual(layout.command(for: key, panelOpen: true, playlistOpen: true), .playlistActivate)
            }
            XCTAssertEqual(layout.command(for: "\u{f729}", playlistOpen: true), .playlistBoundary(false))
            XCTAssertEqual(layout.command(for: "\u{f72b}", playlistOpen: true), .playlistBoundary(true))
            XCTAssertEqual(layout.command(for: keys[0]), .previousFile)
            XCTAssertEqual(layout.command(for: keys[1]), .nextFile)
            XCTAssertEqual(layout.command(for: keys[0], shift: true), .volume(5))
            XCTAssertEqual(layout.command(for: keys[1], shift: true), .volume(-5))
            XCTAssertEqual(layout.command(for: " "), .togglePause)
        }
    }
    func testShiftDoesNotAccidentallyTriggerPlainCommands() {
        for (layout, previous, next) in [(HandLayout.left, "w", "s"), (.right, "i", "k")] {
            for (panel, playlist) in [(false, false), (true, false), (false, true)] {
                for (key, arrow) in [(previous, "\u{f700}"), (next, "\u{f701}"), (layout == .left ? "a" : "j", "\u{f702}"), (layout == .left ? "d" : "l", "\u{f703}")] {
                    for shift in [false, true] {
                        XCTAssertEqual(layout.command(for: key, shift: shift, panelOpen: panel, playlistOpen: playlist), layout.command(for: arrow, shift: shift, panelOpen: panel, playlistOpen: playlist))
                    }
                }
                let slower = layout == .left ? "q" : "u", faster = layout == .left ? "e" : "o"
                XCTAssertEqual(layout.command(for: slower, panelOpen: panel, playlistOpen: playlist), .speed(-0.1))
                XCTAssertEqual(layout.command(for: faster, panelOpen: panel, playlistOpen: playlist), .speed(0.1))
                XCTAssertNil(layout.command(for: slower, shift: true, panelOpen: panel, playlistOpen: playlist))
                XCTAssertNil(layout.command(for: faster, shift: true, panelOpen: panel, playlistOpen: playlist))
            }
        }
        XCTAssertNil(HandLayout.right.command(for: "n", shift: true))
        XCTAssertEqual(HandLayout.right.command(for: "'"), .playlist)
        XCTAssertEqual(HandLayout.right.command(for: "b"), .playlist)
    }

    func testCustomKeysPersistAndFixedAliasesCannotBeStolen() {
        let name = "LPlayer-CommandsTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: preferences)
        XCTAssertNil(store.setBinding(KeyChord("2", modifiers: .option), for: .mute, hand: .left))
        XCTAssertEqual(store.command(for: KeyChord("2", modifiers: .option), hand: .left, context: .playback), .mute)
        XCTAssertNil(store.command(for: KeyChord("2"), hand: .left, context: .playback))
        XCTAssertNotNil(store.setBinding(KeyChord("l", modifiers: .command), for: .mute, hand: .left))
        XCTAssertEqual(ShortcutStore(defaults: preferences).binding(for: .mute, hand: .left), KeyChord("2", modifiers: .option))
        XCTAssertNil(store.setBinding(nil, for: .playlist, hand: .left))
        XCTAssertNil(store.command(for: KeyChord("t"), hand: .left, context: .playback))
        XCTAssertEqual(store.command(for: KeyChord("l", modifiers: .command), hand: .left, context: .playback), .playlist)
        store.resetAll(hand: .left)
        XCTAssertFalse(store.hasCustomizations(hand: .left))
        XCTAssertEqual(store.binding(for: .playlist, hand: .left), KeyChord("t"))
    }
    func testPanelTogglesCannotUseTheirOwnNavigationKeys() {
        let name = "LPlayer-ToggleTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: preferences)
        XCTAssertNil(store.setBinding(nil, for: .volumeUp, hand: .left))
        XCTAssertNotNil(store.setBinding(KeyChord("w"), for: .playlist, hand: .left))
        XCTAssertNotNil(store.setBinding(KeyChord("w", modifiers: .shift), for: .playlist, hand: .left))
        XCTAssertNil(store.setBinding(nil, for: .playPause, hand: .left))
        XCTAssertNotNil(store.setBinding(KeyChord(" "), for: .panel, hand: .left))
        XCTAssertNil(store.setBinding(KeyChord("w", modifiers: .option), for: .playlist, hand: .left))
        XCTAssertEqual(store.command(for: KeyChord("w", modifiers: .option), hand: .left, context: .playlist), .playlist)
        XCTAssertNil(store.setBinding(KeyChord("i", modifiers: .command), for: .panel, hand: .right))
        XCTAssertEqual(store.command(for: KeyChord("i", modifiers: .command), hand: .right, context: .panel), .panel)
    }

    func testLegacyCustomLayoutKeepsInheritedVolumeAndVideoKeysAfterReload() throws {
        for hand in [HandLayout.left, .right] {
            let name = "LPlayer-LegacyShortcutTests-\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: name)!
            defer { preferences.removePersistentDomain(forName: name) }
            let custom: [String: Any] = ["mute": ["chord": ["key": "2", "modifiers": ShortcutModifiers.option.rawValue]]]
            preferences.set(try JSONSerialization.data(withJSONObject: ["version": 1, "hands": [hand.rawValue: custom]]), forKey: ShortcutStore.storageKey)
            let previous = hand == .left ? "w" : "i", next = hand == .left ? "s" : "k"
            let oldPrevious = hand == .left ? "x" : "n", oldNext = hand == .left ? "b" : "."
            for store in [ShortcutStore(defaults: preferences), ShortcutStore(defaults: preferences)] {
                XCTAssertEqual(store.binding(for: .mute, hand: hand), KeyChord("2", modifiers: .option))
                XCTAssertEqual(store.command(for: KeyChord(previous), hand: hand, context: .playback), .volume(5))
                XCTAssertEqual(store.command(for: KeyChord(next), hand: hand, context: .playback), .volume(-5))
                XCTAssertEqual(store.command(for: KeyChord(oldPrevious), hand: hand, context: .playback), .previousFile)
                XCTAssertEqual(store.command(for: KeyChord(oldNext), hand: hand, context: .playback), .nextFile)
                let other: HandLayout = hand == .left ? .right : .left
                XCTAssertEqual(store.binding(for: .previousFile, hand: other), KeyChord(other == .left ? "w" : "i"))
                XCTAssertFalse(store.hasCustomizations(hand: other))
            }
            let migrated = try XCTUnwrap(preferences.data(forKey: ShortcutStore.storageKey))
            XCTAssertEqual((try JSONSerialization.jsonObject(with: migrated) as? [String: Any])?["version"] as? Int, 2)
            let store = ShortcutStore(defaults: preferences)
            store.resetAll(hand: hand)
            let reset = ShortcutStore(defaults: preferences)
            XCTAssertEqual(reset.command(for: KeyChord(previous), hand: hand, context: .playback), .previousFile)
            XCTAssertEqual(reset.command(for: KeyChord(previous, modifiers: .shift), hand: hand, context: .playback), .volume(5))
            XCTAssertFalse(reset.hasCustomizations(hand: hand))
        }
    }

    func testLegacyBorrowedNewDefaultAndDisabledBindingSurviveMigration() throws {
        let name = "LPlayer-BorrowedShortcutTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let custom: [String: Any] = [
            "volumeUp": ["chord": ["key": "2", "modifiers": 0]],
            "mute": ["chord": ["key": "w", "modifiers": 0]],
            "nextFile": [:]
        ]
        preferences.set(try JSONSerialization.data(withJSONObject: ["version": 1, "hands": ["left": custom]]), forKey: ShortcutStore.storageKey)
        for store in [ShortcutStore(defaults: preferences), ShortcutStore(defaults: preferences)] {
            XCTAssertEqual(store.command(for: KeyChord("w"), hand: .left, context: .playback), .mute)
            XCTAssertEqual(store.command(for: KeyChord("2"), hand: .left, context: .playback), .volume(5))
            XCTAssertEqual(store.command(for: KeyChord("x"), hand: .left, context: .playback), .previousFile)
            XCTAssertNil(store.binding(for: .nextFile, hand: .left))
            XCTAssertNil(store.command(for: KeyChord("b"), hand: .left, context: .playback))
            XCTAssertEqual(store.command(for: KeyChord("Down"), hand: .left, context: .playback), .nextFile)
        }
    }
}
