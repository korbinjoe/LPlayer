import Foundation

enum PlayerCommand: Equatable {
    case togglePause, seek(Double), volume(Double), speed(Double), resetSpeed
    case fullscreen, subtitles, undoSeek, panel, help, escape
    case previousFile, nextFile, resetZoom
    case mute, openFiles, privatePlayback, customizeShortcuts
    case zoom(Double), subtitleDelay(Double), cycleTrack(String)
    case panelMove(Int), panelAdjust(Int), panelActivate
    case playlist, playlistMove(Int), playlistActivate, playlistBoundary(Bool)
}

enum HandLayout: String, Codable {
    case left, right
    var title: String { self == .left ? L10n.text("Left hand", "左手") : L10n.text("Right hand", "右手") }
    var panelKey: String { ShortcutStore.defaultBinding(for: .panel, hand: self)!.display }
    var helpKey: String { ShortcutStore.defaultBinding(for: .help, hand: self)!.display }
    var playlistKey: String { ShortcutStore.defaultBinding(for: .playlist, hand: self)!.display }
    var previousKey: String { ShortcutStore.defaultBinding(for: .previousFile, hand: self)!.display }
    var nextKey: String { ShortcutStore.defaultBinding(for: .nextFile, hand: self)!.display }
    var panelAdjustmentKeys: String { self == .left ? "A/D" : "J/L" }
    var movement: String { self == .left ? L10n.text("W/S select · A/D adjust", "W/S 选择 · A/D 调整") : L10n.text("I/K select · J/L adjust", "I/K 选择 · J/L 调整") }
    var playlistMovement: String { self == .left ? L10n.text("W/S or ↑↓ select · Enter to play", "W/S 或 ↑↓ 选择 · 回车播放") : L10n.text("I/K or ↑↓ select · Enter to play", "I/K 或 ↑↓ 选择 · 回车播放") }

    /// Compatibility entry point for callers that need the shipped defaults.
    /// Runtime input uses ShortcutStore so every custom key follows the same rules.
    func command(for key: String, shift: Bool = false, panelOpen: Bool = false, playlistOpen: Bool = false) -> PlayerCommand? {
        let chord = KeyChord(key, modifiers: shift ? .shift : [])
        let context: ShortcutContext = playlistOpen ? .playlist : (panelOpen ? .panel : .playback)
        return ShortcutDefaults.command(for: chord, hand: self, context: context) { action in
            ShortcutStore.defaultBinding(for: action, hand: self)
        }
    }

}

func clockText(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let value = max(0, Int(seconds))
    if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
    return String(format: "%02d:%02d", value / 60, value % 60)
}
