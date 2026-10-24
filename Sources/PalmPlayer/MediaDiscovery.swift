import Foundation

/// File enumeration stays off the UI thread. Each independent channel keeps
/// one active operation and only its newest pending request, so quick opens
/// cannot fill a worker queue with searches for videos already left behind.
final class MediaDiscovery {
    private let queues = LatestDiscovery<(urls: [URL], index: Int)>(label: "app.lplayer.queue-discovery")
    private let subtitles = LatestDiscovery<[URL]>(label: "app.lplayer.subtitle-discovery")

    func discoverQueue(from urls: [URL], access: FileAccessStore.ReadSnapshot,
                       completion: @escaping ((urls: [URL], index: Int)) -> Void) {
        precondition(Thread.isMainThread)
        queues.submit(operation: { token in
            LibraryStore.initialQueue(from: urls,
                canRead: { !token.isCancelled && access.canRead($0) },
                allowSiblingAccess: { !token.isCancelled && access.hasDirectoryAccess(to: $0) })
        }, completion: completion)
    }

    func discoverSubtitles(for video: URL, access: FileAccessStore.ReadSnapshot,
                           completion: @escaping ([URL]) -> Void) {
        precondition(Thread.isMainThread)
        subtitles.submit(operation: { token in
            LibraryStore.matchingSubtitleURLs(for: video,
                canRead: { !token.isCancelled && access.canRead($0) },
                allowDirectory: { !token.isCancelled && access.hasDirectoryAccess(to: $0) })
        }, completion: completion)
    }

    func cancelQueue() { precondition(Thread.isMainThread); queues.cancel() }
    func cancelSubtitles() { precondition(Thread.isMainThread); subtitles.cancel() }
    func cancelAll() { cancelQueue(); cancelSubtitles() }
}

private final class DiscoveryCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Scheduling state belongs to the main thread; only the cancellation token is
/// shared with the worker. Authorized scopes are immutable request snapshots.
private final class LatestDiscovery<Output> {
    private struct Request {
        let token: DiscoveryCancellation
        let operation: (DiscoveryCancellation) -> Output
        let completion: (Output) -> Void
    }
    private let worker: DispatchQueue
    private var current: DiscoveryCancellation?
    private var pending: Request?
    private var running = false

    init(label: String) { worker = DispatchQueue(label: label, qos: .userInitiated) }
    deinit { current?.cancel(); pending?.token.cancel() }

    func submit(operation: @escaping (DiscoveryCancellation) -> Output,
                completion: @escaping (Output) -> Void) {
        current?.cancel()
        let token = DiscoveryCancellation()
        current = token
        pending = Request(token: token, operation: operation, completion: completion)
        startNext()
    }

    func cancel() {
        current?.cancel()
        current = nil
        pending = nil
    }

    private func startNext() {
        guard !running, let request = pending else { return }
        pending = nil
        running = true
        worker.async { [weak self] in
            let result = request.operation(request.token)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.running = false
                if self.current === request.token, !request.token.isCancelled {
                    request.completion(result)
                }
                self.startNext()
            }
        }
    }
}
