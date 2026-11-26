import AppKit
import SwiftUI

@MainActor
final class BeatCanvas: NSView {
    var target: BeatTarget?
    var elapsed = 0.0
    var playing = false
    var onPointer: (BeatPoint?, CGSize) -> Void = { _, _ in }
    var onHit: (BeatPoint, CGSize) -> Void = { _, _ in }

    private var tracking: NSTrackingArea?
    private var pointer: CGPoint?
    private let ink = NSColor(calibratedRed: 0.63, green: 0.42, blue: 1, alpha: 1)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    private var field: CGRect { bounds.insetBy(dx: 26, dy: 26) }

    private func normalized(_ point: CGPoint) -> BeatPoint {
        .init(x: Double((point.x - field.minX) / field.width),
              y: Double((point.y - field.minY) / field.height))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = field.contains(point) ? point : nil
        onPointer(pointer.map(normalized), field.size)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        onPointer(nil, field.size)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard field.contains(point) else { return }
        onHit(normalized(point), field.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor(calibratedRed: 0.035, green: 0.028, blue: 0.064, alpha: 1).cgColor)
        context.fill(bounds)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.055).cgColor)
        context.setLineWidth(1)
        for fraction in 1...4 {
            let x = field.minX + CGFloat(fraction) * field.width / 5
            let y = field.minY + CGFloat(fraction) * field.height / 5
            context.move(to: CGPoint(x: x, y: field.minY))
            context.addLine(to: CGPoint(x: x, y: field.maxY))
            context.move(to: CGPoint(x: field.minX, y: y))
            context.addLine(to: CGPoint(x: field.maxX, y: y))
        }
        context.strokePath()

        if let target {
            let toBeat = target.time - elapsed
            let visible = !playing || (-0.18...1.1).contains(toBeat)
            if visible {
                let centre = CGPoint(x: field.minX + target.centre.x * field.width,
                                     y: field.minY + target.centre.y * field.height)
                let progress = !playing ? 1.0 : min(1, max(0, toBeat / 1.1))
                let approachRadius = 36 + 90 * progress
                context.setStrokeColor(ink.withAlphaComponent(0.75).cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: centre.x - approachRadius,
                                                 y: centre.y - approachRadius,
                                                 width: 2 * approachRadius,
                                                 height: 2 * approachRadius))
                context.setFillColor(ink.withAlphaComponent(0.35).cgColor)
                context.fillEllipse(in: CGRect(x: centre.x - 36, y: centre.y - 36,
                                               width: 72, height: 72))
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                context.setLineWidth(2.5)
                context.strokeEllipse(in: CGRect(x: centre.x - 36, y: centre.y - 36,
                                                 width: 72, height: 72))
                let label = "\(target.number)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 19, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let size = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: centre.x - size.width / 2,
                                       y: centre.y - size.height / 2), withAttributes: attributes)
            }
        }
        if let pointer {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: CGRect(x: pointer.x - 8, y: pointer.y - 8,
                                             width: 16, height: 16))
            context.move(to: CGPoint(x: pointer.x - 15, y: pointer.y))
            context.addLine(to: CGPoint(x: pointer.x + 15, y: pointer.y))
            context.move(to: CGPoint(x: pointer.x, y: pointer.y - 15))
            context.addLine(to: CGPoint(x: pointer.x, y: pointer.y + 15))
            context.strokePath()
        }
    }
}

struct BeatCanvasView: NSViewRepresentable {
    @ObservedObject var model: BeatGameModel

    func makeNSView(context: Context) -> BeatCanvas { BeatCanvas(frame: .zero) }

    func updateNSView(_ view: BeatCanvas, context: Context) {
        view.target = model.currentTarget
        view.elapsed = model.elapsed
        view.playing = model.isPlaying
        view.onPointer = { model.pointerMoved($0, size: $1) }
        view.onHit = { model.attemptHit($0, size: $1) }
        view.needsDisplay = true
    }
}
