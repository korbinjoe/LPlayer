import AppKit

/// A small, in-memory cover cache for the playlist's visible rows. It owns a
/// silent decoder separate from both playback and the timeline preview decoder.
/// Public methods and callbacks run on the main thread.
final class PlaylistThumbnailStore {
    var onUpdate: ((URL, NSImage?) -> Void)?

    private struct Identity: Hashable {
        let size: Int64?
        let modificationDate: Date?
        let readable: Bool
    }

    private struct Source: Equatable {
        let requestedURL: URL
        let url: URL
        let identity: Identity
        var key: SourceKey { SourceKey(path: url.path, identity: identity) }
    }

    private struct SourceKey: Hashable {
        let path: String
        let identity: Identity
    }

    private struct CacheEntry {
        let identity: Identity
        // A nil image is a cached failure, so an unreadable file cannot cause
        // an endless retry loop every time the table updates.
        let image: NSImage?
        let cost: Int
    }

    private struct Request {
        let generation: UInt64
        let source: Source
    }

    private final class MetadataGate {
        private let lock = NSLock()
        private var generation: UInt64 = 0
        func advance() -> UInt64 {
            lock.lock(); defer { lock.unlock() }
            generation &+= 1
            return generation
        }
        func isCurrent(_ token: UInt64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return generation == token
        }
    }

    private let generator = ThumbnailGenerator()
    private let metadataQueue = DispatchQueue(label: "app.lplayer.playlist-metadata", qos: .utility)
    private let metadataGate = MetadataGate()
    private var metadataWork: DispatchWorkItem?
    private var metadataRequestURLs: [URL]?
    private var visibleURLs: [URL] = []
    private var knownSources: [URL: Source] = [:]
    private var lastMetadataRefresh: TimeInterval = 0
    private let cacheLimit = 24 * 1024 * 1024
    private let entryLimit = 128
    private var cache: [String: CacheEntry] = [:]
    private var cacheOrder: [String] = []
    private var cacheCost = 0
    private var visibleSources: [Source] = []
    private var completedVisible: Set<SourceKey> = []
    private var inFlight: Request?
    private var generation: UInt64 = 0
    private var visibilityGeneration: UInt64 = 0
    private var enabled = false
    private var suspended = false
    private var stopped = false
    private var decoderInUse = false

    func image(for url: URL) -> NSImage? {
        precondition(Thread.isMainThread)
        // Row creation and scrolling must never resolve symlinks or stat disk
        // on the main thread. Visible metadata is refreshed asynchronously.
        guard !stopped, let source = knownSources[url] ?? knownSources[url.standardizedFileURL],
              let entry = cache[source.url.path], entry.identity == source.identity else { return nil }
        touch(source.url.path)
        return entry.image
    }

    /// The caller supplies only rows intersecting the scroll viewport, in
    /// display order. There is never more than one outstanding decode request.
    func setVisibleURLs(_ urls: [URL]) {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        if urls == visibleURLs {
            refreshMetadata(force: false)
            return
        }
        var seen = Set<URL>()
        let requested = urls.prefix(entryLimit).compactMap { url -> URL? in
            guard url.isFileURL else { return nil }
            let url = url.standardizedFileURL
            return seen.insert(url).inserted ? url : nil
        }
        let changed = requested != visibleURLs
        if changed {
            visibleURLs = requested
            visibilityGeneration &+= 1
            completedVisible.removeAll()
            visibleSources = requested.compactMap { knownSources[$0] }
            if let request = inFlight, !requested.contains(request.source.requestedURL) { cancelCurrent() }
        }
        guard !requested.isEmpty else {
            cancelMetadata()
            visibleSources.removeAll()
            releaseDecoder()
            return
        }
        refreshMetadata(force: changed)
    }

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        guard !stopped, self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled { refreshMetadata(force: true) } else { cancelCurrent(); cancelMetadata() }
    }

    /// Pause background cover work while the main player seeks or changes
    /// files. Already decoded covers remain available to the table.
    func setSuspended(_ suspended: Bool) {
        precondition(Thread.isMainThread)
        guard !stopped, self.suspended != suspended else { return }
        self.suspended = suspended
        if suspended { cancelCurrent(); cancelMetadata() } else { refreshMetadata(force: true) }
    }

    func reset() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        cancelCurrent()
        cancelMetadata()
        visibleURLs.removeAll()
        knownSources.removeAll()
        visibleSources.removeAll()
        completedVisible.removeAll()
        cache.removeAll()
        cacheOrder.removeAll()
        cacheCost = 0
        generator.reset()
    }

    func shutdown() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        stopped = true
        enabled = false
        cancelCurrent()
        cancelMetadata()
        visibleURLs.removeAll()
        knownSources.removeAll()
        visibleSources.removeAll()
        completedVisible.removeAll()
        cache.removeAll()
        cacheOrder.removeAll()
        cacheCost = 0
        generator.shutdown()
        onUpdate = nil
    }

    private func source(for url: URL) -> Source? {
        guard url.isFileURL else { return nil }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: canonical.path)
        let regular = attributes?[.type] as? FileAttributeType == .typeRegular
        let identity = Identity(size: (attributes?[.size] as? NSNumber)?.int64Value,
                                modificationDate: attributes?[.modificationDate] as? Date,
                                readable: regular && FileManager.default.isReadableFile(atPath: canonical.path))
        return Source(requestedURL: url, url: canonical, identity: identity)
    }

    private func refreshMetadata(force: Bool) {
        guard enabled, !suspended, !stopped, !visibleURLs.isEmpty else { return }
        if metadataRequestURLs == visibleURLs { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastMetadataRefresh >= 1 else { return }
        cancelMetadata()
        let token = metadataGate.advance()
        let urls = visibleURLs
        metadataRequestURLs = urls
        let gate = metadataGate
        let work = DispatchWorkItem { [weak self] in
            guard let self, gate.isCurrent(token) else { return }
            self.metadataWork = nil
            self.metadataQueue.async { [weak self] in
                guard let self else { return }
                let sources = urls.compactMap { url -> Source? in
                    guard gate.isCurrent(token) else { return nil }
                    return self.source(for: url)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, gate.isCurrent(token), !self.stopped,
                          self.enabled, !self.suspended, self.visibleURLs == urls else { return }
                    self.metadataRequestURLs = nil
                    self.lastMetadataRefresh = ProcessInfo.processInfo.systemUptime
                    self.visibleSources = sources
                    // Keep only metadata covered by the bounded image cache
                    // and the visible rows, even for huge directory queues.
                    self.knownSources = self.knownSources.filter { self.cache[$0.value.url.path] != nil }
                    for source in sources {
                        self.knownSources[source.requestedURL] = source
                        if let entry = self.cache[source.url.path], entry.identity != source.identity {
                            self.remove(source.url.path)
                            if self.inFlight?.source.url == source.url { self.cancelCurrent() }
                            self.generator.invalidate(url: source.url)
                            self.onUpdate?(source.requestedURL, nil)
                            self.completedVisible = self.completedVisible.filter { $0.path != source.url.path }
                        }
                    }
                    if self.knownSources.count > self.entryLimit * 2 {
                        let visible = Set(urls)
                        let retained = self.knownSources.filter { !visible.contains($0.key) }
                            .prefix(self.entryLimit)
                        self.knownSources = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
                        for source in sources { self.knownSources[source.requestedURL] = source }
                    }
                    if let request = self.inFlight,
                       !sources.contains(where: { $0.key == request.source.key }) { self.cancelCurrent() }
                    // Covers that were already cached become available to new
                    // rows as soon as their asynchronous identity is verified.
                    for source in sources {
                        if let entry = self.cache[source.url.path], entry.identity == source.identity {
                            self.onUpdate?(source.requestedURL, entry.image)
                        }
                    }
                    self.pump()
                }
            }
        }
        metadataWork = work
        // Bounds notifications can arrive multiple times in a scroll event.
        // Collapse them before touching disk; visible cached covers stay up.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25), execute: work)
    }

    private func cancelMetadata() {
        _ = metadataGate.advance()
        metadataWork?.cancel()
        metadataWork = nil
        metadataRequestURLs = nil
    }

    private func pump() {
        guard enabled, !suspended, !stopped, inFlight == nil, metadataRequestURLs == nil else { return }
        for fresh in visibleSources {
            if let entry = cache[fresh.url.path], entry.identity == fresh.identity { continue }
            if completedVisible.contains(fresh.key) { continue }
            if !fresh.identity.readable {
                insert(image: nil, source: fresh)
                completedVisible.insert(fresh.key)
                let visibilityToken = visibilityGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.enabled, !self.suspended, !self.stopped,
                          self.visibilityGeneration == visibilityToken,
                          self.visibleSources.contains(where: { $0.key == fresh.key }) else { return }
                    self.onUpdate?(fresh.requestedURL, nil)
                }
                continue
            }
            generation &+= 1
            let request = Request(generation: generation, source: fresh)
            inFlight = request
            decoderInUse = true
            decode(request, time: 5)
            return
        }
        // mpv can retain full-resolution codec references even with a small
        // screenshot. Release them as soon as this visible batch is complete.
        releaseDecoder()
    }

    private func decode(_ request: Request, time: Double) {
        generator.request(url: request.source.url, time: time) { [weak self] thumbnail in
            guard let self, self.isCurrent(request) else { return }
            // Verify replacement/deletion off the UI thread before publishing
            // a frame; a changed file must never inherit an old cover.
            self.metadataQueue.async { [weak self] in
                guard let self else { return }
                let current = self.source(for: request.source.requestedURL)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(request) else { return }
                    guard let current, current.key == request.source.key else {
                        self.inFlight = nil
                        self.lastMetadataRefresh = 0
                        self.refreshMetadata(force: true)
                        return
                    }
                    if thumbnail == nil, time > 0 {
                        self.decode(request, time: 0)
                        return
                    }
                    self.inFlight = nil
                    self.insert(image: thumbnail?.image, source: current)
                    self.completedVisible.insert(current.key)
                    self.onUpdate?(current.requestedURL, thumbnail?.image)
                    self.pump()
                }
            }
        }
    }

    private func isCurrent(_ request: Request) -> Bool {
        !stopped && enabled && !suspended && generation == request.generation
            && inFlight?.generation == request.generation
            && visibleSources.contains(where: { $0.key == request.source.key })
    }

    private func cancelCurrent() {
        generation &+= 1
        visibilityGeneration &+= 1
        inFlight = nil
        releaseDecoder()
    }

    private func releaseDecoder() {
        guard decoderInUse else { return }
        decoderInUse = false
        generator.suspend()
    }

    private func insert(image: NSImage?, source: Source) {
        let path = source.url.path
        remove(path)
        let pixels = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let cost = pixels.map { $0.bytesPerRow * $0.height } ?? 0
        guard cost <= cacheLimit else { return }
        cache[path] = CacheEntry(identity: source.identity, image: image, cost: cost)
        cacheCost += cost
        touch(path)
        let visiblePaths = Set(visibleSources.map { $0.url.path })
        while cacheCost > cacheLimit || cache.count > entryLimit {
            guard let oldest = cacheOrder.first(where: { !visiblePaths.contains($0) }) ?? cacheOrder.first else { break }
            remove(oldest)
        }
    }

    private func touch(_ path: String) {
        guard cacheOrder.last != path else { return }
        cacheOrder.removeAll { $0 == path }
        cacheOrder.append(path)
    }

    private func remove(_ path: String) {
        if let removed = cache.removeValue(forKey: path) { cacheCost -= removed.cost }
        cacheOrder.removeAll { $0 == path }
    }
}
