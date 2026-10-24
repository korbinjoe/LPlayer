import AppKit
import CMpv
import Darwin

/// A private, silent decoder for timeline previews. It never uses or seeks the
/// playback engine. All public calls and completions belong to the main thread;
/// loading, seeking and copying pixels run on one utility queue.
final class ThumbnailGenerator {
    struct Thumbnail {
        let image: NSImage
        /// The one-second bucket represented by this preview.
        let time: Double
    }

    private struct CacheEntry {
        let thumbnail: Thumbnail
        let cost: Int
    }

    private struct Request {
        let source: URL
        let bucket: Int
        let token: UInt64
    }

    private let queue = DispatchQueue(label: "app.lplayer.thumbnail-decoder", qos: .utility)
    private let worker = ThumbnailDecoder()
    private let gate = ThumbnailRequestGate()
    private var pending: DispatchWorkItem?
    private var latestRequest: Request?
    private var latestCompletion: ((Thumbnail?) -> Void)?
    private var stopped = false
    private var currentURL: URL?
    private var cache: [Int: CacheEntry] = [:]
    private var cacheOrder: [Int] = []
    private var cacheCost = 0
    private let cacheLimit = 64 * 1024 * 1024

    /// Superseded and cancelled requests do not complete. A current request
    /// completes with nil when the source cannot produce a video frame.
    func request(url: URL, time: Double, completion: @escaping (Thumbnail?) -> Void) {
        precondition(Thread.isMainThread)
        guard !stopped, url.isFileURL, time.isFinite,
              max(0, time) < Double(Int.max) else {
            cancelPendingRequest()
            let token = gate.advance()
            DispatchQueue.main.async { [gate] in
                if gate.isCurrent(token) { completion(nil) }
            }
            return
        }
        let bucket = Int(floor(max(0, time)))
        let source = url.standardizedFileURL
        if currentURL != source {
            clearCache()
            currentURL = source
        }
        // Updating the hover point within one bucket must not interrupt the
        // same frame's preroll. Only its newest recipient needs the result.
        if let latestRequest, latestRequest.source == source,
           latestRequest.bucket == bucket, gate.isCurrent(latestRequest.token) {
            latestCompletion = completion
            return
        }
        let token = gate.advance(source: source)
        latestRequest = Request(source: source, bucket: bucket, token: token)
        latestCompletion = completion
        if let entry = cache[bucket] {
            pending?.cancel()
            pending = nil
            touch(bucket)
            DispatchQueue.main.async { [weak self] in
                self?.complete(entry.thumbnail, token: token)
            }
            return
        }
        // Keep the first deadline while replacing its target. Continuous
        // pointer motion can request a newer frame every ~80 ms instead of
        // postponing all decoding until the mouse finally stops moving.
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, let request = self.latestRequest,
                  self.gate.isCurrent(request.token) else { return }
            self.pending = nil
            let worker = self.worker, gate = self.gate
            self.queue.async { [weak self] in
                let frame = autoreleasepool {
                    worker.frame(url: request.source, time: Double(request.bucket), token: request.token, gate: gate)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped, gate.isCurrent(request.token),
                          self.currentURL == request.source else { return }
                    let thumbnail = frame.map { Thumbnail(image: NSImage(cgImage: $0, size: .zero), time: Double(request.bucket)) }
                    if let frame, let thumbnail {
                        self.insert(thumbnail, bucket: request.bucket, cost: frame.bytesPerRow * frame.height)
                    }
                    self.complete(thumbnail, token: request.token)
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80), execute: work)
    }

    private func complete(_ thumbnail: Thumbnail?, token: UInt64) {
        guard !stopped, gate.isCurrent(token), latestRequest?.token == token else { return }
        let completion = latestCompletion
        latestRequest = nil
        latestCompletion = nil
        completion?(thumbnail)
    }

    private func cancelPendingRequest() {
        pending?.cancel()
        pending = nil
        latestRequest = nil
        latestCompletion = nil
    }

    func cancel() {
        precondition(Thread.isMainThread)
        cancelPendingRequest()
        let token = gate.advance()
        // A paused decoder can retain full-resolution codec reference buffers.
        // Release those after leaving the timeline; the small LRU stays useful
        // when the user returns. A new request invalidates this delayed unload.
        queue.asyncAfter(deadline: .now() + .seconds(2)) { [worker, gate] in
            if gate.isCurrent(token) { worker.unload() }
        }
    }

    /// Give interactive playback priority over thumbnail preroll. Invalidating
    /// a callback alone does not stop mpv's internal software decoder.
    func suspend() {
        precondition(Thread.isMainThread)
        cancel()
        queue.async { [worker] in worker.unload() }
    }

    /// A playlist metadata refresh detected a replacement at this same path.
    /// Other sources retain their cached frames and current decode work.
    func invalidate(url: URL) {
        precondition(Thread.isMainThread)
        if currentURL == url.standardizedFileURL { reset() }
    }

    /// Release the previous file and every cached image when playback changes.
    func reset() {
        precondition(Thread.isMainThread)
        cancel()
        clearCache()
        currentURL = nil
        queue.async { [worker] in worker.unload() }
    }

    func shutdown() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        stopped = true
        cancel()
        clearCache()
        currentURL = nil
        queue.async { [worker] in worker.shutdown() }
    }

    deinit {
        pending?.cancel()
        _ = gate.advance()
        queue.async { [worker] in worker.shutdown() }
    }

    private func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
        cacheCost = 0
    }

    private func touch(_ bucket: Int) {
        guard cacheOrder.last != bucket else { return }
        cacheOrder.removeAll { $0 == bucket }
        cacheOrder.append(bucket)
    }

    private func insert(_ thumbnail: Thumbnail, bucket: Int, cost: Int) {
        guard cost > 0, cost <= cacheLimit else { return }
        if let previous = cache.removeValue(forKey: bucket) { cacheCost -= previous.cost }
        cache[bucket] = CacheEntry(thumbnail: thumbnail, cost: cost)
        cacheCost += cost
        touch(bucket)
        while cacheCost > cacheLimit, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) { cacheCost -= removed.cost }
        }
    }
}

/// Invalidating a request must interrupt an event wait immediately, without
/// waiting behind that same work on the decoder queue.
private final class ThumbnailRequestGate {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var source: URL?

    func advance(source: URL? = nil) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        self.source = source
        return generation
    }

    func isSameSource(_ source: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.source == source
    }

    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }
}

/// This object is confined to ThumbnailGenerator.queue. vo=null still retains
/// its current decoded frame; screenshot-raw's software path returns that frame
/// directly in memory, so there is no hidden window or thumbnail file.
private final class ThumbnailDecoder {
    private var handle: OpaquePointer?
    private var loadedURL: URL?

    func frame(url: URL, time: Double, token: UInt64, gate: ThumbnailRequestGate) -> CGImage? {
        guard gate.isCurrent(token), FileManager.default.isReadableFile(atPath: url.path),
              let core = core() else { return nil }
        drain(core)
        let isLoad = loadedURL != url
        let command: [String]
        if isLoad {
            loadedURL = nil
            command = ["loadfile", url.path, "replace", "-1", "start=\(time)"]
        } else {
            command = ["seek", "\(time)", "absolute+exact"]
        }
        guard run(command, core: core) >= 0 else { return nil }
        // A paused exact seek still decodes one complete frame and emits
        // playback-restart. Never sample the old frame while a seek is pending.
        guard waitForFrame(core, isLoad: isLoad, source: url, token: token, gate: gate) else {
            // A newer position can interrupt this seek without reopening the
            // same source and recreating its demuxer/codec on the next pass.
            if isLoad || gate.isCurrent(token) || !gate.isSameSource(url) { loadedURL = nil }
            return nil
        }
        loadedURL = url
        guard gate.isCurrent(token) else { return nil }
        var result = mpv_node()
        guard run(["screenshot-raw", "video", "rgba"], core: core, result: &result) >= 0 else { return nil }
        defer { mpv_free_node_contents(&result) }
        guard gate.isCurrent(token), let image = copyImage(result) else { return nil }
        // Software screenshots preserve rotation metadata rather than applying
        // the VO's final rotation. Honour it for phone/portrait videos too.
        var rotation: Int64 = 0
        mpv_get_property(core, "video-out-params/rotate", MPV_FORMAT_INT64, &rotation)
        return rotate(image, degrees: Int(rotation))
    }

    func unload() {
        if let handle { _ = run(["stop"], core: handle) }
        loadedURL = nil
    }

    func shutdown() {
        if let handle {
            self.handle = nil
            mpv_terminate_destroy(handle)
        }
        loadedURL = nil
    }

    private func core() -> OpaquePointer? {
        if let handle { return handle }
        guard let core = mpv_create() else { return nil }
        // The main playback engine also sets this before initializing libmpv.
        setlocale(LC_NUMERIC, "C")
        let options: [(String, String)] = [
            ("config", "no"), ("terminal", "no"), ("load-scripts", "no"),
            ("input-default-bindings", "no"), ("input-vo-keyboard", "no"),
            ("osc", "no"), ("ytdl", "no"), ("vo", "null"),
            ("audio", "no"), ("sub", "no"), ("sub-auto", "no"),
            ("audio-file-auto", "no"), ("cover-art-auto", "no"), ("access-references", "no"),
            ("pause", "yes"), ("idle", "yes"), ("keep-open", "yes"),
            ("hwdec", "no"), ("vd-lavc-threads", "2"),
            ("cache", "no"), ("demuxer-readahead-secs", "0"),
            ("demuxer-max-bytes", "8MiB"), ("demuxer-max-back-bytes", "0"),
            ("vf", "scale=w=640:h=360:force_original_aspect_ratio=decrease:force_divisible_by=2")
        ]
        for (key, value) in options {
            let result = mpv_set_option_string(core, key, value)
            if result == MPV_ERROR_OPTION_NOT_FOUND.rawValue,
               ["load-scripts", "osc", "ytdl"].contains(key) { continue }
            guard result >= 0 else {
                mpv_terminate_destroy(core)
                return nil
            }
        }
        guard mpv_initialize(core) >= 0 else { mpv_terminate_destroy(core); return nil }
        handle = core
        return core
    }

    private func drain(_ core: OpaquePointer) {
        while let event = mpv_wait_event(core, 0), event.pointee.event_id != MPV_EVENT_NONE {}
    }

    private func waitForFrame(_ core: OpaquePointer, isLoad: Bool, source: URL, token: UInt64, gate: ThumbnailRequestGate) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        var sawStart = !isLoad
        var sawLoaded = false
        var sawSeek = false
        // Finish a source's first preroll if only its hover position changed.
        // Reopening on every mouse event otherwise repeatedly discards codec
        // setup and can starve the very first preview. Exit/cancel/media change
        // still interrupt immediately through the source-aware request gate.
        while (gate.isCurrent(token) || (isLoad && gate.isSameSource(source))),
              DispatchTime.now().uptimeNanoseconds < deadline {
            guard let event = mpv_wait_event(core, 0.025) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_START_FILE where isLoad: sawStart = true
            case MPV_EVENT_FILE_LOADED where sawStart: sawLoaded = true
            case MPV_EVENT_SEEK where sawStart: sawSeek = true
            case MPV_EVENT_PLAYBACK_RESTART where sawStart && (sawSeek || (isLoad && sawLoaded)):
                // A superseded seek may leave a late restart event. It cannot
                // satisfy this request while a newer seek is still pending.
                var seeking: Int32 = 1
                if mpv_get_property(core, "seeking", MPV_FORMAT_FLAG, &seeking) >= 0, seeking == 0 { return true }
            // loadfile replace ends the previous file before START_FILE.
            case MPV_EVENT_END_FILE where sawStart: return false
            case MPV_EVENT_SHUTDOWN: return false
            default: break
            }
        }
        return false
    }

    @discardableResult
    private func run(_ arguments: [String], core: OpaquePointer, result: UnsafeMutablePointer<mpv_node>? = nil) -> Int32 {
        let allocated = arguments.map { strdup($0) }
        defer { allocated.forEach { free($0) } }
        var argv = allocated.map { $0.map { UnsafePointer<CChar>($0) } }
        argv.append(nil)
        return argv.withUnsafeMutableBufferPointer {
            if let result { return mpv_command_ret(core, $0.baseAddress, result) }
            return mpv_command(core, $0.baseAddress)
        }
    }

    private func copyImage(_ node: mpv_node) -> CGImage? {
        guard let width = intField("w", node), let height = intField("h", node),
              let stride = intField("stride", node), width > 0, height > 0,
              width <= 2048, height <= 2048, stride >= width * 4,
              stride <= 2048 * 4, let dataNode = field("data", node),
              dataNode.format == MPV_FORMAT_BYTE_ARRAY, let bytes = dataNode.u.ba?.pointee,
              let pointer = bytes.data, bytes.size >= stride * height else { return nil }
        let copy = Data(bytes: pointer, count: stride * height)
        guard let provider = CGDataProvider(data: copy as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func field(_ key: String, _ node: mpv_node) -> mpv_node? {
        guard node.format == MPV_FORMAT_NODE_MAP, let map = node.u.list?.pointee,
              let keys = map.keys, let values = map.values else { return nil }
        for index in 0..<Int(map.num) {
            if let name = keys[index], String(cString: name) == key { return values[index] }
        }
        return nil
    }

    private func intField(_ key: String, _ node: mpv_node) -> Int? {
        guard let item = field(key, node), item.format == MPV_FORMAT_INT64,
              item.u.int64 >= 0, item.u.int64 <= Int64(Int.max) else { return nil }
        return Int(item.u.int64)
    }

    private func rotate(_ image: CGImage, degrees: Int) -> CGImage? {
        let angle = ((degrees % 360) + 360) % 360
        if angle == 0, image.width <= 640, image.height <= 360 { return image }
        let swapsAxes = angle == 90 || angle == 270
        let sourceWidth = swapsAxes ? image.height : image.width
        let sourceHeight = swapsAxes ? image.width : image.height
        let scale = min(1, min(640.0 / Double(sourceWidth), 360.0 / Double(sourceHeight)))
        let width = max(1, Int(floor(Double(sourceWidth) * scale)))
        let height = max(1, Int(floor(Double(sourceHeight) * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.scaleBy(x: scale, y: scale)
        context.rotate(by: -CGFloat(angle) * .pi / 180)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }
}
