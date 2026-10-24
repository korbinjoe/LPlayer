import AppKit
import CMpv
import Darwin
import OpenGL.GL3

struct MediaTrack: Equatable {
    let id: Int
    let type: String
    let title: String
    let language: String
    let selected: Bool
}

struct EngineSnapshot: Equatable {
    var position: Double = 0
    var duration: Double = 0
    var paused: Bool = true
    var seeking: Bool = false
    var volume: Double = 70
    var speed: Double = 1
    var subtitleDelay: Double = 0
    var subtitlesVisible: Bool = true
    var mediaTitle: String = ""
    var mediaPath: String = ""
    var tracks: [MediaTrack] = []
    var videoDisplayAspect: Double?
}

enum PlaybackFailureReason {
    case engineMessage(String)
    case missingFileIdentifier

    var localizedDescription: String {
        switch self {
        case .engineMessage(let message): return message
        case .missingFileIdentifier:
            return L10n.text("The playback engine did not return a file identifier. Use a version of libmpv that supports loadfile return values.", "播放引擎未返回文件标识。请使用支持 loadfile 返回值的 libmpv。")
        }
    }
}

private enum PlaybackEngineError: LocalizedError {
    case unavailable
    case initialization(String)
    case graphics(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.text("Could not create the video playback engine.", "无法创建视频播放引擎。")
        case .initialization(let reason): return L10n.format("Could not initialize the playback engine: %@", "播放引擎初始化失败：%@", reason)
        case .graphics(let reason): return L10n.format("Could not initialize the video display: %@", "视频画面初始化失败：%@", reason)
        }
    }
}

/// The C callbacks only enqueue work. Their relays outlive the corresponding
/// libmpv handles, so an in-flight callback cannot dereference a released owner.
private final class EngineWakeupRelay {
    weak var engine: MPVEngine?
    private let lock = NSLock()
    private var scheduled = false
    private var requested = false
    init(_ engine: MPVEngine) { self.engine = engine }

    func request() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        requested = true
        guard !scheduled else { return false }
        scheduled = true
        return true
    }

    func beginDrain() {
        lock.lock(); requested = false; lock.unlock()
    }

    func finishDrain() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if requested { return true }
        scheduled = false
        return false
    }
}

private final class RenderWakeupRelay {
    weak var view: MPVVideoView?
    init(_ view: MPVVideoView) { self.view = view }

    /// Let AppKit merge dirty regions. Holding a notification until a draw
    /// adds state across occlusion/seek without a measured playback benefit.
    func requestDisplay() {
        DispatchQueue.main.async { [weak view] in
            guard let view, !view.stopped else { return }
            view.needsDisplay = true
        }
    }
}

private struct EngineEnding {
    let eof: Bool
    let error: String?
    let reason: PlaybackFailureReason?
}

private struct EnginePublication {
    var snapshot: EngineSnapshot
    let generation: UInt64
    let fileLoaded: Bool
    var ending: EngineEnding? = nil
}

/// Position notifications may arrive faster than AppKit can paint. Replace
/// only consecutive progress updates; preserve pause, seek, file and control
/// transitions in their original order instead of hiding those transitions.
private final class EnginePublicationMailbox {
    private let lock = NSLock()
    private var pending: [EnginePublication] = []
    private var scheduled = false

    func submit(_ value: EnginePublication) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let previous = pending.last,
           !previous.fileLoaded, !value.fileLoaded,
           previous.ending == nil, value.ending == nil,
           previous.generation == value.generation {
            var previousState = previous.snapshot
            previousState.position = value.snapshot.position
            if previousState == value.snapshot {
                pending[pending.count - 1] = value
            } else {
                pending.append(value)
            }
        } else {
            pending.append(value)
        }
        guard !scheduled else { return false }
        scheduled = true
        return true
    }

    func takePending() -> [EnginePublication] {
        lock.lock()
        defer { lock.unlock() }
        let values = pending
        pending.removeAll(keepingCapacity: true)
        scheduled = false
        return values
    }

    func discardPending() {
        lock.lock(); pending.removeAll(keepingCapacity: false); lock.unlock()
    }
}

private struct VideoViewportTarget {
    let zoom: Double
    let panX: Double
    let panY: Double
    let generation: UInt64
}

/// Main-thread geometry is always current, even if decoding temporarily holds
/// up the API queue. Keep one newest absolute crop instead of replaying every
/// intermediate trackpad event after the user's fingers have stopped.
private final class VideoViewportMailbox {
    private let lock = NSLock()
    private var latest: VideoViewportTarget?
    private var workerScheduled = false

    func submit(_ target: VideoViewportTarget) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        latest = target
        guard !workerScheduled else { return false }
        workerScheduled = true
        return true
    }

    func takeLatest() -> VideoViewportTarget? {
        lock.lock()
        defer { lock.unlock() }
        let target = latest
        latest = nil
        return target
    }

    /// Keep ownership of the worker while another target is pending. A new
    /// worker is queued at the tail so file loads, seeks and events get a turn.
    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if latest != nil { return true }
        workerScheduled = false
        return false
    }

    func discardPending() {
        lock.lock()
        latest = nil
        lock.unlock()
    }
}

/// Playback commands and event consumption run on one private queue. Rendering
/// runs on AppKit's main thread, which never waits for a normal mpv API call
/// while its renderer is active. This separation is required by libmpv's API.
final class MPVEngine {
    enum Mode {
        case playback
        case preview
    }

    let videoView: NSView
    private(set) var snapshot = EngineSnapshot()
    private(set) var failureReason: PlaybackFailureReason?
    var onUpdate: ((EngineSnapshot) -> Void)?
    var onFileLoaded: (() -> Void)?
    var onEndFile: ((Bool, String?) -> Void)?
    var onVideoZoomChange: ((Double) -> Void)?
    var onSeekStateChange: ((Bool) -> Void)?
    var videoZoomScale: Double { videoViewport.scale }

    private var videoViewport = VideoViewport()
    private var isZoomGestureActive = false
    private var videoZoomGestureAnchor: NSPoint?
    private let videoViewportMailbox = VideoViewportMailbox()
    // API queue only. A pan must not rewrite an unchanged zoom (or other axis).
    private var writtenVideoViewport: [String: Double] = [:]

    private let mode: Mode
    private var handle: OpaquePointer?
    private let apiQueue = DispatchQueue(label: "app.palmplayer.mpv.events", qos: .userInitiated)
    private var workingSnapshot = EngineSnapshot()
    private let publicationMailbox = EnginePublicationMailbox()
    private var wakeupRelay: EngineWakeupRelay?
    private var isShutdown = false
    // IDs identify a specific load, including two rapid loads of the same URL.
    // A FILE_LOADED event has no data, so associate it with its preceding
    // START_FILE instead of trusting a query that may already describe a newer
    // playlist entry by the time an old event is consumed.
    private var requestedEntryID: Int64?
    private var startedEntryID: Int64?
    private var requestedPath = ""
    private var loadGeneration: UInt64 = 0 // Main thread: changes as soon as load is requested.
    private var workerGeneration: UInt64 = 0 // API queue: the request that produced an update.
    // Confined to apiQueue. A playing seek finishes only after libmpv reports
    // SEEK followed by PLAYBACK_RESTART; returning from mpv_command is too soon.
    private struct SeekRequest {
        let position: Double
        let generation: UInt64
    }
    private struct ActiveSeek {
        let id: UInt64
        let generation: UInt64
        var sawSeekEvent = false
    }
    private var canSeek = false
    private var activeSeek: ActiveSeek?
    private var pendingSeek: SeekRequest?
    private var seekWatchdog: DispatchWorkItem?
    private var seekSequence: UInt64 = 0

    init(mode: Mode = .playback) throws {
        precondition(Thread.isMainThread, "Create the playback engine on the main thread")
        self.mode = mode
        guard let core = mpv_create() else { throw PlaybackEngineError.unavailable }
        // Foundation does not change LC_NUMERIC, but explicitly satisfy the mpv
        // embedding contract even when the app was launched from a custom shell.
        setlocale(LC_NUMERIC, "C")
        do {
            let preferredLanguage = (L10n.mediaPreferredLanguages.first ?? "en").replacingOccurrences(of: "_", with: "-")
            let subtitleLanguages: String
            if preferredLanguage.lowercased().hasPrefix("zh") {
                subtitleLanguages = "zh,chi,zho,zh-CN,en"
            } else {
                var languages = [preferredLanguage]
                if let base = preferredLanguage.split(separator: "-").first.map(String.init), !languages.contains(base) {
                    languages.append(base)
                }
                if !languages.contains("en") { languages.append("en") }
                subtitleLanguages = languages.joined(separator: ",")
            }
            var options: [(String, String)] = [
                ("config", "no"), ("terminal", "no"), ("load-scripts", "no"), ("vo", "libmpv"),
                ("input-default-bindings", "no"), ("input-vo-keyboard", "no"),
                ("osc", "no"), ("ytdl", "no"), ("idle", "yes"),
                ("keep-open", "no"), ("hwdec", "auto-safe"),
                // FileAccessStore authorizes every external file. The app adds
                // matching subtitles explicitly after directory authorization.
                ("volume", "70"), ("sub-auto", "no"), ("slang", subtitleLanguages),
                ("audio-file-auto", "no"), ("cover-art-auto", "no"), ("access-references", "no"),
                ("sub-font", "PingFang SC"), ("sub-font-size", "32"),
                ("sub-border-size", "1"), ("sub-shadow-offset", "0.5"), ("sub-margin-y", "105"),
                ("osd-level", "0"), ("video-timing-offset", "0")
            ]
            if mode == .preview {
                // A playlist preview has its own core. Disable audio before
                // initialization so it cannot briefly open an output device,
                // even while the first file is loading or being replaced.
                options += [
                    ("audio", "no"), ("aid", "no"), ("ao", "null"), ("mute", "yes"),
                    ("sub", "no"), ("loop-file", "inf"),
                    ("cache", "no"), ("demuxer-readahead-secs", "0"),
                    ("demuxer-max-bytes", "8MiB"), ("demuxer-max-back-bytes", "0"),
                    ("vd-lavc-threads", "2")
                ]
            }
            for (name, value) in options {
                let result = mpv_set_option_string(core, name, value)
                // Script options do not exist when the controlled libmpv was
                // built without Lua/JavaScript. In that build there is no
                // script runtime to disable; other option errors still fail.
                if result == MPV_ERROR_OPTION_NOT_FOUND.rawValue,
                   ["load-scripts", "osc", "ytdl"].contains(name) { continue }
                guard result >= 0 else {
                    throw PlaybackEngineError.initialization("\(name): \(Self.message(result))")
                }
            }
            let result = mpv_initialize(core)
            guard result >= 0 else { throw PlaybackEngineError.initialization(Self.message(result)) }
            guard let view = try MPVVideoView(handle: core) else {
                throw PlaybackEngineError.graphics(L10n.text("Could not create the video display surface.", "无法创建视频显示表面。"))
            }
            videoView = view
            handle = core
        } catch {
            mpv_terminate_destroy(core)
            throw error
        }

        let observed: [(String, mpv_format)] = [
            ("time-pos", MPV_FORMAT_DOUBLE), ("duration", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG), ("seeking", MPV_FORMAT_FLAG), ("volume", MPV_FORMAT_DOUBLE),
            ("speed", MPV_FORMAT_DOUBLE), ("sub-delay", MPV_FORMAT_DOUBLE),
            ("sub-visibility", MPV_FORMAT_FLAG), ("media-title", MPV_FORMAT_STRING),
            ("track-list", MPV_FORMAT_NODE), ("video-out-params", MPV_FORMAT_NODE)
        ]
        for (index, property) in observed.enumerated() {
            mpv_observe_property(core, UInt64(index + 1), property.0, property.1)
        }
        let relay = EngineWakeupRelay(self)
        wakeupRelay = relay
        mpv_set_wakeup_callback(core, { pointer in
            guard let pointer else { return }
            Unmanaged<EngineWakeupRelay>.fromOpaque(pointer).takeUnretainedValue().engine?.enqueueEvents()
        }, Unmanaged.passUnretained(relay).toOpaque())
        (videoView as? MPVVideoView)?.onViewportResize = { [weak self] size in
            guard let self else { return }
            let before = self.videoViewport
            self.videoViewport.resize(to: size)
            if self.videoViewport != before { self.applyVideoViewport() }
        }
        videoViewport.resize(to: videoView.bounds.size)
        enqueueEvents()
    }

    func load(_ url: URL, start: Double = 0) {
        precondition(Thread.isMainThread, "Load media on the main thread")
        loadGeneration &+= 1
        failureReason = nil
        let generation = loadGeneration
        isZoomGestureActive = false
        videoZoomGestureAnchor = nil
        videoViewport.setDisplayAspect(nil)
        videoViewportMailbox.discardPending()
        onVideoZoomChange?(1)
        let location = url.isFileURL ? url.path : url.absoluteString
        let position = start.isFinite ? max(0, start) : 0
        apiQueue.async { [weak self] in
            guard let self, let core = self.handle else { return }
            self.clearSeekGate(resetSeeking: true)
            self.canSeek = false
            self.workerGeneration = generation
            self.workingSnapshot.position = position
            self.workingSnapshot.duration = 0
            self.workingSnapshot.mediaTitle = url.deletingPathExtension().lastPathComponent
            self.workingSnapshot.mediaPath = ""
            self.workingSnapshot.tracks = []
            self.workingSnapshot.videoDisplayAspect = nil
            self.requestedPath = location
            self.requestedEntryID = nil
            // These properties persist across mpv loadfile. Every new video
            // starts fitted, even if the previous one was zoomed or cropped.
            self.writeVideoViewport(zoom: 0, panX: 0, panY: 0, core: core)
            self.publish()
            // Since mpv 0.38 the insertion index precedes the file-local options.
            // Passing start with loadfile makes resuming atomic with this file.
            var loadResult = mpv_node()
            let result = self.runCommand(["loadfile", location, "replace", "-1", "start=\(position)"], core: core, result: &loadResult)
            if result < 0 {
                self.workingSnapshot.mediaPath = location
                self.deliverEnd(eof: false, error: Self.message(result))
            } else {
                defer { mpv_free_node_contents(&loadResult) }
                // Use loadfile's own entry ID, rather than querying mutable
                // playlist state in a second API call.
                self.requestedEntryID = Self.integerField("playlist_entry_id", in: loadResult)
                if self.requestedEntryID == nil {
                    self.workingSnapshot.mediaPath = location
                    self.deliverEnd(eof: false, error: PlaybackFailureReason.missingFileIdentifier.localizedDescription, reason: .missingFileIdentifier)
                    return
                }
                var playing: Int32 = 0
                mpv_set_property(core, "pause", MPV_FORMAT_FLAG, &playing)
            }
        }
    }

    /// Call with points in videoView's local AppKit coordinates (bottom-left).
    /// The recognizer/event supplies an incremental magnification, not its
    /// cumulative value since the start of the gesture.
    func beginVideoZoom(at point: NSPoint) {
        precondition(Thread.isMainThread)
        guard !isShutdown, videoViewport.canZoom else { return }
        isZoomGestureActive = true
        videoZoomGestureAnchor = point.x.isFinite && point.y.isFinite ? point
            : NSPoint(x: videoView.bounds.midX, y: videoView.bounds.midY)
    }

    func updateVideoZoom(magnification: Double, at point: NSPoint) {
        precondition(Thread.isMainThread)
        guard magnification.isFinite, !isShutdown else { return }
        if !isZoomGestureActive { beginVideoZoom(at: point) }
        guard isZoomGestureActive else { return }
        // Bounds avoid overflow from synthetic/malformed events. Ordinary
        // AppKit pinch deltas are small; clamping the result remains 1x...5x.
        let factor = min(5, max(0.01, 1 + magnification))
        setVideoZoomScale(videoZoomScale * factor, at: videoZoomGestureAnchor ?? point)
    }

    func endVideoZoom() {
        precondition(Thread.isMainThread)
        isZoomGestureActive = false
        videoZoomGestureAnchor = nil
    }

    func resetVideoZoom() {
        precondition(Thread.isMainThread)
        guard !isShutdown else { return }
        isZoomGestureActive = false
        videoZoomGestureAnchor = nil
        videoViewport.reset()
        applyVideoViewport()
    }

    /// Also used by smart magnify and the visible zoom controls. Omitting an
    /// anchor zooms around the center of the currently visible picture.
    func setVideoZoomScale(_ scale: Double, at point: NSPoint? = nil) {
        precondition(Thread.isMainThread)
        guard !isShutdown, videoViewport.canZoom else { return }
        let before = videoViewport
        let topLeftPoint = point.map { CGPoint(x: $0.x - videoView.bounds.minX,
                                              y: videoView.bounds.maxY - $0.y) }
        videoViewport.setScale(scale, at: topLeftPoint)
        if videoViewport != before { applyVideoViewport() }
    }

    /// AppKit displacement is in view points, with positive Y pointing up.
    /// Keep the existing crop scale and let the viewport constrain each axis.
    func panVideo(by delta: NSPoint) {
        precondition(Thread.isMainThread)
        guard !isShutdown else { return }
        let before = videoViewport
        videoViewport.pan(by: CGPoint(x: delta.x, y: -delta.y))
        if videoViewport != before { applyVideoViewport(notifyZoomChange: false) }
    }

    private func applyVideoViewport(notifyZoomChange: Bool = true) {
        precondition(Thread.isMainThread)
        if notifyZoomChange { onVideoZoomChange?(videoViewport.scale) }
        let target = VideoViewportTarget(zoom: videoViewport.mpvZoom,
                                         panX: videoViewport.panX, panY: videoViewport.panY,
                                         generation: loadGeneration)
        guard videoViewportMailbox.submit(target) else { return }
        enqueueVideoViewport()
    }

    private func enqueueVideoViewport() {
        apiQueue.async { [weak self] in
            self?.drainVideoViewport()
        }
    }

    private func drainVideoViewport() {
        if let target = videoViewportMailbox.takeLatest(),
           let core = handle, workerGeneration == target.generation {
            writeVideoViewport(zoom: target.zoom, panX: target.panX, panY: target.panY, core: core)
        }
        if videoViewportMailbox.finish() { enqueueVideoViewport() }
    }

    private func writeVideoViewport(zoom: Double, panX: Double, panY: Double, core: OpaquePointer) {
        for (name, value) in [("video-zoom", zoom), ("video-pan-x", panX), ("video-pan-y", panY)] {
            guard writtenVideoViewport[name] != value else { continue }
            var number = value
            if mpv_set_property(core, name, MPV_FORMAT_DOUBLE, &number) >= 0 {
                writtenVideoViewport[name] = value
            }
        }
    }

    private func updateVideoGeometry(from update: EngineSnapshot) {
        precondition(Thread.isMainThread)
        let before = videoViewport
        videoViewport.setDisplayAspect(update.videoDisplayAspect)
        if videoViewport != before { applyVideoViewport() }
    }

    func command(_ args: [String]) {
        guard !args.isEmpty else { return }
        apiQueue.async { [weak self] in
            guard let self, let core = self.handle else { return }
            _ = self.runCommand(args, core: core)
        }
    }

    /// Keeps exact target accuracy while allowing a playing decoder to show its
    /// new frame before issuing the newest accumulated target. Paused seeking
    /// remains direct, since libmpv already coalesces it efficiently.
    func seek(to position: Double) {
        precondition(Thread.isMainThread, "Seek media on the main thread")
        guard position.isFinite, !isShutdown else { return }
        let request = SeekRequest(position: max(0, position), generation: loadGeneration)
        apiQueue.async { [weak self] in
            guard let self, let core = self.handle else { return }
            // Consume old restart/pause events before attaching a new seek to
            // them. No synchronous work is performed on AppKit's main thread.
            self.drainEvents()
            guard self.canSeek, request.generation == self.workerGeneration else { return }
            if self.isPaused(core) {
                self.clearSeekGate(resetSeeking: false)
                self.issueSeek(request, gated: false, core: core)
            } else if self.activeSeek != nil {
                self.pendingSeek = request
            } else {
                self.issueSeek(request, gated: true, core: core)
            }
        }
    }

    private func isPaused(_ core: OpaquePointer) -> Bool {
        var paused: Int32 = workingSnapshot.paused ? 1 : 0
        _ = mpv_get_property(core, "pause", MPV_FORMAT_FLAG, &paused)
        return paused != 0
    }

    private func clearSeekGate(resetSeeking: Bool) {
        seekWatchdog?.cancel()
        seekWatchdog = nil
        activeSeek = nil
        pendingSeek = nil
        if resetSeeking { workingSnapshot.seeking = false }
    }

    private func issueSeek(_ request: SeekRequest, gated: Bool, core: OpaquePointer) {
        guard canSeek, request.generation == workerGeneration else { return }
        seekSequence &+= 1
        let sequence = seekSequence
        if gated { activeSeek = ActiveSeek(id: sequence, generation: request.generation) }
        let result = runCommand(["seek", String(request.position), "absolute+exact"], core: core)
        guard result >= 0 else {
            if gated { clearSeekGate(resetSeeking: true) }
            publish()
            return
        }
        workingSnapshot.seeking = true
        publish()
        guard gated else { return }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let core = self.handle, self.canSeek,
                  self.workerGeneration == request.generation,
                  self.activeSeek?.id == sequence else { return }
            let latest = self.pendingSeek
            self.clearSeekGate(resetSeeking: false)
            // A lost completion must never block later input forever. Retain
            // only the latest target, bound to this particular loaded file.
            if let latest, latest.generation == self.workerGeneration {
                self.issueSeek(latest, gated: !self.isPaused(core), core: core)
            } else {
                var seeking: Int32 = 0
                if mpv_get_property(core, "seeking", MPV_FORMAT_FLAG, &seeking) >= 0 {
                    self.workingSnapshot.seeking = seeking != 0
                }
                self.publish()
            }
        }
        seekWatchdog = timeout
        apiQueue.asyncAfter(deadline: .now() + 1.25, execute: timeout)
    }

    private func completePlayingSeek(_ core: OpaquePointer) {
        guard let activeSeek, activeSeek.generation == workerGeneration,
              activeSeek.sawSeekEvent else { return }
        let latest = pendingSeek
        clearSeekGate(resetSeeking: false)
        if let latest, latest.generation == workerGeneration {
            issueSeek(latest, gated: !isPaused(core), core: core)
        }
    }

    private func flushSeekOnPause(_ core: OpaquePointer) {
        let latest = pendingSeek
        clearSeekGate(resetSeeking: false)
        // Pausing must not discard the user's final queued destination.
        if let latest, latest.generation == workerGeneration {
            issueSeek(latest, gated: false, core: core)
        }
    }

    func setFlag(_ name: String, _ value: Bool) {
        apiQueue.async { [weak self] in
            guard let self, let core = self.handle else { return }
            var flag: Int32 = value ? 1 : 0
            let result = mpv_set_property(core, name, MPV_FORMAT_FLAG, &flag)
            if result >= 0, name == "pause", value { self.flushSeekOnPause(core) }
        }
    }

    /// A control acknowledgment follows delivery of its confirmed snapshot.
    /// Relative inputs can keep an optimistic target until this completion,
    /// rather than accidentally treating an older equal snapshot as its ack.
    func setDouble(_ name: String, _ value: Double, completion: ((Bool) -> Void)? = nil) {
        let generation: UInt64?
        if completion != nil {
            precondition(Thread.isMainThread, "Acknowledge numeric controls on the main thread")
            generation = loadGeneration
        } else {
            generation = nil
        }
        guard value.isFinite else {
            if let completion { DispatchQueue.main.async { completion(false) } }
            return
        }
        apiQueue.async { [weak self] in
            guard let self, let core = self.handle else {
                if let completion { DispatchQueue.main.async { completion(false) } }
                return
            }
            var number = value
            let result = mpv_set_property(core, name, MPV_FORMAT_DOUBLE, &number)
            guard let completion else { return }
            self.drainEvents()
            var confirmed = result >= 0
            let field: WritableKeyPath<EngineSnapshot, Double>?
            switch name {
            case "volume": field = \.volume
            case "speed": field = \.speed
            case "sub-delay": field = \.subtitleDelay
            default: field = nil
            }
            if confirmed, let field {
                // Property notifications may be coalesced or arrive later.
                // Read the setter's actual, possibly clamped value now.
                var actual = 0.0
                confirmed = mpv_get_property(core, name, MPV_FORMAT_DOUBLE, &actual) >= 0 && actual.isFinite
                if confirmed { self.workingSnapshot[keyPath: field] = actual }
            }
            self.publish()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isShutdown, self.loadGeneration == generation else {
                    completion(false)
                    return
                }
                completion(confirmed)
            }
        }
    }

    func setString(_ name: String, _ value: String) {
        apiQueue.async { [weak self] in
            guard let core = self?.handle else { return }
            mpv_set_property_string(core, name, value)
        }
    }

    /// Call on the main thread, before releasing the host window. The renderer
    /// must be freed before destroying the core. Repeated calls are harmless.
    func shutdown() {
        precondition(Thread.isMainThread, "Shut down the playback engine on the main thread")
        guard !isShutdown else { return }
        isShutdown = true
        videoViewportMailbox.discardPending()
        publicationMailbox.discardPending()
        onUpdate = nil
        onFileLoaded = nil
        onEndFile = nil
        onVideoZoomChange = nil
        onSeekStateChange = nil
        if mode == .preview, let view = videoView as? MPVVideoView {
            // Closing a card must stop producing frames immediately. The
            // render context can take a decoder timeout (~200 ms) to free,
            // so retire its GL resources off the input/render thread.
            apiQueue.async { [weak self] in
                guard let self, let core = self.handle else { return }
                self.clearSeekGate(resetSeeking: true)
                self.canSeek = false
                var paused: Int32 = 1
                mpv_set_property(core, "pause", MPV_FORMAT_FLAG, &paused)
            }
            view.shutdownRendererAsynchronously { [self] in
                // Keep event consumption alive while the renderer retires.
                // The core must outlive that renderer, including callbacks.
                apiQueue.async { [self] in
                    destroyCore()
                    // AppKit views and their last owning engine are released
                    // on main, even when this was their final strong owner.
                    DispatchQueue.main.async { withExtendedLifetime(self) {} }
                }
            }
        } else {
            (videoView as? MPVVideoView)?.shutdownRenderer()
            apiQueue.sync { destroyCore() }
        }
    }

    private func destroyCore() {
        clearSeekGate(resetSeeking: true)
        canSeek = false
        guard let core = handle else { return }
        mpv_set_wakeup_callback(core, nil, nil)
        mpv_terminate_destroy(core)
        handle = nil
        // The callback relay remains alive until the last C callback stops.
        wakeupRelay = nil
    }

    deinit {
        guard !isShutdown else {
            if !Thread.isMainThread {
                let view = videoView
                DispatchQueue.main.async { withExtendedLifetime(view) {} }
            }
            return
        }
        if Thread.isMainThread, mode == .playback {
            shutdown()
        } else {
            // A callback can briefly retain the final engine reference. If it
            // releases on the event queue, move GL teardown to the main thread
            // while retaining the relay until the core has actually stopped.
            let view = videoView as? MPVVideoView
            let core = handle
            let queue = apiQueue
            let relay = wakeupRelay
            DispatchQueue.main.async {
                let finish = {
                    queue.async {
                        if let core {
                            mpv_set_wakeup_callback(core, nil, nil)
                            mpv_terminate_destroy(core)
                        }
                        withExtendedLifetime(relay) {}
                        DispatchQueue.main.async { withExtendedLifetime(view) {} }
                    }
                }
                if let view { view.shutdownRendererAsynchronously(completion: finish) }
                else { finish() }
            }
        }
    }

    fileprivate func enqueueEvents() {
        guard wakeupRelay?.request() == true else { return }
        enqueueEventDrain()
    }

    private func enqueueEventDrain() {
        apiQueue.async { [weak self] in
            guard let self else { return }
            self.wakeupRelay?.beginDrain()
            self.drainEvents()
            // Schedule at the tail so a busy stream of property changes does
            // not starve a user command already waiting on this queue.
            if self.wakeupRelay?.finishDrain() == true { self.enqueueEventDrain() }
        }
    }

    private func drainEvents() {
        guard let core = handle else { return }
        var changed = false
        while let pointer = mpv_wait_event(core, 0) {
            let event = pointer.pointee
            if event.event_id == MPV_EVENT_NONE { break }
            switch event.event_id {
            case MPV_EVENT_START_FILE:
                guard let data = event.data else { continue }
                startedEntryID = data.assumingMemoryBound(to: mpv_event_start_file.self).pointee.playlist_entry_id
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { continue }
                updateProperty(data.assumingMemoryBound(to: mpv_event_property.self).pointee)
                changed = true
            case MPV_EVENT_SEEK:
                guard canSeek, startedEntryID == requestedEntryID else { continue }
                workingSnapshot.seeking = true
                if activeSeek?.generation == workerGeneration { activeSeek?.sawSeekEvent = true }
                changed = true
            case MPV_EVENT_PLAYBACK_RESTART:
                guard canSeek, startedEntryID == requestedEntryID else { continue }
                workingSnapshot.seeking = false
                completePlayingSeek(core)
                changed = true
            case MPV_EVENT_FILE_LOADED:
                guard let startedEntryID, startedEntryID == requestedEntryID else { continue }
                guard let path = mpv_get_property_string(core, "path") else { continue }
                let mediaPath = String(cString: path)
                mpv_free(path)
                // mpv removes repeated path separators. Compare normalized
                // local paths without resolving symbolic links, then retain
                // the caller's URL spelling for its snapshot identity checks.
                let samePath: Bool
                if requestedPath.hasPrefix("/") {
                    samePath = URL(fileURLWithPath: mediaPath).standardizedFileURL.path == URL(fileURLWithPath: requestedPath).standardizedFileURL.path
                } else {
                    samePath = mediaPath == requestedPath
                }
                guard samePath else { continue }
                workingSnapshot.mediaPath = requestedPath
                canSeek = true
                refresh(core)
                publish(fileLoaded: true)
                changed = false
            case MPV_EVENT_END_FILE:
                guard let data = event.data else { continue }
                let ending = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                guard ending.playlist_entry_id == requestedEntryID else { continue }
                clearSeekGate(resetSeeking: true)
                canSeek = false
                // STOP, QUIT, REDIRECT and file replacement never advance a
                // folder playlist. Only a natural EOF may do that.
                let eof = ending.reason == MPV_END_FILE_REASON_EOF
                let error = ending.reason == MPV_END_FILE_REASON_ERROR ? Self.message(ending.error) : nil
                // Errors can happen before FILE_LOADED. Give that failure the
                // requested path so the caller can reject a superseded load.
                if workingSnapshot.mediaPath.isEmpty, eof || error != nil {
                    workingSnapshot.mediaPath = requestedPath
                }
                changed = false
                deliverEnd(eof: eof, error: error)
            default: break
            }
        }
        if changed { publish() }
    }

    private func updateProperty(_ property: mpv_event_property) {
        guard let name = property.name else { return }
        // Old file properties can still be queued while a replacement loads.
        // Leave their snapshot unbound until the matching FILE_LOADED refresh.
        if workingSnapshot.mediaPath.isEmpty { return }
        if String(cString: name) == "video-out-params" {
            workingSnapshot.videoDisplayAspect = property.format == MPV_FORMAT_NODE
                ? property.data.flatMap { Self.parseDisplayAspect($0.load(as: mpv_node.self)) } : nil
            return
        }
        guard let data = property.data else { return }
        switch String(cString: name) {
        case "time-pos" where property.format == MPV_FORMAT_DOUBLE:
            workingSnapshot.position = max(0, data.load(as: Double.self))
        case "duration" where property.format == MPV_FORMAT_DOUBLE:
            workingSnapshot.duration = max(0, data.load(as: Double.self))
        case "pause" where property.format == MPV_FORMAT_FLAG:
            workingSnapshot.paused = data.load(as: Int32.self) != 0
            if workingSnapshot.paused, let core = handle { flushSeekOnPause(core) }
        case "seeking" where property.format == MPV_FORMAT_FLAG:
            workingSnapshot.seeking = data.load(as: Int32.self) != 0
        case "volume" where property.format == MPV_FORMAT_DOUBLE:
            workingSnapshot.volume = data.load(as: Double.self)
        case "speed" where property.format == MPV_FORMAT_DOUBLE:
            workingSnapshot.speed = data.load(as: Double.self)
        case "sub-delay" where property.format == MPV_FORMAT_DOUBLE:
            workingSnapshot.subtitleDelay = data.load(as: Double.self)
        case "sub-visibility" where property.format == MPV_FORMAT_FLAG:
            workingSnapshot.subtitlesVisible = data.load(as: Int32.self) != 0
        case "media-title" where property.format == MPV_FORMAT_STRING:
            if let value = data.load(as: UnsafePointer<CChar>?.self) {
                workingSnapshot.mediaTitle = String(cString: value)
            }
        case "track-list" where property.format == MPV_FORMAT_NODE:
            workingSnapshot.tracks = Self.parseTracks(data.load(as: mpv_node.self))
        default: break
        }
    }

    private func refresh(_ core: OpaquePointer) {
        let numbers: [(String, WritableKeyPath<EngineSnapshot, Double>)] = [
            ("time-pos", \.position), ("duration", \.duration), ("volume", \.volume),
            ("speed", \.speed), ("sub-delay", \.subtitleDelay)
        ]
        for (name, keyPath) in numbers {
            var value: Double = 0
            if mpv_get_property(core, name, MPV_FORMAT_DOUBLE, &value) >= 0, value.isFinite {
                workingSnapshot[keyPath: keyPath] = value
            }
        }
        var paused: Int32 = 0
        if mpv_get_property(core, "pause", MPV_FORMAT_FLAG, &paused) >= 0 { workingSnapshot.paused = paused != 0 }
        var seeking: Int32 = 0
        if mpv_get_property(core, "seeking", MPV_FORMAT_FLAG, &seeking) >= 0 { workingSnapshot.seeking = seeking != 0 }
        var visible: Int32 = 0
        if mpv_get_property(core, "sub-visibility", MPV_FORMAT_FLAG, &visible) >= 0 {
            workingSnapshot.subtitlesVisible = visible != 0
        }
        if let title = mpv_get_property_string(core, "media-title") {
            workingSnapshot.mediaTitle = String(cString: title)
            mpv_free(title)
        }
        var tracks = mpv_node()
        if mpv_get_property(core, "track-list", MPV_FORMAT_NODE, &tracks) >= 0 {
            workingSnapshot.tracks = Self.parseTracks(tracks)
            mpv_free_node_contents(&tracks)
        }
        var video = mpv_node()
        if mpv_get_property(core, "video-out-params", MPV_FORMAT_NODE, &video) >= 0 {
            workingSnapshot.videoDisplayAspect = Self.parseDisplayAspect(video)
            mpv_free_node_contents(&video)
        } else {
            workingSnapshot.videoDisplayAspect = nil
        }
    }

    private func publish(fileLoaded: Bool = false) {
        var update = workingSnapshot
        update.seeking = update.seeking || activeSeek != nil || pendingSeek != nil
        enqueuePublication(EnginePublication(snapshot: update, generation: workerGeneration, fileLoaded: fileLoaded))
    }

    private func enqueuePublication(_ value: EnginePublication) {
        guard publicationMailbox.submit(value) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for value in self.publicationMailbox.takePending() {
                guard !self.isShutdown, self.loadGeneration == value.generation else { continue }
                let update = value.snapshot
                let changed = self.snapshot != update
                let seekingChanged = self.snapshot.seeking != update.seeking
                if let ending = value.ending {
                    self.failureReason = ending.reason ?? ending.error.map(PlaybackFailureReason.engineMessage)
                }
                self.snapshot = update
                if changed { self.updateVideoGeometry(from: update) }
                guard !self.isShutdown, self.loadGeneration == value.generation else { continue }
                if seekingChanged { self.onSeekStateChange?(update.seeking) }
                guard !self.isShutdown, self.loadGeneration == value.generation else { continue }
                if changed || value.ending != nil { self.onUpdate?(update) }
                guard !self.isShutdown, self.loadGeneration == value.generation else { continue }
                if value.fileLoaded { self.onFileLoaded?() }
                guard !self.isShutdown, self.loadGeneration == value.generation else { continue }
                if let ending = value.ending { self.onEndFile?(ending.eof, ending.error) }
            }
        }
    }

    private func deliverEnd(eof: Bool, error: String?, reason: PlaybackFailureReason? = nil) {
        // Terminal events share the snapshot queue. A separately dispatched
        // callback could otherwise be overtaken by a newer snapshot already
        // absorbed by an earlier pending mailbox drain.
        enqueuePublication(EnginePublication(snapshot: workingSnapshot,
                                             generation: workerGeneration,
                                             fileLoaded: false,
                                             ending: EngineEnding(eof: eof, error: error, reason: reason)))
    }

    @discardableResult
    private func runCommand(_ args: [String], core: OpaquePointer, result: UnsafeMutablePointer<mpv_node>? = nil) -> Int32 {
        let allocated = args.map { strdup($0) }
        defer { allocated.forEach { free($0) } }
        var argv = allocated.map { $0.map { UnsafePointer<CChar>($0) } }
        argv.append(nil)
        return argv.withUnsafeMutableBufferPointer { buffer in
            if let result { return mpv_command_ret(core, buffer.baseAddress, result) }
            return mpv_command(core, buffer.baseAddress)
        }
    }

    private static func integerField(_ key: String, in node: mpv_node) -> Int64? {
        guard node.format == MPV_FORMAT_NODE_MAP, let map = node.u.list?.pointee,
              let keys = map.keys, let values = map.values else { return nil }
        for index in 0..<Int(map.num) {
            if let field = keys[index], String(cString: field) == key, values[index].format == MPV_FORMAT_INT64 {
                return values[index].u.int64
            }
        }
        return nil
    }

    /// mpv reports display dimensions before the VO applies 90/270° rotation.
    /// See video/out/aspect.c: mp_get_src_dst_rects swaps src_dw and src_dh.
    private static func parseDisplayAspect(_ node: mpv_node) -> Double? {
        guard node.format == MPV_FORMAT_NODE_MAP, let map = node.u.list?.pointee,
              let keys = map.keys, let values = map.values else { return nil }
        var width: Double?, height: Double?, aspect: Double?, rotation: Int64 = 0
        for index in 0..<Int(map.num) {
            guard let key = keys[index] else { continue }
            let value = values[index]
            let number: Double?
            if value.format == MPV_FORMAT_INT64 { number = Double(value.u.int64) }
            else if value.format == MPV_FORMAT_DOUBLE { number = value.u.double_ }
            else { number = nil }
            switch String(cString: key) {
            case "dw": width = number
            case "dh": height = number
            case "aspect": aspect = number
            case "rotate" where value.format == MPV_FORMAT_INT64: rotation = value.u.int64
            default: break
            }
        }
        let ratio: Double
        if let width, let height, width > 0, height > 0 { ratio = width / height }
        else if let aspect { ratio = aspect }
        else { return nil }
        let result = rotation % 180 == 90 || rotation % 180 == -90 ? 1 / ratio : ratio
        return result.isFinite && (0.000001...1_000_000).contains(result) ? result : nil
    }

    private static func parseTracks(_ node: mpv_node) -> [MediaTrack] {
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list?.pointee,
              let values = list.values, list.num > 0 else { return [] }
        return (0..<Int(list.num)).compactMap { index in
            let item = values[index]
            guard item.format == MPV_FORMAT_NODE_MAP, let map = item.u.list?.pointee,
                  let keys = map.keys, let entries = map.values else { return nil }
            var id = 0, type = "", title = "", language = ""
            var selected = false
            for field in 0..<Int(map.num) {
                guard let keyPointer = keys[field] else { continue }
                let value = entries[field]
                switch String(cString: keyPointer) {
                case "id" where value.format == MPV_FORMAT_INT64: id = Int(value.u.int64)
                case "type" where value.format == MPV_FORMAT_STRING:
                    if let string = value.u.string { type = String(cString: string) }
                case "title" where value.format == MPV_FORMAT_STRING:
                    if let string = value.u.string { title = String(cString: string) }
                case "lang" where value.format == MPV_FORMAT_STRING:
                    if let string = value.u.string { language = String(cString: string) }
                case "selected" where value.format == MPV_FORMAT_FLAG: selected = value.u.flag != 0
                default: break
                }
            }
            guard !type.isEmpty else { return nil }
            return MediaTrack(id: id, type: type, title: title, language: language, selected: selected)
        }
    }

    private static func message(_ code: Int32) -> String {
        guard let string = mpv_error_string(code) else { return "Error \(code)" }
        return String(cString: string)
    }
}

/// A real OpenGL surface backed by mpv's render API. Retina dimensions come
/// from convertToBacking, and AppKit draws again after resize/display changes.
private final class MPVVideoView: NSOpenGLView {
    var onViewportResize: ((NSSize) -> Void)?
    private static let teardownQueue = DispatchQueue(label: "app.lplayer.preview-renderer-teardown", qos: .utility)
    private var renderer: OpaquePointer?
    private var rendererContext: NSOpenGLContext?
    private var relay: RenderWakeupRelay?
    fileprivate var stopped = false

    init?(handle: OpaquePointer) throws {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion3_2Core),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), 24,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAlphaSize), 8, 0
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attributes) else {
            throw PlaybackEngineError.graphics(L10n.text("Could not create an OpenGL 3.2 display context.", "无法创建 OpenGL 3.2 显示上下文。"))
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 540), pixelFormat: format)
        wantsBestResolutionOpenGLSurface = true
        autoresizingMask = [.width, .height]
        guard let context = openGLContext else {
            throw PlaybackEngineError.graphics(L10n.text("Could not create the video display surface.", "无法创建视频显示表面。"))
        }
        guard context.cglContextObj != nil else {
            throw PlaybackEngineError.graphics(L10n.text("Could not create the video display surface.", "无法创建视频显示表面。"))
        }
        rendererContext = context
        context.makeCurrentContext()
        var interval: GLint = 1
        context.setValues(&interval, for: .swapInterval)
        var glInit = mpv_opengl_init_params(get_proc_address: { _, name in
            guard let name else { return nil }
            // OpenGL.framework is already linked. The process symbol scope is
            // stable for the lifetime of the renderer, unlike a temporary dlopen.
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        }, get_proc_address_ctx: nil)
        let api = strdup("opengl")!
        defer { free(api) }
        let result = withUnsafeMutablePointer(to: &glInit) { initPointer in
            var parameters = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(api)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return mpv_render_context_create(&renderer, handle, &parameters)
        }
        guard result >= 0, renderer != nil else {
            throw PlaybackEngineError.graphics(String(cString: mpv_error_string(result)))
        }
        let relay = RenderWakeupRelay(self)
        self.relay = relay
        mpv_render_context_set_update_callback(renderer, { pointer in
            guard let pointer else { return }
            Unmanaged<RenderWakeupRelay>.fromOpaque(pointer).takeUnretainedValue().requestDisplay()
        }, Unmanaged.passUnretained(relay).toOpaque())
        NSOpenGLContext.clearCurrentContext()
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !stopped, let context = openGLContext else { return }
        context.makeCurrentContext()
        guard let cgl = context.cglContextObj else { return }
        CGLLockContext(cgl)
        defer {
            CGLUnlockContext(cgl)
            NSOpenGLContext.clearCurrentContext()
        }
        let pixels = convertToBacking(bounds)
        let width = max(1, Int32(pixels.width.rounded()))
        let height = max(1, Int32(pixels.height.rounded()))
        glViewport(0, 0, width, height)
        if let renderer {
            _ = mpv_render_context_update(renderer)
            var fbo = mpv_opengl_fbo(fbo: 0, w: width, h: height, internal_format: 0)
            var flip: Int32 = 1
            var blockForTime: Int32 = 0
            withUnsafeMutablePointer(to: &fbo) { fboPointer in
                withUnsafeMutablePointer(to: &flip) { flipPointer in
                    withUnsafeMutablePointer(to: &blockForTime) { blockPointer in
                        var parameters = [
                            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                            mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(blockPointer)),
                            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                        ]
                        _ = mpv_render_context_render(renderer, &parameters)
                    }
                }
            }
            context.flushBuffer()
            mpv_render_context_report_swap(renderer)
        } else {
            glClearColor(0.025, 0.025, 0.035, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            context.flushBuffer()
        }
    }

    override func update() {
        guard !stopped else { return }
        super.update()
    }

    override func reshape() {
        guard !stopped else { return }
        super.reshape()
        onViewportResize?(bounds.size)
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard !stopped else { return }
        openGLContext?.update()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !stopped else { return }
        openGLContext?.update()
        needsDisplay = true
    }

    /// Detach on main before transferring this context to the serial teardown
    /// queue. No AppKit draw or resize can touch it after the transfer.
    func shutdownRendererAsynchronously(completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard !stopped else { completion(); return }
        stopped = true
        onViewportResize = nil
        guard let renderer else { completion(); return }
        // Creation verifies this context and keeps a separate strong owner,
        // so detaching NSOpenGLView cannot invalidate the worker's context.
        guard let context = rendererContext, let cgl = context.cglContextObj else {
            preconditionFailure("A live mpv renderer must retain its OpenGL context")
        }
        let relay = self.relay
        self.renderer = nil
        rendererContext = nil
        self.relay = nil
        clearGLContext()
        Self.teardownQueue.async {
            CGLLockContext(cgl)
            context.makeCurrentContext()
            mpv_render_context_set_update_callback(renderer, nil, nil)
            mpv_render_context_free(renderer)
            NSOpenGLContext.clearCurrentContext()
            CGLUnlockContext(cgl)
            withExtendedLifetime(relay) {}
            completion()
        }
    }

    func shutdownRenderer() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        stopped = true
        onViewportResize = nil
        guard let renderer else { return }
        rendererContext?.makeCurrentContext()
        mpv_render_context_set_update_callback(renderer, nil, nil)
        mpv_render_context_free(renderer)
        self.renderer = nil
        rendererContext = nil
        relay = nil
        NSOpenGLContext.clearCurrentContext()
    }
}
