import Foundation

/// Send the first jump immediately, then sample a held key at a bounded rate.
/// Unlike a trailing debounce, continued input cannot postpone every update.
final class SeekScheduler {
    private let interval: TimeInterval
    private let onSeek: (Double) -> Void
    private var lastSubmission = -Double.infinity
    private var pending: DispatchWorkItem?
    private var pendingTarget: Double?
    private var revision: UInt64 = 0
    private(set) var hasPending = false

    init(interval: TimeInterval = 0.1, onSeek: @escaping (Double) -> Void) {
        self.interval = max(0.01, interval)
        self.onSeek = onSeek
    }

    func request(_ target: Double) {
        precondition(Thread.isMainThread)
        guard target.isFinite else { return }
        pendingTarget = target
        let now = ProcessInfo.processInfo.systemUptime
        let remaining = max(0, interval - (now - lastSubmission))
        if remaining == 0 {
            pending?.cancel()
            revision &+= 1
            submit(target)
        } else if pending == nil {
            // One timer samples the newest absolute target. Cancelling and
            // re-enqueuing a timer for every repeated key builds cancelled
            // work on the main queue without improving the visible cadence.
            hasPending = true
            revision &+= 1
            let currentRevision = revision
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.revision == currentRevision,
                      let target = self.pendingTarget else { return }
                self.submit(target)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
        }
    }

    func cancel() {
        precondition(Thread.isMainThread)
        revision &+= 1
        pending?.cancel(); pending = nil
        pendingTarget = nil
        hasPending = false
        lastSubmission = -Double.infinity
    }

    private func submit(_ target: Double) {
        pending = nil
        pendingTarget = nil
        hasPending = false
        lastSubmission = ProcessInfo.processInfo.systemUptime
        onSeek(target)
    }

    deinit { pending?.cancel() }
}
