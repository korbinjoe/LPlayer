import Foundation
import XCTest
@testable import PalmPlayer

final class FileAccessStoreTests: XCTestCase {
    private var directory: URL!
    private var media: URL!
    private var starts: [URL] = []
    private var stops: [URL] = []
    private var resolutions = 0
    private var creations = 0
    private var movedTo: URL?
    private var stale = false
    private var failResolution = false
    private var failCreation = false

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LPlayer-AccessTests-\(UUID().uuidString)", isDirectory: true)
        media = directory.appendingPathComponent("Season", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        for name in ["Episode 1.mp4", "Episode 2.mp4", "Episode 1.en.srt", "Episode 1.zh-Hans.srt"] {
            try Data().write(to: media.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private var operations: FileAccessStore.Operations {
        FileAccessStore.Operations(
            createBookmark: { [unowned self] url in
                creations += 1
                if failCreation { throw CocoaError(.fileWriteNoPermission) }
                return Data(url.path.utf8)
            },
            resolveBookmark: { [unowned self] data in
                resolutions += 1
                if failResolution { throw CocoaError(.fileReadNoPermission) }
                return .init(url: movedTo ?? URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), isStale: stale)
            },
            startAccess: { [unowned self] url in starts.append(url); return true },
            stopAccess: { [unowned self] url in stops.append(url) }
        )
    }

    func testSingleSelectionDoesNotAuthorizeParentSiblingsOrSubtitles() {
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: true)
        let selected = media.appendingPathComponent("Episode 2.mp4")
        XCTAssertEqual(access.rememberSelection([selected]), [selected])
        XCTAssertTrue(access.canRead(selected))
        XCTAssertFalse(access.hasDirectoryAccess(to: media))
        XCTAssertFalse(access.canRead(media.appendingPathComponent("Episode 1.mp4")))
        let queue = LibraryStore.initialQueue(from: [selected], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(queue.urls, [selected])
        XCTAssertTrue(LibraryStore.matchingSubtitleURLs(for: selected, canRead: access.canRead, allowDirectory: access.hasDirectoryAccess).isEmpty)
    }

    func testOrdinaryLocalSelectionLoadsNaturalSiblingQueueAtSelectedIndex() throws {
        try Data().write(to: media.appendingPathComponent("Episode 10.MKV"))
        try Data().write(to: media.appendingPathComponent("Notes.txt"))
        let nested = media.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("Episode 3.mp4"))
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        let selected = media.appendingPathComponent("Episode 2.mp4")
        access.rememberSelection([selected])
        XCTAssertFalse(access.requiresExplicitDirectorySelection)
        XCTAssertTrue(access.preparePlaylistDirectory(for: selected))
        XCTAssertTrue(access.hasDirectoryAccess(to: media))
        let queue = LibraryStore.initialQueue(from: [selected], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(queue.urls.map(\.lastPathComponent), ["Episode 1.mp4", "Episode 2.mp4", "Episode 10.MKV"])
        XCTAssertEqual(queue.index, 1)
        for video in queue.urls { XCTAssertEqual(access.authorizedURL(for: video), video) }
        XCTAssertEqual(starts, [selected])
        XCTAssertTrue(stops.isEmpty)
        XCTAssertEqual(LibraryStore.matchingSubtitleURLs(for: queue.urls[0], canRead: access.canRead, allowDirectory: access.hasDirectoryAccess).count, 2)
    }

    func testPrivateAutomaticDirectoryNeverSavesOrStartsAParentScope() {
        let selected = media.appendingPathComponent("Episode 1.mp4")
        var access: FileAccessStore? = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        access!.rememberSelection([selected], persist: false)
        XCTAssertTrue(access!.preparePlaylistDirectory(for: selected))
        XCTAssertTrue(access!.preparePlaylistDirectory(for: selected))
        XCTAssertTrue(access!.canRead(media.appendingPathComponent("Episode 2.mp4")))
        XCTAssertEqual(starts, [selected])
        XCTAssertEqual(creations, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("file-access.json").path))
        access = nil
        XCTAssertEqual(stops, [selected])
        let nextSession = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        XCTAssertFalse(nextSession.hasDirectoryAccess(to: media))
        XCTAssertFalse(nextSession.canRead(selected))
    }

    func testLaterExplicitFileSelectionNeverPersistsAutomaticParent() throws {
        let first = media.appendingPathComponent("Episode 1.mp4")
        let second = media.appendingPathComponent("Episode 2.mp4")
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        access.rememberSelection([first], persist: false)
        XCTAssertTrue(access.preparePlaylistDirectory(for: first))
        XCTAssertEqual(access.rememberSelection([second]), [second])
        // Even re-saving the original file must not upgrade its parent scope.
        XCTAssertEqual(access.rememberSelection([first]), [first])
        let data = try Data(contentsOf: directory.appendingPathComponent("file-access.json"))
        let entries = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertEqual(Set(entries.compactMap { $0["path"] as? String }), Set([first.path, second.path]))
        XCTAssertTrue(entries.allSatisfy { ($0["isDirectory"] as? Bool) == false })
        XCTAssertEqual(starts, [first, second])
        let nextSession = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        XCTAssertTrue(nextSession.canRead(first))
        XCTAssertTrue(nextSession.canRead(second))
        XCTAssertFalse(nextSession.hasDirectoryAccess(to: media))
        XCTAssertTrue(nextSession.preparePlaylistDirectory(for: first))
    }

    func testSandboxedSingleFileStillRequiresExplicitDirectorySelection() {
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: true)
        let selected = media.appendingPathComponent("Episode 2.mp4")
        access.rememberSelection([selected])
        XCTAssertTrue(access.requiresExplicitDirectorySelection)
        XCTAssertFalse(access.preparePlaylistDirectory(for: selected))
        XCTAssertFalse(access.canRead(media.appendingPathComponent("Episode 1.mp4")))
        let single = LibraryStore.initialQueue(from: [selected], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(single.urls, [selected])
        access.rememberSelection([media])
        XCTAssertTrue(access.preparePlaylistDirectory(for: selected))
        let folder = LibraryStore.initialQueue(from: [selected], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(folder.urls.count, 2)
        XCTAssertEqual(folder.index, 1)
    }

    func testBareHistoryPathCannotSeedButRestoredSelectedFileCanPrepareDirectory() {
        let selected = media.appendingPathComponent("Episode 1.mp4")
        let bare = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        XCTAssertFalse(bare.preparePlaylistDirectory(for: selected))
        XCTAssertFalse(bare.hasDirectoryAccess(to: media))
        XCTAssertTrue(starts.isEmpty)
        FileAccessStore(directory: directory, operations: operations, sandboxed: false).rememberSelection([selected])
        let restored = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        XCTAssertTrue(restored.canRead(selected))
        XCTAssertFalse(restored.canRead(media.appendingPathComponent("Episode 2.mp4")))
        XCTAssertTrue(restored.preparePlaylistDirectory(for: selected))
        XCTAssertTrue(restored.canRead(media.appendingPathComponent("Episode 2.mp4")))
        let queue = LibraryStore.initialQueue(from: [selected], canRead: restored.canRead, allowSiblingAccess: restored.hasDirectoryAccess)
        XCTAssertEqual(queue.urls.count, 2)
        XCTAssertEqual(queue.index, 0)
    }

    func testFailedAndNonFileSelectionsCannotSeedAutomaticDirectory() throws {
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        let missing = media.appendingPathComponent("Missing.mp4")
        XCTAssertTrue(access.rememberSelection([missing], persist: false).isEmpty)
        XCTAssertFalse(access.preparePlaylistDirectory(for: missing))
        XCTAssertFalse(access.preparePlaylistDirectory(for: URL(string: "https://example.com/video.mp4")!))
        let selected = media.appendingPathComponent("Episode 1.mp4")
        access.rememberSelection([selected], persist: false)
        try FileManager.default.removeItem(at: selected)
        XCTAssertFalse(access.preparePlaylistDirectory(for: selected))
        access.rememberSelection([media], persist: false)
        XCTAssertFalse(access.preparePlaylistDirectory(for: media))
        XCTAssertFalse(access.hasDirectoryAccess(to: directory))
    }

    func testAutomaticDirectoryCannotEscapeComponentOrSymlinkBoundaries() throws {
        let adjacent = directory.appendingPathComponent("Season 2", isDirectory: true)
        try FileManager.default.createDirectory(at: adjacent, withIntermediateDirectories: true)
        let outside = adjacent.appendingPathComponent("Episode 3.mp4")
        try Data().write(to: outside)
        let escapedFile = media.appendingPathComponent("Episode 3.mp4")
        let escapedFolder = media.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: escapedFile, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: escapedFolder, withDestinationURL: adjacent)
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        let selected = media.appendingPathComponent("Episode 1.mp4")
        access.rememberSelection([selected], persist: false)
        XCTAssertTrue(access.preparePlaylistDirectory(for: selected))
        XCTAssertFalse(access.canRead(outside))
        XCTAssertFalse(access.canRead(escapedFile))
        XCTAssertFalse(access.canRead(escapedFolder.appendingPathComponent("Episode 3.mp4")))
        XCTAssertFalse(access.hasDirectoryAccess(to: adjacent))
        XCTAssertFalse(access.hasDirectoryAccess(to: directory))
        let queue = LibraryStore.initialQueue(from: [selected], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(queue.urls.map(\.lastPathComponent), ["Episode 1.mp4", "Episode 2.mp4"])
    }

    func testSelectedSymlinkOutsideParentCannotSeedAutomaticDirectory() throws {
        let outside = directory.appendingPathComponent("Outside.mp4")
        try Data().write(to: outside)
        let selected = media.appendingPathComponent("Link.mp4")
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: outside)
        let access = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        XCTAssertTrue(access.rememberSelection([selected], persist: false).isEmpty)
        XCTAssertFalse(access.canRead(selected))
        XCTAssertFalse(access.preparePlaylistDirectory(for: selected))
        XCTAssertFalse(access.hasDirectoryAccess(to: media))
    }

    func testAutomaticDirectoryStaysSessionOnlyAfterSavedFileRestoration() {
        let selected = media.appendingPathComponent("Episode 2.mp4")
        var access: FileAccessStore? = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        access!.rememberSelection([selected])
        XCTAssertTrue(access!.preparePlaylistDirectory(for: selected))
        access = nil
        let nextSession = FileAccessStore(directory: directory, operations: operations, sandboxed: false)
        XCTAssertTrue(nextSession.canRead(selected))
        XCTAssertFalse(nextSession.hasDirectoryAccess(to: media))
        XCTAssertFalse(nextSession.canRead(media.appendingPathComponent("Episode 1.mp4")))
        nextSession.rememberSelection([selected], persist: false)
        XCTAssertTrue(nextSession.preparePlaylistDirectory(for: selected))
        XCTAssertTrue(nextSession.canRead(media.appendingPathComponent("Episode 1.mp4")))
    }

    func testDirectoryScopeCoversChildrenAndPreviewsWithoutStartingEachChild() {
        let access = FileAccessStore(directory: directory, operations: operations)
        access.rememberSelection([media])
        let first = media.appendingPathComponent("Episode 1.mp4")
        let second = media.appendingPathComponent("Episode 2.mp4")
        XCTAssertTrue(access.preparePlaylistDirectory(for: second))
        let queue = LibraryStore.initialQueue(from: [second], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(queue.urls, [first, second])
        XCTAssertEqual(queue.index, 1)
        XCTAssertEqual(LibraryStore.matchingSubtitleURLs(for: first, canRead: access.canRead, allowDirectory: access.hasDirectoryAccess).count, 2)
        XCTAssertTrue(access.canRead(first))
        XCTAssertTrue(access.canRead(second))
        XCTAssertEqual(starts, [media])
        XCTAssertTrue(stops.isEmpty)
    }

    func testSavedDirectoryRestoresLazilyAndKeepsScopeThroughRepeatedReads() {
        var access: FileAccessStore? = FileAccessStore(directory: directory, operations: operations)
        access!.rememberSelection([media])
        access = nil
        XCTAssertEqual(stops.count, 1)
        starts.removeAll(); stops.removeAll()
        access = FileAccessStore(directory: directory, operations: operations)
        XCTAssertTrue(starts.isEmpty)
        let video = media.appendingPathComponent("Episode 1.mp4")
        XCTAssertNotNil(access!.authorizedURL(for: video))
        XCTAssertNotNil(access!.authorizedURL(for: video))
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(starts, [media])
        XCTAssertTrue(stops.isEmpty)
        access = nil
        XCTAssertEqual(stops, [media])
    }

    func testPrivateSelectionDoesNotWriteBookmarks() {
        let access = FileAccessStore(directory: directory, operations: operations)
        access.rememberSelection([media], persist: false)
        XCTAssertTrue(access.hasDirectoryAccess(to: media))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("file-access.json").path))
        XCTAssertEqual(creations, 0)
    }

    func testClearingSavedAccessDoesNotRevokeActiveDecoderScope() {
        let access = FileAccessStore(directory: directory, operations: operations)
        access.rememberSelection([media])
        access.clearSavedBookmarks()
        XCTAssertTrue(access.canRead(media.appendingPathComponent("Episode 1.mp4")))
        XCTAssertTrue(stops.isEmpty)
        let nextSession = FileAccessStore(directory: directory, operations: operations)
        XCTAssertNil(nextSession.authorizedURL(for: media.appendingPathComponent("Episode 1.mp4")))
    }

    func testBareHistoryPathNeverRestoresWithoutAGrant() {
        let access = FileAccessStore(directory: directory, operations: operations)
        XCTAssertNil(access.authorizedURL(for: media.appendingPathComponent("Episode 1.mp4")))
        XCTAssertTrue(starts.isEmpty)
    }

    func testRevokedBookmarkRequiresReselection() {
        FileAccessStore(directory: directory, operations: operations).rememberSelection([media])
        failResolution = true
        let restored = FileAccessStore(directory: directory, operations: operations)
        XCTAssertNil(restored.authorizedURL(for: media.appendingPathComponent("Episode 1.mp4")))
        XCTAssertFalse(restored.hasDirectoryAccess(to: media))
    }

    func testMissingDescendantDoesNotRepeatedlyStartContainingScope() {
        FileAccessStore(directory: directory, operations: operations).rememberSelection([media])
        starts.removeAll()
        let restored = FileAccessStore(directory: directory, operations: operations)
        let missing = media.appendingPathComponent("Missing.mp4")
        XCTAssertNil(restored.authorizedURL(for: missing))
        XCTAssertNil(restored.authorizedURL(for: missing))
        XCTAssertEqual(starts, [media])
        XCTAssertEqual(resolutions, 1)
    }

    func testMovedDirectoryTranslatesOldHistoryPathAndRefreshesStaleBookmark() throws {
        FileAccessStore(directory: directory, operations: operations).rememberSelection([media])
        let previous = media.appendingPathComponent("Episode 1.mp4")
        let destination = directory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: media, to: destination)
        movedTo = destination; stale = true
        let restored = FileAccessStore(directory: directory, operations: operations)
        XCTAssertEqual(restored.authorizedURL(for: previous), destination.appendingPathComponent("Episode 1.mp4"))
        XCTAssertEqual(creations, 2)
        // App history now points at the actual location. A third process must
        // find the refreshed grant using that new history path.
        movedTo = nil; stale = false
        let nextLaunch = FileAccessStore(directory: directory, operations: operations)
        XCTAssertEqual(nextLaunch.authorizedURL(for: destination.appendingPathComponent("Episode 1.mp4")), destination.appendingPathComponent("Episode 1.mp4"))
        XCTAssertEqual(nextLaunch.authorizedURL(for: media.appendingPathComponent("Episode 2.mp4")), destination.appendingPathComponent("Episode 2.mp4"))
        let anotherLaunch = FileAccessStore(directory: directory, operations: operations)
        XCTAssertEqual(anotherLaunch.authorizedURL(for: media.appendingPathComponent("Episode 2.mp4")), destination.appendingPathComponent("Episode 2.mp4"))
    }

    func testMovedFileRefreshesSavedIndexEvenWhenBookmarkIsNotStale() throws {
        let previous = media.appendingPathComponent("Episode 1.mp4")
        FileAccessStore(directory: directory, operations: operations).rememberSelection([previous])
        let destination = media.appendingPathComponent("Renamed.mp4")
        try FileManager.default.moveItem(at: previous, to: destination)
        movedTo = destination
        let secondLaunch = FileAccessStore(directory: directory, operations: operations)
        XCTAssertEqual(secondLaunch.authorizedURL(for: previous), destination)
        movedTo = nil
        let thirdLaunch = FileAccessStore(directory: directory, operations: operations)
        XCTAssertEqual(thirdLaunch.authorizedURL(for: destination), destination)
    }

    func testExplicitSelectionDoesNotFollowHistoryAliasToDifferentFile() throws {
        let oldVideo = media.appendingPathComponent("Episode 1.mp4")
        FileAccessStore(directory: directory, operations: operations).rememberSelection([media])
        let destination = directory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: media, to: destination)
        movedTo = destination
        let current = FileAccessStore(directory: directory, operations: operations)
        let movedVideo = destination.appendingPathComponent("Episode 1.mp4")
        XCTAssertEqual(current.authorizedURL(for: oldVideo), movedVideo)

        // Finder's old location is occupied again. This selection must play
        // the newly selected file, while the moved grant stays available.
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("different file".utf8).write(to: oldVideo)
        movedTo = nil
        XCTAssertEqual(current.rememberSelection([oldVideo]), [oldVideo])
        XCTAssertEqual(current.rememberSelection([movedVideo]), [movedVideo])
        let nextLaunch = FileAccessStore(directory: directory, operations: operations)
        XCTAssertEqual(nextLaunch.authorizedURL(for: movedVideo), movedVideo)
        XCTAssertEqual(nextLaunch.authorizedURL(for: oldVideo), oldVideo)
    }

    func testBookmarkCreationFailureStillAllowsCurrentSelection() {
        failCreation = true
        let access = FileAccessStore(directory: directory, operations: operations)
        let video = media.appendingPathComponent("Episode 1.mp4")
        XCTAssertEqual(access.rememberSelection([video]), [video])
        XCTAssertTrue(access.canRead(video))
        XCTAssertTrue(access.couldNotPersistSelection)
    }

    func testDirectoryBoundariesAndSymlinksCannotEscapeAGrant() throws {
        let adjacent = directory.appendingPathComponent("Season 2", isDirectory: true)
        try FileManager.default.createDirectory(at: adjacent, withIntermediateDirectories: true)
        let outside = adjacent.appendingPathComponent("Episode 3.mp4")
        try Data().write(to: outside)
        let link = media.appendingPathComponent("Episode 3.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let access = FileAccessStore(directory: directory, operations: operations)
        access.rememberSelection([media])
        XCTAssertFalse(access.canRead(outside))
        XCTAssertFalse(access.canRead(link))
        let queue = LibraryStore.initialQueue(from: [media], canRead: access.canRead, allowSiblingAccess: access.hasDirectoryAccess)
        XCTAssertEqual(queue.urls.map(\.lastPathComponent), ["Episode 1.mp4", "Episode 2.mp4"])
    }

    func testSubtitleLanguagePreferenceAndFilenameBoundaries() throws {
        try Data().write(to: media.appendingPathComponent("Episode 10.srt"))
        let access = FileAccessStore(directory: directory, operations: operations)
        access.rememberSelection([media])
        let subtitles = LibraryStore.matchingSubtitleURLs(for: media.appendingPathComponent("Episode 1.mp4"), canRead: access.canRead, allowDirectory: access.hasDirectoryAccess)
        XCTAssertEqual(subtitles.count, 2)
        XCTAssertEqual(LibraryStore.preferredSubtitle(in: subtitles, languages: ["zh-CN", "en"])?.lastPathComponent, "Episode 1.zh-Hans.srt")
        XCTAssertEqual(LibraryStore.preferredSubtitle(in: subtitles, languages: ["en-US"])?.lastPathComponent, "Episode 1.en.srt")
    }
}
