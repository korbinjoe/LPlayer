import Foundation

enum ShortcutAction: String, CaseIterable, Codable {
    case playPause, seekBackward, seekForward, seekBackwardLarge, seekForwardLarge
    case volumeUp, volumeDown, mute, speedDown, speedUp, resetSpeed
    case zoomIn, zoomOut, resetZoom, fullscreen, subtitles, subtitleEarlier, subtitleLater
    case cycleAudioTrack, cycleSubtitleTrack, undoSeek, previousFile, nextFile
    case panel, playlist, help, openFiles, privatePlayback, customizeShortcuts

    var title: String {
        switch self {
        case .playPause: return L10n.text("Play / Pause", "播放 / 暂停")
        case .seekBackward: return L10n.text("Back 5 seconds", "后退 5 秒")
        case .seekForward: return L10n.text("Forward 5 seconds", "前进 5 秒")
        case .seekBackwardLarge: return L10n.text("Back 30 seconds", "后退 30 秒")
        case .seekForwardLarge: return L10n.text("Forward 30 seconds", "前进 30 秒")
        case .volumeUp: return L10n.text("Volume up", "增大音量")
        case .volumeDown: return L10n.text("Volume down", "减小音量")
        case .mute: return L10n.text("Mute", "静音")
        case .speedDown: return L10n.text("Slower", "降低速度")
        case .speedUp: return L10n.text("Faster", "提高速度")
        case .resetSpeed: return L10n.text("Normal speed", "正常速度")
        case .zoomIn: return L10n.text("Zoom in", "放大画面")
        case .zoomOut: return L10n.text("Zoom out", "缩小画面")
        case .resetZoom: return L10n.text("Fit video", "适应窗口")
        case .fullscreen: return L10n.text("Full screen", "全屏")
        case .subtitles: return L10n.text("Show / Hide subtitles", "显示 / 隐藏字幕")
        case .subtitleEarlier: return L10n.text("Subtitles 0.1s earlier", "字幕提前 0.1 秒")
        case .subtitleLater: return L10n.text("Subtitles 0.1s later", "字幕延后 0.1 秒")
        case .cycleAudioTrack: return L10n.text("Next audio track", "下一音轨")
        case .cycleSubtitleTrack: return L10n.text("Next subtitle track", "下一字幕轨")
        case .undoSeek: return L10n.text("Undo seek", "撤销跳转")
        case .previousFile: return L10n.text("Previous video", "上一个视频")
        case .nextFile: return L10n.text("Next video", "下一个视频")
        case .panel: return L10n.text("Quick Controls", "快捷控制")
        case .playlist: return L10n.text("Playlist", "播放列表")
        case .help: return L10n.text("Keyboard Shortcuts", "快捷键提醒")
        case .openFiles: return L10n.text("Open video / folder", "打开视频 / 文件夹")
        case .privatePlayback: return L10n.text("Private playback", "隐私播放")
        case .customizeShortcuts: return L10n.text("Customize Shortcuts", "自定义快捷键")
        }
    }

    fileprivate var command: PlayerCommand {
        switch self {
        case .playPause: return .togglePause
        case .seekBackward: return .seek(-5)
        case .seekForward: return .seek(5)
        case .seekBackwardLarge: return .seek(-30)
        case .seekForwardLarge: return .seek(30)
        case .volumeUp: return .volume(5)
        case .volumeDown: return .volume(-5)
        case .mute: return .mute
        case .speedDown: return .speed(-0.1)
        case .speedUp: return .speed(0.1)
        case .resetSpeed: return .resetSpeed
        case .zoomIn: return .zoom(0.25)
        case .zoomOut: return .zoom(-0.25)
        case .resetZoom: return .resetZoom
        case .fullscreen: return .fullscreen
        case .subtitles: return .subtitles
        case .subtitleEarlier: return .subtitleDelay(-0.1)
        case .subtitleLater: return .subtitleDelay(0.1)
        case .cycleAudioTrack: return .cycleTrack("audio")
        case .cycleSubtitleTrack: return .cycleTrack("sub")
        case .undoSeek: return .undoSeek
        case .previousFile: return .previousFile
        case .nextFile: return .nextFile
        case .panel: return .panel
        case .playlist: return .playlist
        case .help: return .help
        case .openFiles: return .openFiles
        case .privatePlayback: return .privatePlayback
        case .customizeShortcuts: return .customizeShortcuts
        }
    }
}

struct ShortcutModifiers: OptionSet, Hashable, Codable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    static let shift = Self(rawValue: 1 << 0)
    static let command = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let control = Self(rawValue: 1 << 3)
    fileprivate static let supported: Self = [.shift, .command, .option, .control]

    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(Int.self) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}

struct KeyChord: Hashable, Codable {
    let key: String
    let modifiers: ShortcutModifiers

    private static let canonicalNames = ["space": " ", "spacebar": " ", "return": "\r", "enter": "\r", "escape": "\u{1b}", "esc": "\u{1b}", "tab": "\t", "backspace": "\u{7f}", "delete": "\u{7f}", "forwarddelete": "\u{f728}", "up": "\u{f700}", "arrowup": "\u{f700}", "↑": "\u{f700}", "down": "\u{f701}", "arrowdown": "\u{f701}", "↓": "\u{f701}", "left": "\u{f702}", "arrowleft": "\u{f702}", "←": "\u{f702}", "right": "\u{f703}", "arrowright": "\u{f703}", "→": "\u{f703}", "home": "\u{f729}", "end": "\u{f72b}", "pageup": "\u{f72c}", "pagedown": "\u{f72d}"]
    private static let shiftedKeys = ["!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`"]
    private static let displayNames = [" ": "Space", "\r": "↩", "\u{1b}": "Esc", "\t": "⇥", "\u{7f}": "⌫", "\u{f728}": "⌦", "\u{f700}": "↑", "\u{f701}": "↓", "\u{f702}": "←", "\u{f703}": "→", "\u{f729}": "Home", "\u{f72b}": "End", "\u{f72c}": "Page Up", "\u{f72d}": "Page Down"]

    /// Canonical keys are lowercase US keyboard characters or NSEvent's Unicode
    /// function characters. Uppercase letters do NOT imply Shift: the caller's
    /// modifier flags are authoritative. Shifted punctuation (including '?') is
    /// normalized to its base key plus Shift; keypad Enter and Return are equal.
    init(_ key: String, modifiers: ShortcutModifiers = []) {
        var normalized = key.lowercased()
        var flags = modifiers
        if let named = Self.canonicalNames[normalized] { normalized = named }
        if normalized == "\n" || normalized == "\u{3}" { normalized = "\r" }
        if normalized.hasPrefix("f"), let number = Int(normalized.dropFirst()), (1...20).contains(number), let scalar = UnicodeScalar(0xf703 + number) { normalized = String(scalar) }
        if let base = Self.shiftedKeys[normalized] { normalized = base; flags.insert(.shift) }
        self.key = normalized
        self.modifiers = flags
    }

    var display: String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        if let name = Self.displayNames[key] { return prefix + name }
        if let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1, (0xf704...0xf717).contains(Int(scalar.value)) { return prefix + "F\(scalar.value - 0xf703)" }
        return prefix + key.uppercased()
    }

    private enum CodingKeys: String, CodingKey { case key, modifiers }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(String.self, forKey: .key), modifiers: try container.decode(ShortcutModifiers.self, forKey: .modifiers))
    }
}

enum ShortcutContext { case playback, panel, playlist }

final class ShortcutStore {
    // Keep the original preference key so existing installations can migrate.
    static let storageKey = "LPlayer.shortcuts.v1"
    private static let configurationVersion = 2
    var onChange: (() -> Void)?
    private let defaults: UserDefaults
    private struct StoredBinding: Codable, Equatable { var chord: KeyChord? }
    private struct Configuration: Codable { var version: Int; var hands: [String: [String: StoredBinding]] }
    private var overrides: [HandLayout: [ShortcutAction: StoredBinding]] = [:]
    private var commandMaps: [HandLayout: [KeyChord: PlayerCommand]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey), let config = try? JSONDecoder().decode(Configuration.self, from: data), (1...Self.configurationVersion).contains(config.version) else { return }
        var canPersistMigration = Set(config.hands.keys).isSubset(of: Set([HandLayout.left.rawValue, HandLayout.right.rawValue]))
        for hand in [HandLayout.left, .right] {
            guard let values = config.hands[hand.rawValue] else { continue }
            var decoded: [ShortcutAction: StoredBinding] = [:]
            var malformed = false
            for (key, value) in values {
                guard let action = ShortcutAction(rawValue: key) else { malformed = true; break }
                decoded[action] = value
            }
            guard !malformed else { canPersistMigration = false; continue }
            if config.version == 1, !decoded.isEmpty {
                // Overrides store only differences from a preset. Pin the four
                // changed v1 defaults before validation, preserving the complete
                // effective layout (including disabled and borrowed keys).
                for action in [ShortcutAction.previousFile, .nextFile, .volumeUp, .volumeDown] where decoded[action] == nil {
                    decoded[action] = StoredBinding(chord: Self.legacyBinding(for: action, hand: hand))
                }
            }
            overrides[hand] = decoded
            if decoded.contains(where: { action, value in value.chord.map { validate($0, for: action, hand: hand) != nil } ?? false }) {
                overrides[hand] = nil
                canPersistMigration = false
            }
        }
        // Never overwrite damaged or unrecognized configuration while loading.
        if config.version < Self.configurationVersion, canPersistMigration { persist() }
    }

    private static func legacyBinding(for action: ShortcutAction, hand: HandLayout) -> KeyChord? {
        let left = hand == .left
        switch action {
        case .previousFile: return KeyChord(left ? "x" : "n")
        case .nextFile: return KeyChord(left ? "b" : ".")
        case .volumeUp: return KeyChord(left ? "w" : "i")
        case .volumeDown: return KeyChord(left ? "s" : "k")
        default: return nil
        }
    }

    private static let defaultBindings: [HandLayout: [ShortcutAction: KeyChord]] = {
        Dictionary(uniqueKeysWithValues: [HandLayout.left, .right].map { hand in
            (hand, Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
                makeDefaultBinding(for: action, hand: hand).map { (action, $0) }
            }))
        })
    }()

    static func defaultBinding(for action: ShortcutAction, hand: HandLayout) -> KeyChord? {
        defaultBindings[hand]?[action]
    }

    private static func makeDefaultBinding(for action: ShortcutAction, hand: HandLayout) -> KeyChord? {
        let left = hand == .left
        switch action {
        case .playPause: return KeyChord(" ")
        case .seekBackward: return KeyChord(left ? "a" : "j")
        case .seekForward: return KeyChord(left ? "d" : "l")
        case .seekBackwardLarge: return KeyChord(left ? "a" : "j", modifiers: .shift)
        case .seekForwardLarge: return KeyChord(left ? "d" : "l", modifiers: .shift)
        case .volumeUp: return KeyChord(left ? "w" : "i", modifiers: .shift)
        case .volumeDown: return KeyChord(left ? "s" : "k", modifiers: .shift)
        case .speedDown: return KeyChord(left ? "q" : "u")
        case .speedUp: return KeyChord(left ? "e" : "o")
        case .resetSpeed: return KeyChord(left ? "r" : "p")
        case .resetZoom: return KeyChord("0")
        case .fullscreen: return KeyChord(left ? "f" : "h")
        case .subtitles: return KeyChord(left ? "g" : ";")
        case .undoSeek: return KeyChord(left ? "z" : "m")
        case .previousFile: return KeyChord(left ? "w" : "i")
        case .nextFile: return KeyChord(left ? "s" : "k")
        case .panel: return KeyChord(left ? "c" : ",")
        case .playlist: return KeyChord(left ? "t" : "'")
        case .help: return KeyChord(left ? "v" : "y")
        default: return nil
        }
    }

    func binding(for action: ShortcutAction, hand: HandLayout) -> KeyChord? {
        if let custom = overrides[hand]?[action] { return custom.chord }
        return Self.defaultBinding(for: action, hand: hand)
    }

    func label(for action: ShortcutAction, hand: HandLayout) -> String {
        binding(for: action, hand: hand)?.display ?? aliases(for: action, hand: hand).first?.display ?? "—"
    }

    func aliases(for action: ShortcutAction, hand: HandLayout) -> [KeyChord] { ShortcutDefaults.aliases(for: action, hand: hand) }

    /// Errors never mutate the stored mapping. Standard app / system shortcuts
    /// and navigation remain available independently of the editable primary.
    func validate(_ binding: KeyChord, for action: ShortcutAction, hand: HandLayout) -> String? {
        guard Self.usable(binding) else { return L10n.text("Choose a single usable key with optional modifiers.", "请选择一个有效按键，可搭配修饰键。") }
        if Self.navigationKeys.contains(binding.key) { return L10n.text("This key is reserved for panel navigation.", "此按键保留用于面板导航。") }
        if action == .panel || action == .playlist,
           binding.modifiers.isEmpty || binding.modifiers == .shift {
            let contextualKeys = hand == .left ? ["w", "a", "s", "d", " "] : ["i", "j", "k", "l", " "]
            if contextualKeys.contains(binding.key) {
                return L10n.text("This key navigates the panel; choose another shortcut to open and close it.", "此按键用于面板导航；请选择其他快捷键以打开和关闭面板。")
            }
        }
        if Self.isSystemShortcut(binding) { return L10n.text("This shortcut is reserved by macOS or an app menu.", "此组合键由 macOS 或应用菜单保留。") }
        for other in ShortcutAction.allCases where other != action {
            if aliases(for: other, hand: hand).contains(binding) || self.binding(for: other, hand: hand) == binding {
                return L10n.format("Already assigned to %@.", "此按键已分配给“%@”。", other.title)
            }
        }
        return nil
    }

    @discardableResult
    func setBinding(_ binding: KeyChord?, for action: ShortcutAction, hand: HandLayout) -> String? {
        if let binding, let error = validate(binding, for: action, hand: hand) { return error }
        let before = overrides
        if binding == Self.defaultBinding(for: action, hand: hand) { overrides[hand]?[action] = nil }
        else { overrides[hand, default: [:]][action] = StoredBinding(chord: binding) }
        commit(ifChangedFrom: before)
        return nil
    }

    func reset(_ action: ShortcutAction, hand: HandLayout) {
        let before = overrides
        overrides[hand]?[action] = nil
        // Restoring an original key may reclaim one that another customized
        // action has borrowed. Restore only those conflicting custom actions.
        var changed = true
        while changed {
            changed = false
            for candidate in ShortcutAction.allCases where overrides[hand]?[candidate]?.chord != nil {
                if let key = binding(for: candidate, hand: hand), validate(key, for: candidate, hand: hand) != nil {
                    overrides[hand]?[candidate] = nil
                    changed = true
                }
            }
        }
        commit(ifChangedFrom: before)
    }

    func resetAll(hand: HandLayout) {
        let before = overrides
        overrides[hand] = nil
        commit(ifChangedFrom: before)
    }

    func hasCustomizations(hand: HandLayout) -> Bool { !(overrides[hand]?.isEmpty ?? true) }

    func command(for chord: KeyChord, hand: HandLayout, context: ShortcutContext) -> PlayerCommand? {
        if let navigation = ShortcutDefaults.navigationCommand(for: chord, hand: hand, context: context) { return navigation }
        if commandMaps[hand] == nil {
            var commands: [KeyChord: PlayerCommand] = [:]
            // Preserve registry precedence when an action shares its primary
            // key with one of its own fixed menu aliases.
            for action in ShortcutAction.allCases {
                let keys = aliases(for: action, hand: hand) + (binding(for: action, hand: hand).map { [$0] } ?? [])
                for key in keys where commands[key] == nil { commands[key] = action.command }
            }
            commandMaps[hand] = commands
        }
        return commandMaps[hand]?[chord]
    }

    private func commit(ifChangedFrom before: [HandLayout: [ShortcutAction: StoredBinding]]) {
        overrides = overrides.filter { !$0.value.isEmpty }
        let normalizedBefore = before.filter { !$0.value.isEmpty }
        guard overrides != normalizedBefore else { return }
        commandMaps.removeAll(keepingCapacity: true)
        persist()
        onChange?()
    }

    private func persist() {
        if overrides.isEmpty { defaults.removeObject(forKey: Self.storageKey) }
        else {
            var hands: [String: [String: StoredBinding]] = [:]
            for (hand, actions) in overrides { hands[hand.rawValue] = Dictionary(uniqueKeysWithValues: actions.map { ($0.key.rawValue, $0.value) }) }
            if let data = try? JSONEncoder().encode(Configuration(version: Self.configurationVersion, hands: hands)) { defaults.set(data, forKey: Self.storageKey) }
        }
    }

    private static let navigationKeys: Set<String> = ["\u{1b}", "\t", "\r", "\u{f700}", "\u{f701}", "\u{f702}", "\u{f703}", "\u{f729}", "\u{f72b}"]
    private static func usable(_ chord: KeyChord) -> Bool {
        guard chord.modifiers.subtracting(.supported).isEmpty, chord.key.unicodeScalars.count == 1, let value = chord.key.unicodeScalars.first?.value else { return false }
        return (0x20...0x7f).contains(value) || (0xf700...0xf747).contains(value) || navigationKeys.contains(chord.key)
    }
    private static func isSystemShortcut(_ chord: KeyChord) -> Bool {
        if chord.modifiers.contains(.command) {
            if ["q", "h", "w", "m", "\t", " ", "c", "x", "v", "a", "z"].contains(chord.key) { return true }
            if chord.key == "o", chord.modifiers == [.command, .shift] { return true } // Allow Folder Access menu
            if chord.key == "`" { return true } // Cycle app windows
            if chord.modifiers.contains(.shift), ["3", "4", "5", "6"].contains(chord.key) { return true } // Screenshots
            if chord.modifiers.contains(.option), ["d", "8", "=", "-"].contains(chord.key) { return true } // Dock / accessibility zoom
        }
        if chord.modifiers.contains(.control), [" ", "\u{f700}", "\u{f701}", "\u{f702}", "\u{f703}"].contains(chord.key) { return true }
        if chord.modifiers == [.command, .option], chord.key == "\u{1b}" { return true }
        return false
    }
}

/// One registry drives both default compatibility calls and the editable store.
/// These aliases belong to the application and cannot be stolen by a different
/// action. Exact modifier matching avoids accidental Shift/Option commands.
enum ShortcutDefaults {
    private static let aliasMaps: [HandLayout: [ShortcutAction: [KeyChord]]] = {
        Dictionary(uniqueKeysWithValues: [HandLayout.left, .right].map { hand in
            (hand, Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { action in
                (action, makeAliases(for: action, hand: hand))
            }))
        })
    }()

    static func aliases(for action: ShortcutAction, hand: HandLayout) -> [KeyChord] {
        aliasMaps[hand]?[action] ?? []
    }

    private static func makeAliases(for action: ShortcutAction, hand: HandLayout) -> [KeyChord] {
        switch action {
        case .seekBackward: return [KeyChord("\u{f702}")]
        case .seekForward: return [KeyChord("\u{f703}")]
        case .seekBackwardLarge: return [KeyChord("\u{f702}", modifiers: .shift)]
        case .seekForwardLarge: return [KeyChord("\u{f703}", modifiers: .shift)]
        case .volumeUp: return [KeyChord("\u{f700}", modifiers: .shift)]
        case .volumeDown: return [KeyChord("\u{f701}", modifiers: .shift)]
        case .openFiles: return [KeyChord("o", modifiers: .command)]
        case .privatePlayback: return [KeyChord("n", modifiers: .command)]
        case .playlist: return [KeyChord("l", modifiers: .command)] + (hand == .right ? [KeyChord("b")] : [])
        case .previousFile: return [KeyChord("\u{f700}"), KeyChord("[", modifiers: .command)]
        case .nextFile: return [KeyChord("\u{f701}"), KeyChord("]", modifiers: .command)]
        case .resetZoom: return [KeyChord("0", modifiers: .command)]
        case .help: return [KeyChord("/"), KeyChord("?"), KeyChord("/", modifiers: .command)]
        case .fullscreen: return [KeyChord("f", modifiers: [.control, .command])]
        case .customizeShortcuts: return [KeyChord(",", modifiers: .command)]
        default: return []
        }
    }

    static func command(for chord: KeyChord, hand: HandLayout, context: ShortcutContext, binding: (ShortcutAction) -> KeyChord?) -> PlayerCommand? {
        if let navigation = navigationCommand(for: chord, hand: hand, context: context) { return navigation }
        for action in ShortcutAction.allCases {
            if aliases(for: action, hand: hand).contains(chord) || binding(action) == chord { return action.command }
        }
        return nil
    }

    static func navigationCommand(for chord: KeyChord, hand: HandLayout, context: ShortcutContext) -> PlayerCommand? {
        let key = chord.key
        let navigation = chord.modifiers.isEmpty || chord.modifiers == .shift
        if navigation && key == "\u{1b}" { return .escape }
        if context != .playback && navigation {
            let up = hand == .left ? "w" : "i", down = hand == .left ? "s" : "k"
            let back = hand == .left ? "a" : "j", forward = hand == .left ? "d" : "l"
            if context == .playlist {
                if key == up || key == "\u{f700}" { return .playlistMove(-1) }
                if key == down || key == "\u{f701}" { return .playlistMove(1) }
                if [back, forward, "\u{f702}", "\u{f703}"].contains(key) { return .playlistMove(0) }
                if key == " " || key == "\r" { return .playlistActivate }
                if key == "\u{f729}" { return .playlistBoundary(false) }
                if key == "\u{f72b}" { return .playlistBoundary(true) }
            } else {
                if key == up || key == "\u{f700}" { return .panelMove(-1) }
                if key == down || key == "\u{f701}" { return .panelMove(1) }
                if key == back || key == "\u{f702}" { return .panelAdjust(-1) }
                if key == forward || key == "\u{f703}" { return .panelAdjust(1) }
                if key == " " || key == "\r" { return .panelActivate }
            }
        }
        return nil
    }
}
