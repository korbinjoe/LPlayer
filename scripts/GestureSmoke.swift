import AppKit
import OpenGL.GL3

/// Exercises native responder routing and libmpv's actual rendered crop using
/// only the repository's synthetic fixture. No playback history or user media
/// is loaded, and the accessory window stays behind normal application windows.
@main
enum GestureSmoke {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Run this program through scripts/check-gestures.sh.\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            let run = try GestureSmokeRun(media: URL(fileURLWithPath: CommandLine.arguments[1]))
            run.start()
            withExtendedLifetime(run) { app.run() }
        } catch {
            fputs("FAIL gesture initialization: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

/// AppKit exposes no public constructor for a magnify event. This event supplies
/// the same public values a trackpad event supplies, without injecting input
/// into the user's current application or claiming a physical trackpad test.
private final class FixtureGesture: NSEvent {
    private let eventKind: NSEvent.EventType
    private let eventPhase: NSEvent.Phase
    private let eventPoint: NSPoint
    private let eventDelta: CGFloat
    init(type: NSEvent.EventType = .magnify, phase: NSEvent.Phase, at point: NSPoint, delta: Double = 0) {
        eventKind = type
        eventPhase = phase
        eventPoint = point
        eventDelta = CGFloat(delta)
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var type: NSEvent.EventType { eventKind }
    override var phase: NSEvent.Phase { eventPhase }
    override var locationInWindow: NSPoint { eventPoint }
    override var magnification: CGFloat { eventDelta }
}

private struct FixtureFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func difference(from other: FixtureFrame, scale: Double = 1,
                    anchor: NSPoint = NSPoint(x: 0.5, y: 0.5)) -> Double {
        var error: Double = 0
        var count = 0
        // Viewport coordinates remain bottom-left throughout: the source is a
        // GL readback, and the gesture point is in local AppKit coordinates.
        for y in stride(from: 5, to: height - 5, by: 7) {
            for x in stride(from: 5, to: width - 5, by: 7) {
                let nx = Double(x) / Double(width)
                let ny = Double(y) / Double(height)
                let sx = Double(anchor.x) + (nx - Double(anchor.x)) / scale
                let sy = Double(anchor.y) + (ny - Double(anchor.y)) / scale
                let ox = min(other.width - 1, max(0, Int((sx * Double(other.width)).rounded())))
                let oy = min(other.height - 1, max(0, Int((sy * Double(other.height)).rounded())))
                let source = (oy * other.width + ox) * 4
                let target = (y * width + x) * 4
                for channel in 0..<3 {
                    error += abs(Double(pixels[target + channel]) - Double(other.pixels[source + channel]))
                    count += 1
                }
            }
        }
        return error / Double(max(1, count))
    }

    var sampledColorCount: Int {
        var colors = Set<UInt32>()
        for index in stride(from: 0, to: pixels.count - 4, by: 400) {
            colors.insert((UInt32(pixels[index]) << 16) | (UInt32(pixels[index + 1]) << 8) | UInt32(pixels[index + 2]))
        }
        return colors.count
    }
}

private final class GestureSmokeRun {
    private let engine: MPVEngine
    private let window: NSWindow
    private let surface = PlayerSurface(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    private let media: URL
    private let hud = RoundedView(color: Palette.panel)
    private var baseline: FixtureFrame?
    private var failures: [String] = []
    private var magnifyCallbacks = 0
    private var smartCallbacks = 0
    private var zoomNotifications = 0
    private var didLoad = false
    private var reloading = false
    private var finished = false
    private let anchor = NSPoint(x: 0.32, y: 0.42)

    init(media: URL) throws {
        self.media = media
        engine = try MPVEngine()
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "LPlayer · Synthetic gesture check"
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.contentView = surface
        engine.videoView.frame = surface.bounds
        engine.videoView.autoresizingMask = [.width, .height]
        surface.addSubview(engine.videoView)
        // Keep a visible HUD and its text over the gesture origin throughout
        // repeated pinches. Neither may become the magnify hit-test target.
        hud.frame = NSRect(x: 100, y: 100, width: 360, height: 180)
        hud.passesThroughEvents = true
        let hudLabel = label("画面缩放 200%", size: 18)
        hudLabel.frame = NSRect(x: 10, y: 10, width: 340, height: 160)
        hud.addSubview(hudLabel)
        surface.addSubview(hud)
        surface.onMagnify = { [weak self] event in
            guard let self else { return }
            self.magnifyCallbacks += 1
            let point = self.engine.videoView.convert(event.locationInWindow, from: nil)
            if event.phase.contains(.began) { self.engine.beginVideoZoom(at: point) }
            self.engine.updateVideoZoom(magnification: Double(event.magnification), at: point)
            if !event.phase.intersection([.ended, .cancelled]).isEmpty { self.engine.endVideoZoom() }
        }
        surface.onSmartMagnify = { [weak self] event in
            guard let self else { return }
            self.smartCallbacks += 1
            if self.engine.videoZoomScale > 1.01 { self.engine.resetVideoZoom() }
            else { self.engine.setVideoZoomScale(2, at: self.engine.videoView.convert(event.locationInWindow, from: nil)) }
        }
        engine.onVideoZoomChange = { [weak self] _ in self?.zoomNotifications += 1 }
        engine.onFileLoaded = { [weak self] in self?.fileLoaded() }
    }

    func start() {
        window.orderBack(nil)
        engine.setDouble("volume", 0)
        engine.setFlag("sub-visibility", false)
        engine.load(media, start: 2)
        after(15) { [self] in check(false, "gesture watchdog expired"); finish() }
    }

    private func fileLoaded() {
        engine.setFlag("pause", true)
        engine.setFlag("sub-visibility", false)
        engine.command(["seek", "2", "absolute+exact"])
        if reloading {
            after(0.4) { [self] in
                check(close(engine.videoZoomScale, 1), "loading another playback entry resets zoom")
                if let reset = readFrame(), let baseline { check(reset.difference(from: baseline) < 4, "new playback entry renders the original uncropped frame") }
                finish()
            }
            return
        }
        guard !didLoad else { check(false, "unexpected extra fixture load"); finish(); return }
        didLoad = true
        after(0.6) { [self] in
            check(engine.snapshot.paused, "fixture is paused for deterministic crop comparisons")
            baseline = readFrame()
            guard let baseline else { finish(); return }
            check(baseline.sampledColorCount > 16, "synthetic fixture renders a nonblank OpenGL frame")
            check(!hud.isHidden && hud.frame.contains(point()), "visible HUD and label cover the pinch origin")
            sendGesture(phase: .began)
            sendGesture(phase: .changed, delta: 0.5)
            // A moving cursor must not change the original gesture anchor.
            sendGesture(phase: .changed, delta: 1.0 / 3.0, normalizedLocation: NSPoint(x: 0.68, y: 0.66))
            sendGesture(phase: .ended)
            check(magnifyCallbacks == 4, "visible HUD and label let events reach video then bubble to PlayerSurface")
            check(close(engine.videoZoomScale, 2), "successive pinch deltas multiply to 2x")
            after(0.35) { [self] in checkZoomedFrame() }
        }
    }

    private func checkZoomedFrame() {
        guard let baseline, let zoomed = readFrame() else { finish(); return }
        let cropError = zoomed.difference(from: baseline, scale: 2, anchor: anchor)
        let centeredError = zoomed.difference(from: baseline, scale: 2)
        let unchangedError = zoomed.difference(from: baseline)
        print(String(format: "INFO frame MAE: anchored=%.3f centered=%.3f unchanged=%.3f", cropError, centeredError, unchangedError))
        check(unchangedError > 3, "pinch changes actual rendered pixels while paused")
        check(cropError < 8 && cropError < centeredError * 0.65, "rendered crop locks its off-center begin anchor despite changed-event movement")
        check(engine.snapshot.paused && abs(engine.snapshot.position - 2) < 0.1, "pinch preserves pause and playback position")
        window.setContentSize(NSSize(width: 800, height: 450))
        after(0.35) { [self] in
            check(close(engine.videoZoomScale, 2), "window resize preserves video zoom")
            if let resized = readFrame() {
                let error = resized.difference(from: baseline, scale: 2, anchor: anchor)
                print(String(format: "INFO resized anchored frame MAE=%.3f", error))
                check(error < 8, "resized surface keeps the same anchored crop")
            }
            sendGesture(phase: .began)
            sendGesture(phase: .changed, delta: -0.25)
            sendGesture(phase: .cancelled)
            check(close(engine.videoZoomScale, 1.5), "inward pinch reduces zoom and cancellation ends gesture")
            engine.updateVideoZoom(magnification: .nan, at: point())
            engine.updateVideoZoom(magnification: .infinity, at: point())
            check(close(engine.videoZoomScale, 1.5), "nonfinite magnification cannot corrupt zoom")
            engine.setVideoZoomScale(.nan)
            check(engine.videoZoomScale.isFinite, "nonfinite scale requests retain finite state")
            engine.setVideoZoomScale(100)
            check(close(engine.videoZoomScale, 5), "zoom is bounded at 5x")
            engine.setVideoZoomScale(-100)
            check(close(engine.videoZoomScale, 1), "zoom is bounded at the original fitted frame")
            engine.setVideoZoomScale(2, at: point())
            sendSmartGesture()
            check(smartCallbacks == 1 && close(engine.videoZoomScale, 1), "smart magnify bubbles from video and resets zoom")
            after(0.35) { [self] in
                if let reset = readFrame() { check(reset.difference(from: baseline) < 4, "reset restores the original rendered frame") }
                sendSmartGesture()
                check(smartCallbacks == 2 && close(engine.videoZoomScale, 2), "smart magnify from fitted view zooms to 2x")
                check(zoomNotifications > 4, "zoom changes publish UI notifications")
                reloading = true
                engine.load(media, start: 2)
            }
        }
    }

    private func point() -> NSPoint {
        NSPoint(x: anchor.x * engine.videoView.bounds.width, y: anchor.y * engine.videoView.bounds.height)
    }

    private func sendGesture(phase: NSEvent.Phase, delta: Double = 0, normalizedLocation: NSPoint? = nil) {
        let normalized = normalizedLocation ?? anchor
        let local = NSPoint(x: normalized.x * engine.videoView.bounds.width,
                            y: normalized.y * engine.videoView.bounds.height)
        let event = FixtureGesture(phase: phase, at: engine.videoView.convert(local, to: nil), delta: delta)
        guard let target = surface.hitTest(surface.convert(event.locationInWindow, from: nil)) else { check(false, "video hit test succeeds"); return }
        check(target === engine.videoView, "pinch targets the actual OpenGL video child")
        target.magnify(with: event)
    }

    private func sendSmartGesture() {
        let event = FixtureGesture(type: .smartMagnify, phase: [], at: engine.videoView.convert(point(), to: nil))
        surface.hitTest(surface.convert(event.locationInWindow, from: nil))?.smartMagnify(with: event)
    }

    private func readFrame() -> FixtureFrame? {
        guard let view = engine.videoView as? NSOpenGLView, let context = view.openGLContext,
              let cgl = context.cglContextObj else { check(false, "OpenGL context exists"); return nil }
        // A background window can be fully occluded. Force only our own renderer
        // to draw; never capture screen pixels or activate the user's player.
        view.draw(view.bounds)
        context.makeCurrentContext()
        CGLLockContext(cgl)
        defer { CGLUnlockContext(cgl); NSOpenGLContext.clearCurrentContext() }
        let rect = view.convertToBacking(view.bounds)
        let width = max(1, Int(rect.width.rounded()))
        let height = max(1, Int(rect.height.rounded()))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        glReadBuffer(GLenum(GL_FRONT))
        glReadPixels(0, 0, Int32(width), Int32(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &data)
        check(glGetError() == GLenum(GL_NO_ERROR), "rendered frame readback succeeds")
        return FixtureFrame(width: width, height: height, pixels: data)
    }

    private func close(_ actual: Double, _ expected: Double) -> Bool { abs(actual - expected) < 0.0001 }
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
        engine.shutdown()
        window.orderOut(nil)
        print(failures.isEmpty ? "PASS gesture integration check" : "FAIL gesture integration check: \(failures.count) failed assertion(s)")
        exit(failures.isEmpty ? 0 : 1)
    }
}
