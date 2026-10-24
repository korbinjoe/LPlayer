import AppKit
import Foundation

/// Uses an independent accessory render window and synthetic fixture only.
/// The shell runner adds measurement hooks to a disposable copy of MPVEngine.
@main
enum SeekSmoke {
    static func main() {
        guard CommandLine.arguments.count == 5 else { exit(2) }
        NSApplication.shared.setActivationPolicy(.accessory)
        do {
            let run = try SeekSmokeRun(media: CommandLine.arguments[1], output: CommandLine.arguments[2], label: CommandLine.arguments[3], temporary: CommandLine.arguments[4])
            run.start()
            withExtendedLifetime(run) { NSApplication.shared.run() }
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}

private final class SeekSmokeRun {
    private let engine: MPVEngine
    private let window: NSWindow
    private let media: String
    private let replacement: String
    private let output: String
    private let label: String
    private let origin = ProcessInfo.processInfo.systemUptime
    private var events: [[String: Any]] = []
    private var requests: [[String: Any]] = []
    private var checks: [[String: Any]] = []
    private var environment: [String: String] = [:]
    private var failed = false
    private var finished = false
    private var loaded = 0
    private var initialReady = false
    private var observations: [[String: Any]] = []
    private var scheduledSeek: DispatchWorkItem?
    private var activeTarget: Double?
    private var pendingTarget: Double?

    init(media: String, output: String, label: String, temporary: String) throws {
        self.media = media
        self.output = output
        self.label = label
        replacement = temporary + "/replacement.mp4"
        try FileManager.default.createSymbolicLink(atPath: replacement, withDestinationPath: media)
        engine = try MPVEngine()
        window = NSWindow(contentRect: NSRect(x: 24, y: 24, width: 640, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "LPlayer seek regression (synthetic media)"
        window.level = .normal
        window.contentView = engine.videoView
        engine.benchmarkOnEvent = { [weak self] name, timestamp, position in
            guard let self else { return }
            events.append(["name": name, "t": timestamp - origin, "position": position])
            if label.contains("gate"), name == "playback-restart", let activeTarget,
               abs(position - activeTarget) < 0.2 {
                self.activeTarget = nil
                if let pendingTarget {
                    self.pendingTarget = nil
                    execute(pendingTarget)
                }
            }
        }
        engine.benchmarkOnFrame = { [weak self] timestamp in
            guard let self else { return }
            events.append(["name": "rendered-frame-swap", "t": timestamp - origin])
        }
        engine.onUpdate = { [weak self] state in
            guard let self else { return }
            var value: [String: Any] = ["t": now, "position": state.position, "paused": state.paused, "path": state.mediaPath]
            #if LPLAYER_PRODUCTION_SEEK
            value["seeking"] = state.seeking
            #endif
            observations.append(value)
        }
        engine.onFileLoaded = { [weak self] in self?.fileLoaded() }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime - origin }

    func start() {
        // Render normally behind other windows; never activate or capture user UI.
        window.orderBack(nil)
        engine.load(URL(fileURLWithPath: media), start: 2)
        after(22) { [self] in check(false, "watchdog"); finish() }
    }

    private func fileLoaded() {
        loaded += 1
        if loaded == 1 {
            engine.setFlag("pause", true)
            engine.benchmarkReadProperties { [weak self] in self?.environment = $0 }
            after(0.7) { [self] in
                guard !initialReady else { return }
                initialReady = true
                singles()
            }
        }
    }

    private func singles() {
        let targets: [Double] = [7.13, 14.37, 21.73, 28.93, 36.27, 43.61, 50.79, 11.47]
        for (index, target) in targets.enumerated() {
            after(Double(index) * 0.65) { [self] in request(target, kind: "paused-single") }
            after(Double(index) * 0.65 + 0.5) { [self] in
                check(abs(engine.snapshot.position - target) < 0.1, "paused single \(index + 1) exact target", expected: target, actual: engine.snapshot.position)
                check(engine.snapshot.paused, "paused single \(index + 1) preserves pause")
            }
        }
        after(Double(targets.count) * 0.65 + 0.1) { [self] in
            rawExact(5.13)
            after(0.6) { [self] in burst(paused: true) }
        }
    }

    private func burst(paused: Bool) {
        let base = paused ? 5.13 : 3.13
        let kind = paused ? "paused-burst" : "playing-burst"
        if !paused { engine.setFlag("pause", false) }
        for index in 0..<8 {
            after(Double(index) * 0.1) { [self] in request(base + Double(index + 1) * 5, kind: kind) }
        }
        after(1.45) { [self] in
            let expected = base + 40
            let allowance = paused ? 0.1 : 1.1
            check(abs(engine.snapshot.position - expected) < allowance, "\(kind) final target reaches latest request", expected: expected, actual: engine.snapshot.position)
            check(engine.snapshot.paused == paused, "\(kind) preserves playback state")
            #if LPLAYER_PRODUCTION_SEEK
            check(!engine.snapshot.seeking, "\(kind) finishes seeking")
            #endif
            if paused {
                rawExact(3.13)
                after(0.6) { [self] in burst(paused: false) }
            } else {
                engine.setFlag("pause", true)
                after(0.3) { [self] in replaceDuringSeek() }
            }
        }
    }

    private func replaceDuringSeek() {
        #if LPLAYER_PRODUCTION_SEEK
        engine.setFlag("pause", false)
        request(47.91, kind: "superseded-file")
        request(52.53, kind: "superseded-file-pending")
        #else
        request(47.91, kind: "superseded-file")
        #endif
        scheduledSeek?.cancel()
        activeTarget = nil; pendingTarget = nil
        engine.load(URL(fileURLWithPath: replacement), start: 2.27)
        after(0.8) { [self] in
            check(engine.snapshot.mediaPath == replacement, "replacement path remains current")
            check(engine.snapshot.position >= 2.2 && engine.snapshot.position < 3.5, "replacement ignores previous file's seek", expected: 2.27, actual: engine.snapshot.position)
            #if LPLAYER_PRODUCTION_SEEK
            check(!engine.snapshot.seeking, "replacement has no stale seeking state")
            #endif
            finish()
        }
    }

    private func request(_ target: Double, kind: String) {
        requests.append(["id": requests.count + 1, "kind": kind, "target": target, "t": now])
        seek(target, precise: kind == "paused-single")
    }

    private func seek(_ target: Double, precise: Bool) {
        #if LPLAYER_PRODUCTION_SEEK
        engine.seek(to: target)
        #else
        // Baseline reproduces App's old absolute exact seek plus 35 ms debounce.
        // The optional gate label is an isolated experiment, not product code.
        scheduledSeek?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if label.contains("gate"), activeTarget != nil { pendingTarget = target }
            else { execute(target) }
        }
        scheduledSeek = work
        let delay = label.contains("immediate") ? 0.0 : 0.035
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        #endif
    }

    private func execute(_ target: Double) {
        if label.contains("gate") { activeTarget = target }
        engine.command(["seek", String(target), "absolute+exact"])
    }

    private func rawExact(_ target: Double) {
        #if LPLAYER_PRODUCTION_SEEK
        engine.seek(to: target)
        #else
        engine.command(["seek", String(target), "absolute+exact"])
        #endif
    }

    private func after(_ delay: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !finished else { return }; work()
        }
    }

    private func check(_ pass: Bool, _ message: String, expected: Double? = nil, actual: Double? = nil) {
        failed = failed || !pass
        var value: [String: Any] = ["passed": pass, "message": message, "t": now]
        if let expected { value["expected"] = expected }
        if let actual { value["actual"] = actual }
        checks.append(value)
        print("\(pass ? "PASS" : "FAIL") \(message)\(actual.map { " actual=\($0)" } ?? "")")
    }

    private func finish() {
        guard !finished else { return }; finished = true
        var measured: [[String: Any]] = []
        for (index, request) in requests.enumerated() {
            let issued = request["t"] as! Double, target = request["target"] as! Double
            let deadline = index + 1 < requests.count ? requests[index + 1]["t"] as! Double : now
            var result = request
            let seek = events.first(where: { ($0["name"] as? String) == "seeking" && ($0["t"] as! Double) >= issued && ($0["t"] as! Double) < deadline && abs(($0["position"] as? Double ?? -100) - target) < 0.15 })
            if let seek,
               let restart = events.first(where: { ($0["name"] as? String) == "playback-restart" && ($0["t"] as! Double) >= (seek["t"] as! Double) && abs(($0["position"] as? Double ?? -100) - target) < 0.15 }) {
                let restartTime = restart["t"] as! Double
                result["seekEventMs"] = ((seek["t"] as! Double) - issued) * 1000
                result["restartMs"] = (restartTime - issued) * 1000
                result["decodeRestartMs"] = (restartTime - (seek["t"] as! Double)) * 1000
                result["restartPosition"] = restart["position"]
                // Paused case has no unrelated ongoing frames. The renderer's
                // first post-request update/swap is actual target presentation.
                if let frame = events.first(where: { ($0["name"] as? String) == "rendered-frame-swap" && ($0["t"] as! Double) >= (seek["t"] as! Double) && ($0["t"] as! Double) <= restartTime + 0.1 }) {
                    result["firstSwapAfterRequestMs"] = ((frame["t"] as! Double) - issued) * 1000
                }
            }
            measured.append(result)
        }
        for row in measured where row["kind"] as? String == "paused-single" {
            check(row["restartMs"] != nil, "single target has a paired decoder restart", expected: row["target"] as? Double)
        }
        for kind in ["paused-burst", "playing-burst"] {
            let final = measured.last { $0["kind"] as? String == kind }
            check(final?["restartMs"] != nil, "\(kind) latest target has a paired decoder restart")
        }
        let document: [String: Any] = ["label": label, "fixture": media, "environment": environment,
            "measurements": measured, "events": events, "observations": observations, "checks": checks,
            "allPassed": !failed, "note": "Synthetic 1080p30 H264 long-GOP fixture only. Accessory window, actual MPVEngine and render pipeline. First swap is target presentation only for paused single seeks; playing swaps are not attributed to target frames."]
        do {
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output))
        } catch { print("FAIL JSON output \(error)"); failed = true }
        print("INFO environment \(environment)")
        print("INFO report \(output)")
        engine.shutdown(); window.orderOut(nil)
        exit(failed ? 1 : 0)
    }
}
