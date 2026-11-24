import AppKit
import SwiftUI

@MainActor
final class TraceCanvas: NSView {
    var series = TraceLibrary.series
    var selectedID: Int?
    var progress = 0.0
    var pinned = false
    var showLine = true
    var onPressStart: (Int) -> Void = { _ in }
    var onPressEnd: (Bool) -> Void = { _ in }
    var onScrub: (Double?) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    private var tracking: NSTrackingArea?
    private var pressedID: Int?
    private var pressedAt = 0.0
    private let purple = NSColor(calibratedRed: 0.43, green: 0.16, blue: 0.71, alpha: 1)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }

    private var plot: CGRect { bounds.insetBy(dx: 65, dy: 55) }

    private func location(of series: TraceSeries) -> CGPoint {
        CGPoint(x: plot.minX + series.position.x * plot.width,
                y: plot.minY + series.position.y * plot.height)
    }

    private func hit(_ point: CGPoint) -> Int? {
        series.min(by: {
            hypot(location(of: $0).x - point.x, location(of: $0).y - point.y) <
            hypot(location(of: $1).x - point.x, location(of: $1).y - point.y)
        }).flatMap { candidate in
            hypot(location(of: candidate).x - point.x,
                  location(of: candidate).y - point.y) <= 21 ? candidate.id : nil
        }
    }

    private func card(for series: TraceSeries) -> CGRect {
        let size = CGSize(width: min(310, max(220, bounds.width - 34)), height: 176)
        let point = location(of: series)
        let x = min(bounds.maxX - size.width - 16, max(16, point.x + 24))
        let above = point.y + 23
        let y = above + size.height <= bounds.maxY - 12
            ? above : max(12, point.y - size.height - 23)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func chart(in card: CGRect) -> CGRect {
        CGRect(x: card.minX + 18, y: card.minY + 27,
               width: card.width - 36, height: card.height - 66)
    }

    private func scrub(at point: CGPoint) {
        guard pinned, let selectedID,
              let selected = series.first(where: { $0.id == selectedID }) else { return }
        let rect = chart(in: card(for: selected))
        onScrub(rect.contains(point) ? Double((point.x - rect.minX) / rect.width) : nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = hit(point) {
            pressedID = id
            pressedAt = ProcessInfo.processInfo.systemUptime
            onPressStart(id)
        } else if pinned {
            scrub(at: point)
            if let selectedID, let selected = series.first(where: { $0.id == selectedID }),
               !card(for: selected).contains(point) { onDismiss() }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if pinned { scrub(at: convert(event.locationInWindow, from: nil)) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let pressedID else { return }
        self.pressedID = nil
        let point = convert(event.locationInWindow, from: nil)
        let quick = ProcessInfo.processInfo.systemUptime - pressedAt < 0.28 && hit(point) == pressedID
        onPressEnd(quick)
    }

    override func mouseMoved(with event: NSEvent) {
        scrub(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { onScrub(nil) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedRed: 0.985, green: 0.98, blue: 0.99, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(1)
        for index in 0...4 {
            let x = plot.minX + CGFloat(index) * plot.width / 4
            let y = plot.minY + CGFloat(index) * plot.height / 4
            context.move(to: CGPoint(x: x, y: plot.minY))
            context.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        context.strokePath()
        drawLabel("DIMENSION A", at: CGPoint(x: plot.midX - 45, y: 21),
                  colour: .secondaryLabelColor, size: 10)
        drawLabel("DIMENSION B", at: CGPoint(x: 13, y: plot.midY),
                  colour: .secondaryLabelColor, size: 10)

        for item in series {
            let point = location(of: item)
            let chosen = item.id == selectedID
            if chosen {
                context.setStrokeColor(purple.withAlphaComponent(0.35).cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: point.x - 16, y: point.y - 16,
                                                 width: 32, height: 32))
            }
            context.setFillColor(purple.withAlphaComponent(chosen ? 1 : 0.78).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 9, y: point.y - 9,
                                           width: 18, height: 18))
        }

        if let selectedID, let item = series.first(where: { $0.id == selectedID }) {
            drawCard(for: item, context: context)
        }
    }

    private func drawCard(for item: TraceSeries, context: CGContext) {
        let rect = card(for: item)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20,
                          color: NSColor.black.withAlphaComponent(0.18).cgColor)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15).fill()
        context.restoreGState()
        purple.withAlphaComponent(0.18).setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15).stroke()
        drawLabel("\(item.label.uppercased())  ·  \(item.shape.rawValue.uppercased())",
                  at: CGPoint(x: rect.minX + 18, y: rect.maxY - 29),
                  colour: purple, size: 11)
        drawLabel(pinned ? "PINNED · MOVE OVER THE TRACE TO SCRUB" : "HOLD TO FEEL · RELEASE TO CLOSE",
                  at: CGPoint(x: rect.minX + 18, y: rect.minY + 9),
                  colour: .secondaryLabelColor, size: 9)

        let line = chart(in: rect)
        context.setStrokeColor(purple.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: line.minX, y: line.midY))
        context.addLine(to: CGPoint(x: line.maxX, y: line.midY))
        context.strokePath()
        if showLine {
            context.setStrokeColor(purple.cgColor)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for (index, value) in item.values.enumerated() {
                let point = CGPoint(x: line.minX + CGFloat(index) / CGFloat(item.values.count - 1) * line.width,
                                    y: line.minY + value * line.height)
                if index == 0 { context.move(to: point) }
                else { context.addLine(to: point) }
            }
            context.strokePath()
        } else {
            drawLabel("HAPTIC TRACE", at: CGPoint(x: line.midX - 42, y: line.midY),
                      colour: .secondaryLabelColor, size: 10)
        }
        let x = line.minX + progress * line.width
        context.setStrokeColor(purple.withAlphaComponent(0.48).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: line.minY))
        context.addLine(to: CGPoint(x: x, y: line.maxY))
        context.strokePath()
        let value = TraceHapticMapping.value(in: item.values, at: progress) ?? 0
        context.setFillColor(purple.cgColor)
        context.fillEllipse(in: CGRect(x: x - 4, y: line.minY + value * line.height - 4,
                                       width: 8, height: 8))
    }

    private func drawLabel(_ text: String, at point: CGPoint, colour: NSColor, size: CGFloat) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: colour
        ])
    }
}

struct TraceCanvasView: NSViewRepresentable {
    let model: TraceModel

    func makeNSView(context: Context) -> TraceCanvas { TraceCanvas(frame: .zero) }

    func updateNSView(_ view: TraceCanvas, context: Context) {
        view.selectedID = model.selectedID
        view.progress = model.progress
        view.pinned = model.pinned
        view.showLine = model.showLine
        view.onPressStart = { model.beginPress($0) }
        view.onPressEnd = { model.endPress(quickClick: $0) }
        view.onScrub = { model.scrub($0) }
        view.onDismiss = { model.clearSelection() }
        view.needsDisplay = true
    }
}
