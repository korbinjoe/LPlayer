import Foundation
import CoreGraphics

/// Geometry is in top-left-origin view points. mpv's video-zoom is log2(scale),
/// while video-pan-x/y are fractions of the full, scaled video rectangle.
/// Keeping this math independent of renderer pixels also makes Retina changes
/// and window/fullscreen resizing preserve the selected area of the picture.
struct VideoViewport: Equatable {
    static let scaleRange = 1.0...5.0

    private(set) var size = CGSize.zero
    private(set) var displayAspect: Double?
    private(set) var scale: Double = 1
    private(set) var panX: Double = 0
    private(set) var panY: Double = 0

    var canZoom: Bool { fittedSize != nil }
    var mpvZoom: Double { log2(scale) }

    var videoRect: CGRect? {
        guard let fit = fittedSize else { return nil }
        let width = fit.width * scale, height = fit.height * scale
        return CGRect(x: (size.width - width) / 2 + panX * width,
                      y: (size.height - height) / 2 + panY * height,
                      width: width, height: height)
    }

    mutating func resize(to newSize: CGSize) {
        guard newSize.width.isFinite, newSize.height.isFinite,
              newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        clampPan()
    }

    mutating func setDisplayAspect(_ aspect: Double?) {
        if let aspect, aspect.isFinite, (0.000001...1_000_000).contains(aspect) {
            displayAspect = aspect
            clampPan()
        } else {
            displayAspect = nil
            reset()
        }
    }

    mutating func reset() {
        scale = 1
        panX = 0
        panY = 0
    }

    /// Move the enlarged picture by view points, independently of display scale.
    /// Axes which still fit inside the viewport stay centered in their letterbox.
    mutating func pan(by delta: CGPoint) {
        guard scale > 1, delta.x.isFinite, delta.y.isFinite,
              let rectangle = videoRect,
              rectangle.width.isFinite, rectangle.height.isFinite,
              rectangle.width > 0, rectangle.height > 0 else { return }
        // A whole-image displacement already reaches either edge. Limit before
        // normalizing so even an extreme finite input cannot overflow to infinity.
        panX += min(rectangle.width, max(-rectangle.width, delta.x)) / rectangle.width
        panY += min(rectangle.height, max(-rectangle.height, delta.y)) / rectangle.height
        clampPan()
    }

    /// Preserve the image coordinate under the gesture. If an edge is reached,
    /// keep the picture against that edge rather than exposing new black space.
    mutating func setScale(_ proposedScale: Double, at proposedPoint: CGPoint? = nil) {
        guard proposedScale.isFinite, let oldRect = videoRect else { return }
        let nextScale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, proposedScale))
        guard nextScale != scale else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rawPoint = proposedPoint ?? center
        let safePoint = rawPoint.x.isFinite && rawPoint.y.isFinite ? rawPoint : center
        // A pinch initiated on a letterbox bar uses the nearest image edge.
        let point = CGPoint(x: min(oldRect.maxX, max(oldRect.minX, min(size.width, max(0, safePoint.x)))),
                            y: min(oldRect.maxY, max(oldRect.minY, min(size.height, max(0, safePoint.y)))))
        let imageX = (point.x - oldRect.minX) / oldRect.width
        let imageY = (point.y - oldRect.minY) / oldRect.height
        let ratio = nextScale / scale
        let width = oldRect.width * ratio, height = oldRect.height * ratio
        scale = nextScale
        panX = (point.x - imageX * width - (size.width - width) / 2) / width
        panY = (point.y - imageY * height - (size.height - height) / 2) / height
        clampPan()
    }

    private var fittedSize: CGSize? {
        guard let aspect = displayAspect, size.width > 0, size.height > 0 else { return nil }
        let height = min(size.height, size.width / aspect)
        return CGSize(width: height * aspect, height: height)
    }

    private mutating func clampPan() {
        guard let fit = fittedSize, scale > 1 else {
            panX = 0
            panY = 0
            return
        }
        let width = fit.width * scale, height = fit.height * scale
        let maxX = max(0, (width - size.width) / (2 * width))
        let maxY = max(0, (height - size.height) / (2 * height))
        panX = panX.isFinite ? min(maxX, max(-maxX, panX)) : 0
        panY = panY.isFinite ? min(maxY, max(-maxY, panY)) : 0
    }
}
