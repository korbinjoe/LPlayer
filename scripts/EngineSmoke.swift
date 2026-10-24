import AppKit
import OpenGL.GL3

/// A small real-window integration check for MPVEngine, independent of XCTest
/// and the application's UI. Its transient aliases exercise rapid replacement
/// without copying, modifying, or deleting the supplied media.
@main
enum EngineSmoke {
    static func main() {
        guard CommandLine.arguments.count == 4 else {
            fputs("Run this program through scripts/check-engine.sh.\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            let run = try EngineSmokeRun(
                media: URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL,
                temporaryDirectory: URL(fileURLWithPath: CommandLine.arguments[2]),
                expectsFixture: CommandLine.arguments[3] == "1"
            )
            run.start()
            withExtendedLifetime(run) { app.run() }
        } catch {
            fputs("FAIL engine initialization: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private final class EngineSmokeRun {
    private enum Phase { case initial, replacing, ending, missing, finished }
    private let engine: MPVEngine
    private let window: NSWindow
    private let media: URL
    private let replacementB: URL
    private let replacementC: URL
    private let missingMedia: URL
    private let expectsFixture: Bool
    private var phase: Phase = .initial
    private var failures: [String] = []
    private var loadedCount = 0
    private var initialDuration: Double = 0
    private var seekTarget: Double = 0
    private var sawEOF = false
    private var sawMissingError = false
    private var replacementLoaded = false
    private var finished = false

    init(media: URL, temporaryDirectory: URL, expectsFixture: Bool) throws {
        self.media = media
        self.expectsFixture = expectsFixture
        replacementB = temporaryDirectory.appendingPathComponent("quick-B").appendingPathExtension(media.pathExtension)
        replacementC = temporaryDirectory.appendingPathComponent("quick-C").appendingPathExtension(media.pathExtension)
        missingMedia = temporaryDirectory.appendingPathComponent("intentionally-missing.mkv")
        try FileManager.default.createSymbolicLink(at: replacementB, withDestinationURL: media)
        try FileManager.default.createSymbolicLink(at: replacementC, withDestinationURL: media)
        engine = try MPVEngine()
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "掌映 · 播放引擎检查"
        window.contentView = engine.videoView
        engine.onFileLoaded = { [weak self] in self?.fileLoaded() }
        engine.onEndFile = { [weak self] eof, error in self?.fileEnded(eof: eof, error: error) }
    }

    func start() {
        window.orderFrontRegardless()
        engine.load(media, start: 1)
        // A missing video output, an initialization stall, or a broken callback
        // must fail instead of leaving the window/process running indefinitely.
        after(12) { [self] in
            check(false, "playback watchdog expired")
            finish()
        }
    }

    private func fileLoaded() {
        loadedCount += 1
        let state = engine.snapshot
        switch phase {
        case .initial:
            check(state.mediaPath == media.path, "initial snapshot belongs to the requested file")
            check(state.duration.isFinite && state.duration > 4, "test video has more than 4 seconds of duration")
            guard state.duration > 4 else { finish(); return }
            initialDuration = state.duration
            check(abs(state.position - 1) < 0.25, "file-local resume starts at 1 second")
            check(!state.paused, "file opens playing")
            check(state.tracks.contains { $0.type == "video" && $0.selected }, "selected video track is reported")
            if expectsFixture {
                check(state.tracks.contains { $0.type == "audio" && $0.selected }, "selected audio track is reported")
                check(state.tracks.contains { $0.type == "sub" && $0.selected }, "default fixture selects a subtitle track")
            }
            print("INFO loaded duration=\(state.duration), tracks=\(state.tracks.count), path=\(state.mediaPath)")
            scheduleChecks()
        case .replacing:
            check(state.mediaPath == replacementC.path, "rapid B → C load delivers only C's file-loaded callback")
            check(loadedCount == 2, "superseded loads do not deliver extra file-loaded callbacks")
            check(abs(state.position - 2) < 0.25, "C uses its own resume position")
            replacementLoaded = true
            phase = .ending
            engine.setFlag("pause", true)
            after(0.35) { [self] in
                check(engine.snapshot.mediaPath == replacementC.path, "replacement snapshots remain associated with C")
                engine.command(["seek", String(max(0, engine.snapshot.duration - 0.8)), "absolute+exact"])
                engine.setFlag("pause", false)
            }
        default:
            check(false, "unexpected file-loaded callback in phase \(phase)")
        }
    }

    private func scheduleChecks() {
        after(0.8) { [self] in engine.setFlag("pause", true) }
        after(1.15) { [self] in
            check(engine.snapshot.paused, "pause is observed")
            check(engine.snapshot.position >= 1 && engine.snapshot.position < initialDuration, "playback position advances before pause")
            inspectFrame(requireVariedPixels: expectsFixture)
            window.setContentSize(NSSize(width: 800, height: 450))
            seekTarget = min(max(2, initialDuration / 3), initialDuration - 2)
            engine.command(["seek", String(seekTarget), "absolute+exact"])
        }
        after(1.8) { [self] in
            check(abs(engine.snapshot.position - seekTarget) < 0.15, "absolute exact seek reaches its target")
            check(engine.snapshot.paused, "seeking preserves pause")
            let pixels = engine.videoView.convertToBacking(engine.videoView.bounds)
            check(pixels.width >= 800 && pixels.height >= 450, "video surface follows window resize and backing scale")
            inspectFrame(requireVariedPixels: expectsFixture)
            engine.setDouble("volume", 33)
            engine.setDouble("speed", 1.5)
            engine.setDouble("sub-delay", 0.2)
            engine.setFlag("sub-visibility", false)
        }
        after(2.25) { [self] in
            let state = engine.snapshot
            check(abs(state.volume - 33) < 0.01, "volume update is observed")
            check(abs(state.speed - 1.5) < 0.01, "speed update is observed")
            check(abs(state.subtitleDelay - 0.2) < 0.01, "subtitle delay update is observed")
            check(!state.subtitlesVisible, "subtitle visibility update is observed")
            check(!sawEOF, "pause and seek did not synthesize a natural EOF")
            phase = .replacing
            // These two requests occur in the same main-thread turn. Old B
            // callbacks and observations must also be filtered by generation.
            engine.load(replacementB, start: 0.5)
            engine.load(replacementC, start: 2)
        }
        after(5.2) { [self] in
            check(replacementLoaded, "rapid replacement completed")
            check(sawEOF, "seeking near the end produced a natural EOF")
            phase = .missing
            engine.load(missingMedia)
        }
        after(7) { [self] in
            check(sawMissingError, "missing file produces an error callback with its own snapshot path")
            finish()
        }
    }

    private func fileEnded(eof: Bool, error: String?) {
        if eof {
            check(phase == .ending, "only C's natural end advances playback")
            check(engine.snapshot.mediaPath == replacementC.path, "EOF callback and snapshot refer to the same file")
            check(error == nil, "natural EOF has no error")
            sawEOF = true
        } else if let error {
            check(phase == .missing, "only the intentionally missing file reports an error")
            check(engine.snapshot.mediaPath == missingMedia.path, "loading error retains the failed media path")
            sawMissingError = true
            print("INFO expected missing-file error: \(error)")
        }
    }

    private func inspectFrame(requireVariedPixels: Bool) {
        guard let view = engine.videoView as? NSOpenGLView, let context = view.openGLContext,
              let cgl = context.cglContextObj else {
            check(false, "OpenGL video surface exists")
            return
        }
        context.makeCurrentContext()
        CGLLockContext(cgl)
        defer { CGLUnlockContext(cgl); NSOpenGLContext.clearCurrentContext() }
        let pixels = view.convertToBacking(view.bounds)
        let width = max(1, Int(pixels.width.rounded()))
        let height = max(1, Int(pixels.height.rounded()))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        glReadBuffer(GLenum(GL_FRONT))
        glReadPixels(0, 0, Int32(width), Int32(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &data)
        check(glGetError() == GLenum(GL_NO_ERROR), "front-buffer read has no OpenGL error")
        var colors = Set<UInt32>()
        for index in stride(from: 0, to: data.count - 4, by: 400) {
            let red = UInt32(data[index]) << 16
            let green = UInt32(data[index + 1]) << 8
            let blue = UInt32(data[index + 2])
            colors.insert(red | green | blue)
        }
        print("INFO rendered surface=\(width)×\(height), sampled colors=\(colors.count)")
        // A custom file can legitimately contain a black/static frame. The
        // known demo fixture has varied pixels, which verifies actual output.
        if requireVariedPixels { check(colors.count > 16, "known fixture produces a nonblank video frame") }
    }

    private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { print("PASS \(message)") }
        else { failures.append(message); print("FAIL \(message)") }
    }

    private func after(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.finished else { return }
            action()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        phase = .finished
        engine.shutdown()
        engine.shutdown()
        window.orderOut(nil)
        print("PASS repeated shutdown completes")
        print(failures.isEmpty ? "PASS engine integration check" : "FAIL engine integration check: \(failures.count) failed assertion(s)")
        // NSApplication.stop does not wake an otherwise idle event loop in an
        // accessory test process. Exit only after synchronous engine teardown.
        exit(failures.isEmpty ? 0 : 1)
    }
}
