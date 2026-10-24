import AppKit

/// One silent moving preview for the keyboard-selected playlist card. The
/// owner supplies an authorized local URL and hosts the returned view. Nothing
/// here changes the main player's media, playback position, audio or history.
/// All methods and callbacks run on the main thread.
final class PlaylistMotionPreview {
    private final class MetadataGate {
        private let lock = NSLock()
        private var generation: UInt64 = 0
        func set(_ generation: UInt64) { lock.lock(); self.generation = generation; lock.unlock() }
        func isCurrent(_ generation: UInt64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return self.generation == generation
        }
    }

    var onViewChange: ((NSView?, URL?) -> Void)?
    var onDurationChange: ((URL, Double) -> Void)?
    private(set) var engine: MPVEngine?

    private var desiredURL: URL?
    private var loadedURL: URL?
    private var pending: DispatchWorkItem?
    private let metadataQueue = DispatchQueue(label: "app.lplayer.motion-preview-metadata", qos: .utility)
    private let metadataGate = MetadataGate()
    private var generation: UInt64 = 0
    private var enabled = false
    private var suspended = false
    private var stopped = false

    func request(url: URL?) {
        precondition(Thread.isMainThread)
        guard !stopped, desiredURL != url else { return }
        desiredURL = url
        cancelPending()
        hideView()
        // Stop decode/render work immediately while rapid keyboard presses
        // settle. The same core is reused if another card is selected shortly.
        engine?.setFlag("pause", true)
        guard url != nil else {
            releaseEngine()
            return
        }
        scheduleDesiredPreview()
    }

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        guard !stopped, self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled { scheduleDesiredPreview() } else { stopPreview() }
    }

    func setSuspended(_ suspended: Bool) {
        precondition(Thread.isMainThread)
        guard !stopped, self.suspended != suspended else { return }
        self.suspended = suspended
        if suspended { stopPreview() } else { scheduleDesiredPreview() }
    }

    func shutdown() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        stopped = true
        enabled = false
        desiredURL = nil
        stopPreview()
        onViewChange = nil
        onDurationChange = nil
    }

    private func scheduleDesiredPreview() {
        guard !stopped, enabled, !suspended, let url = desiredURL else { return }
        cancelPending()
        let token = generation
        let request = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, self.enabled, !self.suspended,
                  self.generation == token, self.desiredURL == url else { return }
            self.pending = nil
            // External volumes may block file metadata. Keep that wait away
            // from keyboard handling and scrolling on the main thread.
            let gate = self.metadataGate
            self.metadataQueue.async {
                guard gate.isCurrent(token) else { return }
                let readable = url.isFileURL && FileManager.default.isReadableFile(atPath: url.path)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped, self.enabled, !self.suspended,
                          self.generation == token, self.desiredURL == url else { return }
                    if readable { self.load(url: url, token: token) }
                    else { self.releaseEngine() }
                }
            }
        }
        pending = request
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(220), execute: request)
    }

    private func load(url: URL, token: UInt64) {
        guard url.isFileURL else { return }
        if engine == nil {
            do {
                engine = try MPVEngine(mode: .preview)
            } catch {
                // Failed previews retain their static poster. A new selection
                // or explicit visibility change can try again; no retry loop.
                return
            }
        }
        guard let engine else { return }
        loadedURL = url
        engine.onFileLoaded = { [weak self, weak engine] in
            guard let self, let engine, self.engine === engine,
                  !self.stopped, self.enabled, !self.suspended,
                  self.generation == token, self.desiredURL == url,
                  self.loadedURL == url,
                  engine.snapshot.mediaPath == url.path else { return }
            self.onDurationChange?(url, engine.snapshot.duration)
            self.onViewChange?(engine.videoView, url)
        }
        engine.onEndFile = { [weak self, weak engine] _, _ in
            guard let self, let engine, self.engine === engine,
                  self.generation == token, self.desiredURL == url else { return }
            // loop-file keeps normal EOF inside libmpv. A terminal decoder or
            // loading error removes the motion layer and leaves the poster.
            self.hideView()
            self.releaseEngine()
        }
        engine.load(url)
    }

    private func cancelPending() {
        generation &+= 1
        metadataGate.set(generation)
        pending?.cancel()
        pending = nil
    }

    private func hideView() {
        engine?.videoView.removeFromSuperview()
        onViewChange?(nil, nil)
    }

    private func releaseEngine() {
        let previous = engine
        engine = nil
        loadedURL = nil
        previous?.shutdown()
    }

    private func stopPreview() {
        cancelPending()
        hideView()
        releaseEngine()
    }

    deinit {
        pending?.cancel()
        // MPVEngine also owns a safe off-main fallback, but playlist owners
        // normally call shutdown before the host window is released.
        if Thread.isMainThread { engine?.shutdown() }
    }
}
