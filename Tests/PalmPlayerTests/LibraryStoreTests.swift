import Foundation
import XCTest
@testable import PalmPlayer

final class LibraryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PalmPlayer-LibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRestoresPlaybackPreferencesFromDisk() throws {
        let video = directory.appendingPathComponent("Movie.mkv")
        let store = LibraryStore(directory: directory)
        let bookmark = PlaybackBookmark(
            path: video.path,
            name: "Movie",
            position: 125.5,
            duration: 4_000,
            speed: 1.25,
            volume: 47,
            subtitleDelay: -0.25,
            subtitleID: 2,
            audioID: 3,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.save(bookmark)

        let reopened = LibraryStore(directory: directory)
        XCTAssertEqual(reopened.entry(for: video), bookmark)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    func testDisabledSubtitlesRemainDisabledAfterReopening() {
        let video = directory.appendingPathComponent("Movie.mkv")
        let bookmark = PlaybackBookmark(path: video.path, position: 25, subtitlesVisible: false)
        LibraryStore(directory: directory).save(bookmark)

        XCTAssertEqual(LibraryStore(directory: directory).entry(for: video), bookmark)
        XCTAssertEqual(LibraryStore(directory: directory).entry(for: video)?.subtitlesVisible, false)
    }

    func testOlderHistoryWithoutSubtitleVisibilityDefaultsToVisible() throws {
        let video = directory.appendingPathComponent("Older.mkv")
        let bookmark = PlaybackBookmark(path: video.path, position: 45)
        let encoded = try JSONEncoder().encode([bookmark])
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        legacy[0].removeValue(forKey: "subtitlesVisible")
        let data = try JSONSerialization.data(withJSONObject: legacy)
        try data.write(to: directory.appendingPathComponent("history.json"))

        let restored = LibraryStore(directory: directory).entry(for: video)
        XCTAssertEqual(restored, bookmark)
        XCTAssertEqual(restored?.subtitlesVisible, true)
    }

    func testPrivateModeDoesNotChangeMemoryOrDisk() throws {
        let store = LibraryStore(directory: directory)
        let original = PlaybackBookmark(path: directory.appendingPathComponent("Original.mp4").path, position: 12)
        store.save(original)
        let historyURL = directory.appendingPathComponent("history.json")
        let before = try Data(contentsOf: historyURL)

        store.isPrivate = true
        store.save(PlaybackBookmark(path: original.path, position: 90))
        store.save(PlaybackBookmark(path: directory.appendingPathComponent("Private.mp4").path))
        store.remove(path: original.path)
        store.clear()

        XCTAssertEqual(store.recent, [original])
        XCTAssertEqual(try Data(contentsOf: historyURL), before)
        XCTAssertEqual(LibraryStore(directory: directory).recent, [original])
    }

    func testPrivateSessionDoesNotCreateHistoryFile() {
        let store = LibraryStore(directory: directory)
        store.isPrivate = true
        store.save(PlaybackBookmark(path: directory.appendingPathComponent("Private.mp4").path))
        XCTAssertTrue(store.recent.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    func testHistoryIsBoundedAndReopeningPromotesAnExistingFile() {
        let store = LibraryStore(directory: directory)
        for index in 0..<35 {
            store.save(PlaybackBookmark(
                path: directory.appendingPathComponent("Episode \(index).mkv").path,
                updatedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        XCTAssertEqual(store.recent.count, 30)
        XCTAssertEqual(store.recent.first?.name, "Episode 34.mkv")
        XCTAssertEqual(store.recent.last?.name, "Episode 5.mkv")

        let existing = directory.appendingPathComponent("Episode 10.mkv")
        store.save(PlaybackBookmark(path: existing.path, position: 42, updatedAt: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(store.recent.count, 30)
        XCTAssertEqual(store.recent.first?.path, existing.path)
        XCTAssertEqual(store.recent.filter { $0.path == existing.path }.count, 1)
        XCTAssertEqual(LibraryStore(directory: directory).recent, store.recent)
    }

    func testInvalidPlaybackNumbersCannotReplaceAValidEntry() {
        let store = LibraryStore(directory: directory)
        let valid = PlaybackBookmark(path: directory.appendingPathComponent("Movie.mp4").path, position: 20)
        store.save(valid)
        for position in [Double.nan, Double.infinity, -Double.infinity, -1] {
            var invalid = valid
            invalid.position = position
            store.save(invalid)
        }
        var invalidDuration = valid
        invalidDuration.duration = .infinity
        store.save(invalidDuration)
        var invalidSpeed = valid
        invalidSpeed.speed = 0
        store.save(invalidSpeed)
        XCTAssertEqual(store.recent, [valid])
        XCTAssertEqual(LibraryStore(directory: directory).recent, [valid])
    }

    func testCorruptHistoryIsIgnoredAndNextSaveRecovers() throws {
        try Data("interrupted or invalid JSON".utf8).write(to: directory.appendingPathComponent("history.json"))
        let store = LibraryStore(directory: directory)
        XCTAssertTrue(store.recent.isEmpty)
        let bookmark = PlaybackBookmark(path: directory.appendingPathComponent("Recovered.mp4").path)
        store.save(bookmark)
        XCTAssertEqual(LibraryStore(directory: directory).recent, [bookmark])
    }

    func testSelectedFolderUsesNaturalOrderWithoutRecursing() throws {
        let folder = directory.appendingPathComponent("Season", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["Episode 10.mkv", "Episode 2.MP4", "Episode 1.mov", "notes.txt", ".hidden.mp4"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("Episode 3.mp4"))

        let urls = LibraryStore.playableURLs(from: [folder])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["Episode 1.mov", "Episode 2.MP4", "Episode 10.mkv"])
    }

    func testExplicitFilesRetainOrderAndRemoveDuplicates() throws {
        let first = directory.appendingPathComponent("First.mkv")
        let second = directory.appendingPathComponent("Second.mp4")
        let subtitle = directory.appendingPathComponent("Second.srt")
        for url in [first, second, subtitle] { try Data().write(to: url) }

        let urls = LibraryStore.playableURLs(from: [second, first, second, subtitle, URL(string: "https://example.com/movie.mp4")!])
        XCTAssertEqual(urls, [second, first])
    }

    func testRemoveAndClearArePersisted() {
        let store = LibraryStore(directory: directory)
        let first = PlaybackBookmark(path: directory.appendingPathComponent("First.mp4").path)
        let second = PlaybackBookmark(path: directory.appendingPathComponent("Second.mp4").path)
        store.save(first)
        store.save(second)
        store.remove(path: first.path)
        XCTAssertEqual(LibraryStore(directory: directory).recent, [second])
        store.clear()
        XCTAssertTrue(LibraryStore(directory: directory).recent.isEmpty)
    }

    func testMovedFileKeepsPlaybackPreferencesAtResolvedPath() {
        let old = directory.appendingPathComponent("Old.mp4")
        let moved = directory.appendingPathComponent("Moved.mp4")
        let store = LibraryStore(directory: directory)
        store.save(PlaybackBookmark(path: old.path, position: 125, speed: 1.5, subtitlesVisible: false))
        store.relocate(path: old.path, to: moved)
        XCTAssertNil(store.entry(for: old))
        XCTAssertEqual(store.entry(for: moved)?.position, 125)
        XCTAssertEqual(store.entry(for: moved)?.speed, 1.5)
        XCTAssertEqual(store.entry(for: moved)?.subtitlesVisible, false)
    }
}
