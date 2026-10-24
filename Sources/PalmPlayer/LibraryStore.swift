import Foundation

struct PlaybackBookmark: Codable, Equatable {
    var path: String
    var name: String
    var position: Double
    var duration: Double
    var speed: Double
    var volume: Double
    var subtitleDelay: Double
    var subtitlesVisible: Bool
    var subtitleID: Int?
    var audioID: Int?
    var updatedAt: Date

    init(
        path: String,
        name: String = "",
        position: Double = 0,
        duration: Double = 0,
        speed: Double = 1,
        volume: Double = 70,
        subtitleDelay: Double = 0,
        subtitleID: Int? = nil,
        audioID: Int? = nil,
        updatedAt: Date = Date(),
        subtitlesVisible: Bool = true
    ) {
        self.path = path
        self.name = name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name
        self.position = position
        self.duration = duration
        self.speed = speed
        self.volume = volume
        self.subtitleDelay = subtitleDelay
        self.subtitlesVisible = subtitlesVisible
        self.subtitleID = subtitleID
        self.audioID = audioID
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case path, name, position, duration, speed, volume, subtitleDelay
        case subtitleID, audioID, updatedAt, subtitlesVisible
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try values.decode(String.self, forKey: .path),
            name: try values.decode(String.self, forKey: .name),
            position: try values.decode(Double.self, forKey: .position),
            duration: try values.decode(Double.self, forKey: .duration),
            speed: try values.decode(Double.self, forKey: .speed),
            volume: try values.decode(Double.self, forKey: .volume),
            subtitleDelay: try values.decode(Double.self, forKey: .subtitleDelay),
            subtitleID: try values.decodeIfPresent(Int.self, forKey: .subtitleID),
            audioID: try values.decodeIfPresent(Int.self, forKey: .audioID),
            updatedAt: try values.decode(Date.self, forKey: .updatedAt),
            subtitlesVisible: try values.decodeIfPresent(Bool.self, forKey: .subtitlesVisible) ?? true
        )
    }
}

/// A bounded, local-only history. Passing a directory keeps tests and previews
/// independent of the user's Application Support folder.
final class LibraryStore {
    enum Persistence: Equatable { case immediate, background }
    private(set) var recent: [PlaybackBookmark] = []
    var isPrivate = false {
        didSet { if isPrivate && !oldValue { flush() } }
    }

    private static let historyLimit = 30
    private let directory: URL
    private let backgroundWriter: HistoryWriter?
    private var historyURL: URL { directory.appendingPathComponent("history.json") }

    init(directory: URL? = nil, persistence: Persistence = .immediate) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("PalmPlayer", isDirectory: true)
        backgroundWriter = persistence == .background ? HistoryWriter(directory: self.directory) : nil

        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([PlaybackBookmark].self, from: data) else { return }

        var paths = Set<String>()
        recent = entries.compactMap(Self.validated)
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { paths.insert($0.path).inserted }
            .prefix(Self.historyLimit)
            .map { $0 }
    }

    deinit { flush() }

    /// Explicit shutdown/verification boundary; ordinary playback never waits
    /// for JSON encoding or atomic file replacement on the main thread.
    func flush() { backgroundWriter?.flush() }

    func entry(for url: URL) -> PlaybackBookmark? {
        guard url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        return recent.first { $0.path == path }
    }

    func save(_ entry: PlaybackBookmark) {
        guard !isPrivate, let entry = Self.validated(entry) else { return }
        recent.removeAll { $0.path == entry.path }
        recent.insert(entry, at: 0)
        if recent.count > Self.historyLimit {
            recent.removeLast(recent.count - Self.historyLimit)
        }
        persist()
    }

    func remove(path: String) {
        guard !isPrivate else { return }
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        recent.removeAll { $0.path == path }
        persist()
    }

    func clear() {
        guard !isPrivate else { return }
        recent.removeAll()
        persist()
    }

    /// Expands only the selected folders' immediate children. Explicit input
    /// order is retained, and each selected folder gets a natural filename sort.
    static func playableURLs(from urls: [URL], canRead: (URL) -> Bool = { _ in true }) -> [URL] {
        let manager = FileManager.default
        var result: [URL] = []
        var seen = Set<String>()

        func appendVideo(_ url: URL) {
            let url = url.standardizedFileURL
            guard canRead(url), supportedExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  seen.insert(url.path).inserted else { return }
            result.append(url)
        }

        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            guard canRead(url) else { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                let children = (try? manager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )) ?? []
                for child in children.filter({ supportedExtensions.contains($0.pathExtension.lowercased()) }).sorted(by: {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }) {
                    appendVideo(child)
                }
            } else {
                appendVideo(url)
            }
        }
        return result
    }

    /// The caller supplies its directory access policy: local playback can
    /// permit a session-only parent, while sandbox playback needs a grant.
    static func initialQueue(from urls: [URL], canRead: (URL) -> Bool = { _ in true },
                             allowSiblingAccess: (URL) -> Bool = { _ in false }) -> (urls: [URL], index: Int) {
        let videos = playableURLs(from: urls, canRead: canRead)
        guard urls.count == 1, videos.count == 1,
              (try? urls[0].resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              allowSiblingAccess(videos[0].deletingLastPathComponent()) else {
            return (videos, 0)
        }
        let selected = videos[0].standardizedFileURL
        let siblings = playableURLs(from: [selected.deletingLastPathComponent()], canRead: canRead)
        guard let index = siblings.firstIndex(where: { $0.standardizedFileURL.path == selected.path }) else {
            return ([selected], 0)
        }
        return (siblings, index)
    }

    static func matchingSubtitleURLs(for video: URL, canRead: (URL) -> Bool,
                                     allowDirectory: (URL) -> Bool) -> [URL] {
        let directory = video.deletingLastPathComponent()
        guard allowDirectory(directory) else { return [] }
        let stem = video.deletingPathExtension().lastPathComponent
        let extensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "sup"]
        let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return children.filter { url in
            guard extensions.contains(url.pathExtension.lowercased()), canRead(url) else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            let matches = name.caseInsensitiveCompare(stem) == .orderedSame || [".", " ", "_", "-"].contains {
                name.lowercased().hasPrefix((stem + $0).lowercased())
            }
            return matches && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func subtitleLanguage(for url: URL) -> String {
        let suffix = url.deletingPathExtension().pathExtension.lowercased()
        let aliases = ["eng": "en", "english": "en", "chi": "zh", "zho": "zh", "chs": "zh-Hans", "cht": "zh-Hant", "jpn": "ja", "japanese": "ja", "kor": "ko", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "spa": "es"]
        if let alias = aliases[suffix] { return alias }
        let parts = suffix.split(separator: "-")
        guard let base = parts.first, base.count == 2,
              base.unicodeScalars.allSatisfy({ CharacterSet.lowercaseLetters.contains($0) }) else { return "" }
        return suffix
    }

    static func preferredSubtitle(in urls: [URL], languages: [String]) -> URL? {
        for language in languages {
            let normalized = language.lowercased()
            if let exact = urls.first(where: { subtitleLanguage(for: $0).lowercased() == normalized }) { return exact }
            let base = normalized.split(separator: "-").first
            if let match = urls.first(where: { !subtitleLanguage(for: $0).isEmpty && subtitleLanguage(for: $0).lowercased().split(separator: "-").first == base }) { return match }
        }
        return urls.first
    }

    /// Bookmark resolution can follow a file moved in Finder. Preserve the
    /// playback record under the actual resolved URL before resuming it.
    func relocate(path: String, to url: URL) {
        guard !isPrivate, url.isFileURL,
              var entry = recent.first(where: { $0.path == URL(fileURLWithPath: path).standardizedFileURL.path }) else { return }
        recent.removeAll { $0.path == entry.path }
        entry.path = url.standardizedFileURL.path
        entry.name = url.lastPathComponent
        save(entry)
    }

    private static let supportedExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "mov", "avi", "webm", "mts", "m2ts", "ts",
        "mpg", "mpeg", "m2v", "vob", "wmv", "asf", "flv", "f4v", "ogv",
        "ogg", "3gp", "3g2", "rm", "rmvb", "mxf", "divx"
    ]

    static func isVideoURL(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func validated(_ entry: PlaybackBookmark) -> PlaybackBookmark? {
        guard !entry.path.isEmpty,
              entry.path.hasPrefix("/"),
              entry.position.isFinite, entry.position >= 0,
              entry.duration.isFinite, entry.duration >= 0,
              entry.speed.isFinite, entry.speed > 0,
              entry.volume.isFinite,
              entry.subtitleDelay.isFinite,
              entry.updatedAt.timeIntervalSince1970.isFinite else { return nil }

        var entry = entry
        entry.path = URL(fileURLWithPath: entry.path).standardizedFileURL.path
        if entry.name.isEmpty {
            entry.name = URL(fileURLWithPath: entry.path).lastPathComponent
        }
        entry.volume = min(100, max(0, entry.volume))
        return entry
    }

    private func persist() {
        if let backgroundWriter { backgroundWriter.submit(recent); return }
        Self.write(recent, to: directory)
    }

    private static func write(_ entries: [PlaybackBookmark], to directory: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        } catch {
            // Playback remains usable when the history location is unavailable.
            // The current session's entries are still retained in memory.
        }
    }

    /// One writer and one newest immutable history snapshot. Bursts of progress
    /// updates or clear/save actions cannot accumulate disk work or resurrect an
    /// older history after the newest snapshot has been written.
    private final class HistoryWriter {
        private let directory: URL
        private let queue = DispatchQueue(label: "app.lplayer.history", qos: .utility)
        private let lock = NSLock()
        private var latest: [PlaybackBookmark]?
        private var scheduled = false
        init(directory: URL) { self.directory = directory }
        func submit(_ entries: [PlaybackBookmark]) {
            lock.lock()
            latest = entries
            let needsWorker = !scheduled
            scheduled = true
            lock.unlock()
            if needsWorker { queue.async { self.drain() } }
        }
        private func takeLatest() -> [PlaybackBookmark]? {
            lock.lock(); defer { lock.unlock() }
            let result = latest; latest = nil
            return result
        }
        private func drain() {
            if let entries = takeLatest() { LibraryStore.write(entries, to: directory) }
            lock.lock()
            let again = latest != nil
            if !again { scheduled = false }
            lock.unlock()
            if again { queue.async { self.drain() } }
        }
        func flush() {
            queue.sync {
                while let entries = takeLatest() { LibraryStore.write(entries, to: directory) }
            }
        }
    }
}
