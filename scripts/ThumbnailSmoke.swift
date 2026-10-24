import AppKit

/// Native AppKit/libmpv integration checks using only generated repository media.
/// Mouse events are passed directly to our own slider; no system input is sent.
@main
enum ThumbnailSmoke {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            fputs("Run through scripts/check-thumbnails.sh.\n", stderr)
            exit(2)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        do {
            let run = try ThumbnailSmokeRun(
                mediaDirectory: URL(fileURLWithPath: CommandLine.arguments[1]),
                output: URL(fileURLWithPath: CommandLine.arguments[2]))
            run.run()
        } catch {
            fputs("FAIL thumbnail initialization: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct FixturePixels {
    let bytes: [UInt8]
    init?(image: NSImage) {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        var data = [UInt8](repeating: 0, count: 320 * 180 * 4)
        let drawn = data.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: 320, height: 180, bitsPerComponent: 8,
                                          bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 320, height: 180))
            return true
        }
        guard drawn else { return nil }
        bytes = data
    }
    func difference(from other: Self) -> Double {
        var error: Double = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 { error += abs(Double(bytes[offset + channel]) - Double(other.bytes[offset + channel])) }
        }
        return error / Double(320 * 180 * 3)
    }
    var sampledColors: Int {
        var result = Set<UInt32>()
        for offset in stride(from: 0, to: bytes.count - 4, by: 40) {
            result.insert((UInt32(bytes[offset]) << 16) | (UInt32(bytes[offset + 1]) << 8) | UInt32(bytes[offset + 2]))
        }
        return result.count
    }
}

private final class ActionCounter: NSObject {
    var count = 0
    @objc func changed(_ sender: Any?) { count += 1 }
}

private final class ThumbnailSmokeRun {
    private let generator = ThumbnailGenerator()
    private let engine: MPVEngine
    private let window: NSWindow
    private let mediaDirectory: URL
    private let output: URL
    private let slider = SeekSlider(frame: NSRect(x: 32, y: 42, width: 576, height: 24))
    private let preview = ThumbnailPreviewView(frame: NSRect(origin: .zero, size: ThumbnailPreviewView.preferredSize))
    private let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
    private let actionCounter = ActionCounter()
    private var failures = [String]()
    private var total = 0
    private var fixtureLoaded = false

    init(mediaDirectory: URL, output: URL) throws {
        self.mediaDirectory = mediaDirectory
        self.output = output
        engine = try MPVEngine()
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "LPlayer · Synthetic thumbnail check"
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.contentView = container
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.background.cgColor
        engine.videoView.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        container.addSubview(engine.videoView)
        slider.minValue = 0
        slider.maxValue = 48
        slider.doubleValue = 9
        slider.target = actionCounter
        slider.action = #selector(ActionCounter.changed(_:))
        container.addSubview(slider)
        preview.frame.origin = NSPoint(x: 214, y: 87)
        preview.pointerX = preview.bounds.midX
        container.addSubview(preview)
        engine.onFileLoaded = { [weak self] in self?.fixtureLoaded = true }
    }

    func run() {
        // No activation, screen capture, shared defaults, or user media involved.
        window.orderBack(nil)
        checkSlider()
        let mp4 = mediaDirectory.appendingPathComponent("Palm Demo 01.mp4")
        let mkv = mediaDirectory.appendingPathComponent("Palm Demo 01.mkv")
        let second = mediaDirectory.appendingPathComponent("Palm Demo 02.mp4")
        _ = request(mp4, at: 0, label: "MP4 opening frame")
        let early = request(mp4, at: 3.2, label: "MP4 early frame")
        let late = request(mp4, at: 34.7, label: "MP4 distant frame")
        if let early, let late, let a = FixturePixels(image: early.image), let b = FixturePixels(image: late.image) {
            let difference = a.difference(from: b)
            print(String(format: "INFO distant MP4 thumbnail pixel MAE=%.3f", difference))
            check(a.sampledColors > 16, "MP4 thumbnail contains actual varied fixture pixels")
            check(difference > 0.2, "distant hover positions produce distinct actual video frames")
        } else { check(false, "MP4 fixture thumbnails decode to pixel data") }
        let mkvFrame = request(mkv, at: 34.7, label: "MKV frame")
        if let late, let mkvFrame, let a = FixturePixels(image: late.image), let b = FixturePixels(image: mkvFrame.image) {
            let difference = a.difference(from: b)
            print(String(format: "INFO same-frame MP4/MKV thumbnail pixel MAE=%.3f", difference))
            check(b.sampledColors > 16, "MKV thumbnail contains actual video pixels")
            check(difference < 4, "MKV and MP4 resolve the same fixture timestamp")
        }
        checkLatestWins(mp4)
        checkCancellation(mp4)
        checkSeekSuspension(mp4)
        checkMediaSwitch(mp4, second: second, firstFrame: early)
        checkMissingFile()
        checkCorruptFile()
        checkPlaybackIndependence(mp4)
        if let late { capturePreview(late) }
        generator.shutdown()
        generator.shutdown()
        var stoppedCompleted = false
        var stoppedImage = false
        generator.request(url: mp4, time: 4) { image in
            stoppedCompleted = true
            stoppedImage = image != nil
        }
        wait(timeout: 1, until: { stoppedCompleted })
        check(stoppedCompleted && !stoppedImage, "repeated shutdown is safe and later requests complete unavailable")
        engine.shutdown()
        window.orderOut(nil)
        print(failures.isEmpty ? "PASS thumbnail integration check (\(total) assertions)" : "FAIL thumbnail integration check: \(failures.count) failed assertion(s)")
        exit(failures.isEmpty ? 0 : 1)
    }

    private func checkSlider() {
        guard let cell = slider.cell as? NSSliderCell else { check(false, "native slider cell exists"); return }
        slider.doubleValue = slider.minValue
        let left = cell.knobRect(flipped: slider.isFlipped).midX
        slider.doubleValue = slider.maxValue
        let right = cell.knobRect(flipped: slider.isFlipped).midX
        slider.doubleValue = 9
        let y = slider.bounds.midY
        let first = slider.hoverTime(at: NSPoint(x: left, y: y))
        let middle = slider.hoverTime(at: NSPoint(x: (left + right) / 2, y: y))
        let last = slider.hoverTime(at: NSPoint(x: right, y: y))
        check(first.map { abs($0) < 0.001 } ?? false, "hover starts at first native knob center")
        check(middle.map { abs($0 - 24) < 0.001 } ?? false, "hover midpoint maps to half duration")
        check(last.map { abs($0 - 48) < 0.001 } ?? false, "hover ends at last native knob center")
        check(abs(slider.doubleValue - 9) < 0.001, "hover-time geometry preserves playback slider value")
        var hoverCallbacks = 0
        var endCallbacks = 0
        var hoveredTime = -1.0
        slider.onHover = { time, _ in hoverCallbacks += 1; hoveredTime = time }
        slider.onHoverEnd = { endCallbacks += 1 }
        let point = NSPoint(x: (left + right) / 2, y: y)
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: slider.convert(point, to: nil),
                                         modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 0, clickCount: 0, pressure: 0) {
            slider.mouseMoved(with: event)
        }
        check(hoverCallbacks == 1 && abs(hoveredTime - 24) < 0.001, "synthetic slider mouse movement publishes hovered time")
        check(slider.hoverPoint != nil, "slider records the local hover point")
        check(actionCounter.count == 0 && abs(slider.doubleValue - 9) < 0.001,
              "hovering neither sends a seek action nor changes playback value")
        slider.endHover()
        check(endCallbacks == 1 && slider.hoverPoint == nil, "ending hover clears the point and publishes one exit")
        slider.endHover()
        check(endCallbacks == 1, "repeated hover exit is idempotent")
        if let moved = NSEvent.mouseEvent(with: .mouseMoved, location: slider.convert(point, to: nil),
                                         modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 1, clickCount: 0, pressure: 0),
           let exited = NSEvent.enterExitEvent(with: .mouseExited, location: slider.convert(point, to: nil),
                                              modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 2, trackingNumber: 0, userData: nil) {
            slider.mouseMoved(with: moved)
            slider.mouseExited(with: exited)
        }
        check(endCallbacks == 2 && slider.hoverPoint == nil, "synthetic mouse-exit event ends thumbnail hover")
        check(preview.hitTest(NSPoint(x: preview.bounds.midX, y: preview.bounds.midY)) == nil, "thumbnail overlay lets mouse input reach underlying controls")
        slider.isEnabled = false
        check(slider.hoverTime(at: point) == nil, "disabled slider has no hover timestamp")
        slider.isEnabled = true
        slider.maxValue = 0
        check(slider.hoverTime(at: point) == nil, "unknown duration has no hover timestamp")
        slider.maxValue = 48
    }

    private func checkSeekSuspension(_ media: URL) {
        let cached = request(media, at: 9, label: "pre-seek cached thumbnail")
        var callbacks = 0
        generator.request(url: media, time: 26) { _ in callbacks += 1 }
        wait(timeout: 0.09, until: { false })
        let beforeSuspension = callbacks
        generator.suspend()
        wait(timeout: 0.2, until: { false })
        check(callbacks == beforeSuspension, "playback seek suspension rejects unfinished preview callbacks")
        let after = request(media, at: 9, label: "cached preview after seek suspension")
        check(cached != nil && cached?.image === after?.image, "playback seek suspension preserves small cached thumbnails")
        _ = request(media, at: 28, label: "fresh preview after decoder resumes")
    }

    private func request(_ url: URL, at time: Double, label: String) -> ThumbnailGenerator.Thumbnail? {
        var completed = false
        var result: ThumbnailGenerator.Thumbnail?
        generator.request(url: url, time: time) { thumbnail in
            self.check(Thread.isMainThread, "\(label) completion runs on the main thread")
            result = thumbnail
            completed = true
        }
        wait(timeout: 8, until: { completed })
        check(completed, "\(label) request completes")
        check(result != nil, "\(label) produces an image")
        if let result {
            check(result.image.size.width > 0 && result.image.size.height > 0 && result.image.size.width <= 640 && result.image.size.height <= 360,
                  "\(label) image dimensions stay within 640×360 for Retina playlist cards")
            check(abs(result.time - floor(time)) < 0.001, "\(label) reports its second-level timestamp")
        }
        return result
    }

    private func checkLatestWins(_ media: URL) {
        generator.reset()
        var delivered: [Double] = []
        for time in 5...24 {
            generator.request(url: media, time: Double(time)) { result in
                delivered.append(result?.time ?? -1)
            }
        }
        wait(timeout: 8, until: { !delivered.isEmpty })
        pump(0.3)
        check(delivered == [24], "rapid hover requests deliver only the newest thumbnail")
    }

    private func checkCancellation(_ media: URL) {
        generator.reset()
        var delivered = 0
        generator.request(url: media, time: 14) { _ in delivered += 1 }
        generator.cancel()
        pump(0.6)
        check(delivered == 0, "leaving the progress bar cancels a pending thumbnail completion")
    }

    private func checkMediaSwitch(_ first: URL, second: URL, firstFrame: ThumbnailGenerator.Thumbnail?) {
        generator.reset()
        var staleCallbacks = 0
        var switched = false
        generator.request(url: first, time: 3) { _ in if switched { staleCallbacks += 1 } }
        // Let a decode begin before switching, exercising the generation guard
        // for both pending and already active work without delaying user input.
        pump(0.085)
        switched = true
        generator.reset()
        let newer = request(second, at: 3, label: "replacement media frame")
        pump(0.3)
        check(staleCallbacks == 0, "media switch rejects results from the earlier video")
        if let firstFrame, let newer, let a = FixturePixels(image: firstFrame.image), let b = FixturePixels(image: newer.image) {
            check(a.difference(from: b) > 10, "replacement thumbnail belongs to the new fixture video")
        }
    }

    private func checkMissingFile() {
        generator.reset()
        var completed = false
        var gotImage = false
        generator.request(url: mediaDirectory.appendingPathComponent("intentionally-missing.mkv"), time: 8) { image in
            completed = true
            gotImage = image != nil
        }
        wait(timeout: 8, until: { completed })
        check(completed && !gotImage, "missing media completes gracefully without an image")
    }

    private func checkCorruptFile() {
        generator.reset()
        let bad = output.appendingPathComponent(".intentionally-broken.mp4")
        do { try Data("This is not a movie.".utf8).write(to: bad) }
        catch { check(false, "corrupt fixture writes successfully"); return }
        defer { try? FileManager.default.removeItem(at: bad) }
        var completed = false
        var gotImage = false
        generator.request(url: bad, time: 8) { image in
            completed = true
            gotImage = image != nil
        }
        wait(timeout: 8, until: { completed })
        check(completed && !gotImage, "invalid video completes gracefully without an image")
    }

    private func checkPlaybackIndependence(_ media: URL) {
        engine.setDouble("volume", 0)
        engine.load(media, start: 2)
        wait(timeout: 8, until: { fixtureLoaded })
        check(fixtureLoaded, "independent fixture playback starts")
        pump(0.35)
        let beginning = engine.snapshot.position
        let startedAt = ProcessInfo.processInfo.systemUptime
        generator.reset()
        for time in [4.0, 13.0, 22.0, 31.0, 40.0] {
            _ = request(media, at: time, label: "live-playback hover \(Int(time))")
            pump(0.12)
        }
        pump(0.5)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let advanced = engine.snapshot.position - beginning
        print(String(format: "INFO playback advance=%.3fs elapsed=%.3fs during thumbnail work", advanced, elapsed))
        check(!engine.snapshot.paused, "thumbnail requests preserve active playback")
        check(advanced > elapsed * 0.65 && advanced < elapsed + 0.45,
              "playback keeps advancing naturally while thumbnails decode")
        check(engine.snapshot.mediaPath == media.path && engine.snapshot.position < 15,
              "hover decode neither loads another file nor seeks the main player")
    }

    private func capturePreview(_ thumbnail: ThumbnailGenerator.Thumbnail) {
        engine.videoView.isHidden = true
        slider.doubleValue = 9
        preview.isHidden = false
        preview.setPreview(time: thumbnail.time, image: thumbnail.image, state: .ready)
        preview.needsDisplay = true
        container.layoutSubtreeIfNeeded()
        guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
            check(false, "preview bitmap can be allocated"); return
        }
        container.cacheDisplay(in: container.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                check(false, "preview bitmap encodes PNG"); return
            }
            let file = output.appendingPathComponent("hover.png")
            try data.write(to: file)
            check(true, "standalone hover preview rendered to fixture-only PNG")
            print("INFO preview \(file.path)")
        } catch { check(false, "preview PNG writes successfully") }
    }

    private func wait(timeout: Double, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }
    private func pump(_ seconds: Double) { wait(timeout: seconds, until: { false }) }
    private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        total += 1
        if condition() { print("PASS \(message)") }
        else { failures.append(message); print("FAIL \(message)") }
    }
}
