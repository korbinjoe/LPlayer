import Foundation
import Security

/// File-system permission is separate from PlaybackBookmark, which only stores
/// playback preferences. Only URLs supplied by a user action create grants.
final class FileAccessStore {
    struct Resolution {
        var url: URL
        var isStale: Bool
    }

    /// Injectable operations let tests exercise revoked/stale scopes without
    /// giving a test runner access to the user's folders.
    struct Operations {
        var createBookmark: (URL) throws -> Data
        var resolveBookmark: (Data) throws -> Resolution
        var startAccess: (URL) -> Bool
        var stopAccess: (URL) -> Void

        static let system = Operations(
            createBookmark: { try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) },
            resolveBookmark: {
                var stale = false
                let url = try URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                return Resolution(url: url, isStale: stale)
            },
            startAccess: { $0.startAccessingSecurityScopedResource() },
            stopAccess: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    private struct SavedGrant: Codable {
        var id: UUID? = nil
        var path: String
        var previousPaths: [String]? = nil
        var isDirectory: Bool
        var bookmark: Data
        var updatedAt: Date
    }

    private struct ActiveGrant {
        let id: UUID
        let originalURL: URL
        let aliasURLs: [URL]
        // Retain the actual URL supplied by the system; rebuilding a URL from
        // its path discards the URL's security-scoped information.
        let scopedURL: URL
        let isDirectory: Bool
        let didStartAccess: Bool
    }

    private let directory: URL
    private let operations: Operations
    private var saved: [SavedGrant] = []
    private var active: [ActiveGrant] = []
    // These roots describe this process's ordinary file-system access. They
    // are not security-scoped grants and must never enter bookmark storage.
    private var automaticDirectoryRoots: [URL] = []
    private var defersBookmarkWrite = false
    private var bookmarkWritePending = false
    let requiresExplicitDirectorySelection: Bool
    private(set) var couldNotPersistSelection = false
    private var bookmarksURL: URL { directory.appendingPathComponent("file-access.json") }
    private static let savedLimit = 96

    /// A missing sandbox entitlement means ordinary local access; an unknown
    /// entitlement result fails closed and keeps directory selection explicit.
    static var isSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return true }
        var error: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, &error)
        if let error { _ = error.takeRetainedValue(); return true }
        guard let value else { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return true }
        return (value as? Bool) ?? true
    }

    init(directory: URL? = nil, operations: Operations = .system, sandboxed: Bool = FileAccessStore.isSandboxed) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PalmPlayer", isDirectory: true)
        self.operations = operations
        requiresExplicitDirectorySelection = sandboxed
        if let data = try? Data(contentsOf: bookmarksURL),
           let entries = try? JSONDecoder().decode([SavedGrant].self, from: data) {
            var seen = Set<String>()
            saved = entries.filter {
                $0.path.hasPrefix("/") && !$0.bookmark.isEmpty && $0.updatedAt.timeIntervalSince1970.isFinite
                    && seen.insert($0.path).inserted
            }.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.savedLimit).map {
                var entry = $0
                if entry.id == nil { entry.id = UUID() }
                return entry
            }
        }
    }

    deinit {
        // Playback and the two thumbnail decoders are asynchronous. A grant is
        // session-owned, so a queue replacement or cancelled preview cannot
        // revoke a scope while a decoder still has work in flight. The player
        // owns this store for its entire process lifetime.
        for grant in active where grant.didStartAccess { operations.stopAccess(grant.scopedURL) }
    }

    /// Call only for NSOpenPanel, Finder-open, drag-and-drop, or explicit CLI
    /// inputs. A failed bookmark still permits the current user-selected file
    /// to play; a future session will ask the user to select it again.
    @discardableResult
    func rememberSelection(_ urls: [URL], persist: Bool = true) -> [URL] {
        couldNotPersistSelection = false
        defersBookmarkWrite = true
        defer {
            defersBookmarkWrite = false
            if bookmarkWritePending {
                bookmarkWritePending = false
                persistSavedGrants()
            }
        }
        var accepted: [URL] = []
        for url in urls where url.isFileURL {
            // Explicit selections describe the file at its current location.
            // Old aliases belong only to history restoration; an old location
            // may now contain an entirely different file chosen by the user.
            if let existing = activeURL(for: url, translatingAliases: false) {
                accepted.append(existing)
                if persist { saveGrant(resolvedURL: existing) }
                continue
            }
            let didStart = operations.startAccess(url)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            guard values?.isDirectory == true || values?.isRegularFile == true,
                  FileManager.default.isReadableFile(atPath: url.path) else {
                if didStart { operations.stopAccess(url) }
                continue
            }
            active.append(ActiveGrant(id: UUID(), originalURL: url.standardizedFileURL, aliasURLs: [], scopedURL: url,
                                      isDirectory: values?.isDirectory == true, didStartAccess: didStart))
            accepted.append(url)
            if persist { saveGrant(resolvedURL: url) }
        }
        return accepted
    }

    /// The unsandboxed app can discover siblings of an authorized file opened
    /// by the user. This does not save or fabricate a directory grant.
    /// Sandboxed builds still require an explicit containing-folder selection.
    @discardableResult
    func preparePlaylistDirectory(for selected: URL) -> Bool {
        guard selected.isFileURL,
              canRead(selected),
              (try? selected.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
        let parent = selected.deletingLastPathComponent().standardizedFileURL
        if hasDirectoryAccess(to: parent) { return true }
        guard !requiresExplicitDirectorySelection,
              (try? parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              FileManager.default.isReadableFile(atPath: parent.path),
              Self.covers(root: parent, isDirectory: true, url: selected) else { return false }
        if !automaticDirectoryRoots.contains(where: { Self.covers(root: $0, isDirectory: true, url: parent) }) {
            automaticDirectoryRoots.append(parent)
        }
        return true
    }

    /// Resolve existing session access or a saved grant. A bare path from
    /// watch history never establishes permission outside an authorized root.
    func authorizedURL(for url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        if let existing = activeURL(for: url, translatingAliases: false) { return existing }
        if let existing = automaticURL(for: url) { return existing }
        let candidates = saved.filter { entry in
            ([entry.path] + (entry.previousPaths ?? [])).contains { path in
                Self.lexicallyCovers(root: URL(fileURLWithPath: path), isDirectory: entry.isDirectory, url: url)
            }
        }.sorted { lhs, rhs in
            let lhsDirect = Self.lexicallyCovers(root: URL(fileURLWithPath: lhs.path), isDirectory: lhs.isDirectory, url: url)
            let rhsDirect = Self.lexicallyCovers(root: URL(fileURLWithPath: rhs.path), isDirectory: rhs.isDirectory, url: url)
            return lhsDirect && !rhsDirect
        }
        for entry in candidates {
            // A missing descendant must not start the same containing scope
            // repeatedly while a playlist checks its rows.
            if let existing = active.first(where: { $0.id == entry.id }) {
                if let authorized = activeURL(for: url, grantID: existing.id) { return authorized }
                continue
            }
            guard let resolved = try? operations.resolveBookmark(entry.bookmark), resolved.url.isFileURL else { continue }
            let didStart = operations.startAccess(resolved.url)
            let values = try? resolved.url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            guard (entry.isDirectory ? values?.isDirectory == true : values?.isRegularFile == true),
                  FileManager.default.isReadableFile(atPath: resolved.url.path) else {
                if didStart { operations.stopAccess(resolved.url) }
                continue
            }
            let matchingPath = ([entry.path] + (entry.previousPaths ?? [])).first {
                Self.lexicallyCovers(root: URL(fileURLWithPath: $0), isDirectory: entry.isDirectory, url: url)
            } ?? entry.path
            let aliases = ([entry.path] + (entry.previousPaths ?? [])).map { URL(fileURLWithPath: $0) }
            let grant = ActiveGrant(id: entry.id ?? UUID(), originalURL: URL(fileURLWithPath: matchingPath), aliasURLs: aliases, scopedURL: resolved.url,
                                    isDirectory: entry.isDirectory, didStartAccess: didStart)
            active.append(grant)
            if resolved.isStale || resolved.url.standardizedFileURL.path != entry.path {
                saveGrant(resolvedURL: resolved.url)
            }
            if let authorized = activeURL(for: url, grantID: grant.id) { return authorized }
        }
        return activeURL(for: url)
    }

    func canRead(_ url: URL) -> Bool { authorizedURL(for: url) != nil }

    /// Immutable copies of already-active scopes. Directory enumeration may
    /// check these on its worker without resolving/mutating bookmarks there.
    /// The store keeps the real scoped URLs alive for the process lifetime.
    struct ReadSnapshot {
        fileprivate let roots: [(url: URL, isDirectory: Bool)]
        func canRead(_ url: URL) -> Bool {
            url.isFileURL && roots.contains { FileAccessStore.covers(root: $0.url, isDirectory: $0.isDirectory, url: url) }
                && FileManager.default.isReadableFile(atPath: url.path)
        }
        func hasDirectoryAccess(to url: URL) -> Bool {
            roots.contains { $0.isDirectory && FileAccessStore.covers(root: $0.url, isDirectory: true, url: url) }
                && FileManager.default.isReadableFile(atPath: url.path)
        }
    }

    func readSnapshot() -> ReadSnapshot {
        ReadSnapshot(roots: active.map { ($0.scopedURL, $0.isDirectory) }
            + automaticDirectoryRoots.map { ($0, true) })
    }

    /// A saved/selected directory scope works in every build. Ordinary local
    /// access can additionally cover a session-only playlist directory.
    func hasDirectoryAccess(to directoryURL: URL) -> Bool {
        guard let resolved = authorizedURL(for: directoryURL) else { return false }
        return active.contains { grant in
            grant.isDirectory && Self.covers(root: grant.scopedURL, isDirectory: true, url: resolved)
        } || automaticDirectoryRoots.contains { Self.covers(root: $0, isDirectory: true, url: resolved) }
    }

    func clearSavedBookmarks() {
        saved.removeAll()
        try? FileManager.default.removeItem(at: bookmarksURL)
        // Active grants remain valid for the current playback session.
    }

    private func activeURL(for requested: URL, translatingAliases: Bool = true, grantID: UUID? = nil) -> URL? {
        for grant in active where grantID == nil || grant.id == grantID {
            let translated: URL
            if translatingAliases, let original = ([grant.originalURL] + grant.aliasURLs).first(where: { Self.lexicallyCovers(root: $0, isDirectory: grant.isDirectory, url: requested) }) {
                let relative = requested.standardizedFileURL.pathComponents.dropFirst(original.standardizedFileURL.pathComponents.count)
                translated = relative.reduce(grant.scopedURL) { $0.appendingPathComponent($1) }
            } else {
                translated = requested
            }
            if Self.covers(root: grant.scopedURL, isDirectory: grant.isDirectory, url: translated),
               FileManager.default.isReadableFile(atPath: translated.path) { return translated }
        }
        return nil
    }

    private func automaticURL(for requested: URL) -> URL? {
        guard automaticDirectoryRoots.contains(where: { Self.covers(root: $0, isDirectory: true, url: requested) }),
              FileManager.default.isReadableFile(atPath: requested.path) else { return nil }
        return requested
    }

    private func saveGrant(resolvedURL: URL) {
        guard let grant = active.first(where: { Self.covers(root: $0.scopedURL, isDirectory: $0.isDirectory, url: resolvedURL) }) else { return }
        // A containing directory grant is sufficient and avoids creating one
        // security scope per episode and per subtitle.
        let root = grant.scopedURL
        let originalPath = grant.originalURL.standardizedFileURL.path
        let resolvedPath = root.standardizedFileURL.path
        do {
            let bookmark = try operations.createBookmark(root)
            let previous = saved.filter { $0.id == grant.id || $0.path == resolvedPath }
            var aliases = [originalPath] + previous.flatMap { [$0.path] + ($0.previousPaths ?? []) }
            var seen = Set([resolvedPath])
            aliases = aliases.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
            saved.removeAll { $0.id == grant.id || $0.path == resolvedPath }
            saved.insert(SavedGrant(id: grant.id, path: resolvedPath, previousPaths: aliases, isDirectory: grant.isDirectory, bookmark: bookmark, updatedAt: Date()), at: 0)
            if saved.count > Self.savedLimit { saved.removeLast(saved.count - Self.savedLimit) }
            if defersBookmarkWrite { bookmarkWritePending = true }
            else { persistSavedGrants() }
        } catch { couldNotPersistSelection = true }
    }

    private func persistSavedGrants() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: bookmarksURL, options: .atomic)
        } catch { couldNotPersistSelection = true }
    }

    private static func lexicallyCovers(root: URL, isDirectory: Bool, url: URL) -> Bool {
        let rootParts = root.standardizedFileURL.pathComponents
        let fileParts = url.standardizedFileURL.pathComponents
        return rootParts == fileParts || (isDirectory && fileParts.count > rootParts.count && fileParts.starts(with: rootParts))
    }

    /// Resolve symbolic links before checking component boundaries. A symlink
    /// inside an authorized folder must not expose a file outside that folder.
    static func covers(root: URL, isDirectory: Bool, url: URL) -> Bool {
        guard root.isFileURL, url.isFileURL else { return false }
        return lexicallyCovers(root: root.resolvingSymlinksInPath(), isDirectory: isDirectory, url: url.resolvingSymlinksInPath())
    }
}
