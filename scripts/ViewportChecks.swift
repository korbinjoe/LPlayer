import Foundation
import CoreGraphics
import Darwin

/// Runs the real viewport geometry using Command Line Tools, without XCTest.
@main
enum ViewportChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000001 }
    static func viewport(width: Double = 960, height: Double = 540, aspect: Double = 16 / 9) -> VideoViewport {
        var result = VideoViewport()
        result.resize(to: CGSize(width: width, height: height))
        result.setDisplayAspect(aspect)
        return result
    }
    static func rect(_ view: VideoViewport) throws -> CGRect {
        guard let rect = view.videoRect else { throw Failure(description: "Missing video rectangle") }
        return rect
    }
    static func main() {
        do {
            try anchoredPinch()
            try letterboxes()
            try edges()
            try limits()
            try resizing()
            try malformedInputs()
            try mediaChange()
            try panDisplacement()
            try panEdges()
            try panLetterboxes()
            try panResizeAndReset()
            try panThenPinch()
            try panMalformedInputs()
            print("All 13 video viewport checks passed.")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    static func anchoredPinch() throws {
        var view = viewport()
        let point = CGPoint(x: 320, y: 220)
        let before = try rect(view)
        let imageX = (point.x - before.minX) / before.width
        let imageY = (point.y - before.minY) / before.height
        view.setScale(2, at: point)
        let after = try rect(view)
        try require(near(after.minX + imageX * after.width, point.x), "Horizontal gesture anchor moved")
        try require(near(after.minY + imageY * after.height, point.y), "Vertical gesture anchor moved")
        try require(near(view.mpvZoom, 1), "2x must map to mpv video-zoom=1")
        print("PASS off-center pinch retains the exact image point")
    }

    static func letterboxes() throws {
        var wide = viewport(aspect: 3)
        wide.setScale(1.25, at: CGPoint(x: 100, y: 5))
        try require(wide.panY == 0 && near(try rect(wide).midY, 270), "Wide video drifted vertically within its letterbox")
        var portrait = viewport(aspect: 9 / 16)
        portrait.setScale(2, at: CGPoint(x: 40, y: 500))
        try require(portrait.panX == 0 && near(try rect(portrait).midX, 480), "Portrait video drifted horizontally within its letterbox")
        print("PASS wide and portrait letterboxes remain centered")
    }

    static func edges() throws {
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 960, y: 540), CGPoint(x: -500, y: 1000)] {
            var view = viewport()
            for scale in [1.1, 2, 4, 5, 2, 1.2] {
                view.setScale(scale, at: point)
                let rectangle = try rect(view)
                try require(rectangle.minX <= 0.000001 && rectangle.minY <= 0.000001 &&
                            rectangle.maxX >= 959.999999 && rectangle.maxY >= 539.999999,
                            "An edge pinch exposed black space")
            }
        }
        print("PASS repeated edge pinches never expose new blank space")
    }

    static func limits() throws {
        var view = viewport()
        view.setScale(20, at: CGPoint(x: 1, y: 1))
        try require(view.scale == 5, "Zoom exceeded 5x")
        view.setScale(0.25)
        try require(view.scale == 1 && view.panX == 0 && view.panY == 0, "Fit reset retained a crop")
        try require(try rect(view) == CGRect(x: 0, y: 0, width: 960, height: 540), "1x must fit the whole image")
        print("PASS 1x to 5x range and exact fit reset")
    }

    static func resizing() throws {
        var view = viewport()
        view.setScale(2, at: CGPoint(x: 300, y: 200))
        let oldPan = CGPoint(x: view.panX, y: view.panY)
        view.resize(to: CGSize(width: 1920, height: 1080))
        try require(near(view.panX, oldPan.x) && near(view.panY, oldPan.y), "Retina/fullscreen proportional resize changed crop")
        view.resize(to: CGSize(width: 4000, height: 400))
        try require(view.panX == 0 && near(try rect(view).midX, 2000), "Aspect-changing resize failed to recenter letterbox")
        print("PASS resize preserves normalized crop and clamps new letterboxes")
    }

    static func malformedInputs() throws {
        var view = viewport()
        view.setScale(.nan)
        view.setScale(.infinity)
        view.resize(to: CGSize(width: CGFloat.infinity, height: -CGFloat.infinity))
        view.setScale(2, at: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))
        try require(view.scale == 2 && view.panX == 0 && view.panY == 0, "Invalid event coordinates poisoned the viewport")
        try require(try rect(view).width.isFinite, "Nonfinite render geometry")
        view.setDisplayAspect(.nan)
        try require(!view.canZoom && view.scale == 1, "Invalid video dimensions retained zoom")
        print("PASS nonfinite scales, dimensions and points remain safe")
    }

    static func mediaChange() throws {
        var view = viewport()
        view.setScale(4, at: CGPoint(x: 100, y: 100))
        view.setDisplayAspect(nil)
        view.setScale(3)
        try require(view.scale == 1 && view.panX == 0 && view.panY == 0 && !view.canZoom,
                    "Cleared or audio-only media retained a crop")
        print("PASS media clear resets pan and blocks zoom without video")
    }

    static func panDisplacement() throws {
        var view = viewport()
        let fitted = view
        view.pan(by: CGPoint(x: 120, y: -60))
        try require(view == fitted, "Dragging at fit size moved the picture")
        view.setScale(2)
        let before = try rect(view)
        view.pan(by: CGPoint(x: 120, y: -60))
        let after = try rect(view)
        try require(near(after.minX - before.minX, 120) && near(after.minY - before.minY, -60),
                    "Picture did not follow a drag in view points")
        try require(view.scale == 2 && after.size == before.size, "Dragging changed the zoom scale")
        view.pan(by: CGPoint(x: -30, y: 20))
        try require(near(try rect(view).minX - before.minX, 90) &&
                    near(try rect(view).minY - before.minY, -40), "Consecutive drag deltas were not accumulated")
        print("PASS dragging follows point deltas without changing magnification")
    }

    static func panEdges() throws {
        var view = viewport()
        view.setScale(2)
        view.pan(by: CGPoint(x: 100_000, y: 100_000))
        try require(near(try rect(view).minX, 0) && near(try rect(view).minY, 0),
                    "Dragging past the first image edge exposed blank space")
        view.pan(by: CGPoint(x: -1, y: -1))
        try require(near(try rect(view).minX, -1) && near(try rect(view).minY, -1),
                    "Dragging back from a clamped edge retained an invisible overshoot")
        view.pan(by: CGPoint(x: -100_000, y: -100_000))
        try require(near(try rect(view).maxX, 960) && near(try rect(view).maxY, 540),
                    "Dragging past the opposite edge exposed blank space")
        view.pan(by: CGPoint(x: 1, y: 1))
        try require(near(try rect(view).maxX, 961) && near(try rect(view).maxY, 541),
                    "Opposite-edge drag did not respond immediately")
        print("PASS pan boundaries cover the viewport and reverse immediately")
    }

    static func panLetterboxes() throws {
        var wide = viewport(aspect: 3)
        wide.setScale(1.25)
        wide.pan(by: CGPoint(x: 100, y: 100))
        try require(near(try rect(wide).minX, -20) && wide.panY == 0 &&
                    near(try rect(wide).midY, 270), "Dragging a wide video shifted its letterbox axis")
        var portrait = viewport(aspect: 9 / 16)
        portrait.setScale(2)
        portrait.pan(by: CGPoint(x: -100, y: -100))
        try require(portrait.panX == 0 && near(try rect(portrait).midX, 480) &&
                    near(try rect(portrait).minY, -370), "Dragging a portrait video shifted its letterbox axis")
        var square = viewport(aspect: 1)
        square.setScale(2)
        square.pan(by: CGPoint(x: 1_000, y: -1_000))
        try require(near(try rect(square).minX, 0) && near(try rect(square).maxY, 540),
                    "Independent image axes did not clamp to their actual bounds")
        print("PASS wide, portrait and square videos clamp each pan axis independently")
    }

    static func panResizeAndReset() throws {
        var view = viewport()
        view.setScale(2)
        view.pan(by: CGPoint(x: 120, y: -60))
        let before = try rect(view)
        let pan = CGPoint(x: view.panX, y: view.panY)
        view.resize(to: CGSize(width: 1920, height: 1080))
        try require(near(view.panX, pan.x) && near(view.panY, pan.y) &&
                    near(try rect(view).minX, before.minX * 2), "Resizing lost the dragged crop")
        let resized = try rect(view)
        view.pan(by: CGPoint(x: 10, y: 10))
        try require(near(try rect(view).minX - resized.minX, 10) &&
                    near(try rect(view).minY - resized.minY, 10), "Resize changed drag units from view points")
        view.resize(to: CGSize(width: 4000, height: 400))
        try require(view.panX == 0 && near(try rect(view).midX, 2000),
                    "Aspect-changing resize retained a pan on a letterboxed axis")
        view.reset()
        try require(view.scale == 1 && view.panX == 0 && view.panY == 0, "Fit did not clear the dragged crop")
        view.setScale(3)
        view.pan(by: CGPoint(x: 20, y: 20))
        view.setDisplayAspect(nil)
        view.setDisplayAspect(16 / 9)
        try require(view.scale == 1 && view.panX == 0 && view.panY == 0,
                    "Opening a new video retained the previous dragged crop")
        print("PASS resize retains the crop while fit and new media clear it")
    }

    static func panThenPinch() throws {
        var view = viewport()
        view.setScale(2)
        view.pan(by: CGPoint(x: 120, y: -60))
        let point = CGPoint(x: 400, y: 250)
        let before = try rect(view)
        let imagePoint = CGPoint(x: (point.x - before.minX) / before.width,
                                 y: (point.y - before.minY) / before.height)
        view.setScale(3, at: point)
        let after = try rect(view)
        try require(near(after.minX + imagePoint.x * after.width, point.x) &&
                    near(after.minY + imagePoint.y * after.height, point.y),
                    "Pinching after a drag lost its image anchor")
        view.setScale(1)
        try require(view.panX == 0 && view.panY == 0 &&
                    (try rect(view)) == CGRect(x: 0, y: 0, width: 960, height: 540),
                    "Pinching back to fit retained the dragged crop")
        print("PASS pinch continues from the dragged region and returns exactly to fit")
    }

    static func panMalformedInputs() throws {
        var empty = VideoViewport()
        empty.pan(by: CGPoint(x: 100, y: 100))
        try require(empty.panX == 0 && empty.panY == 0 && !empty.canZoom,
                    "Dragging without video created a crop")
        var view = viewport()
        view.setScale(2)
        view.pan(by: CGPoint(x: 100, y: -50))
        let before = view
        for delta in [CGPoint(x: CGFloat.nan, y: 20), CGPoint(x: 20, y: CGFloat.infinity),
                      CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity)] {
            view.pan(by: delta)
            try require(view == before, "Invalid pan delta modified the picture")
        }
        view.pan(by: CGPoint(x: CGFloat.greatestFiniteMagnitude, y: -CGFloat.greatestFiniteMagnitude))
        try require(near(try rect(view).minX, 0) && near(try rect(view).maxY, 540) &&
                    view.panX.isFinite && view.panY.isFinite && view.scale == 2,
                    "Extreme finite drag overflowed or lost its edge direction")
        print("PASS absent media, nonfinite input and extreme finite drags remain safe")
    }
}
