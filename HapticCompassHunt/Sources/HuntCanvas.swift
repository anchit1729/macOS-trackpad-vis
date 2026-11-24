import AppKit
import SwiftUI

@MainActor
final class HuntCanvas: NSView {
    var target = HuntPoint(x: 0.5, y: 0.5)
    var found = false
    var proximity = 0.0
    var onPointer: (HuntPoint?, HuntSize) -> Void = { _, _ in }

    private var tracking: NSTrackingArea?
    private var pointer: CGPoint?
    private var trail: [CGPoint] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                options: [.mouseMoved, .mouseEnteredAndExited,
                                          .activeInActiveApp, .inVisibleRect],
                                owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    private var field: CGRect { bounds.insetBy(dx: 22, dy: 22) }
    private var fieldSize: HuntSize {
        .init(width: Double(field.width), height: Double(field.height))
    }

    func clearTrail() {
        trail.removeAll(keepingCapacity: true)
        pointer = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard field.contains(local) else {
            pointer = nil
            onPointer(nil, fieldSize)
            needsDisplay = true
            return
        }
        pointer = local
        if trail.last.map({ hypot($0.x - local.x, $0.y - local.y) > 7 }) ?? true {
            trail.append(local)
            if trail.count > 75 { trail.removeFirst() }
        }
        let normalized = HuntPoint(x: Double((local.x - field.minX) / field.width),
                                   y: Double((local.y - field.minY) / field.height))
        onPointer(normalized, fieldSize)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        onPointer(nil, fieldSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor(calibratedRed: 0.025, green: 0.038,
                                     blue: 0.060, alpha: 1).cgColor)
        context.fill(bounds)
        let field = field
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [
                                    NSColor(calibratedRed: 0.055, green: 0.10,
                                            blue: 0.15, alpha: 1).cgColor,
                                    NSColor(calibratedRed: 0.015, green: 0.035,
                                            blue: 0.055, alpha: 1).cgColor
                                  ] as CFArray, locations: [0, 1])!
        context.saveGState()
        context.clip(to: field)
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: field.minX, y: field.maxY),
                                   end: CGPoint(x: field.maxX, y: field.minY), options: [])

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.055).cgColor)
        context.setLineWidth(1)
        let spacing: CGFloat = 48
        var x = field.minX
        while x <= field.maxX {
            context.move(to: CGPoint(x: x, y: field.minY))
            context.addLine(to: CGPoint(x: x, y: field.maxY))
            x += spacing
        }
        var y = field.minY
        while y <= field.maxY {
            context.move(to: CGPoint(x: field.minX, y: y))
            context.addLine(to: CGPoint(x: field.maxX, y: y))
            y += spacing
        }
        context.strokePath()

        for (index, point) in trail.enumerated() {
            let age = Double(index + 1) / Double(max(1, trail.count))
            context.setFillColor(NSColor(calibratedRed: 0.48, green: 0.78,
                                         blue: 0.92, alpha: 0.04 + 0.21 * age).cgColor)
            let diameter: CGFloat = 2.5 + CGFloat(age) * 2
            context.fillEllipse(in: CGRect(x: point.x - diameter / 2,
                                           y: point.y - diameter / 2,
                                           width: diameter, height: diameter))
        }

        if let pointer {
            let glow = CGFloat(0.2 + 0.8 * proximity)
            context.setStrokeColor(NSColor(calibratedRed: 0.42, green: 0.84,
                                           blue: 0.98, alpha: 0.18 + 0.42 * glow).cgColor)
            context.setLineWidth(1.5)
            for radius in [CGFloat(16), 26 + 18 * glow] {
                context.strokeEllipse(in: CGRect(x: pointer.x - radius,
                                                 y: pointer.y - radius,
                                                 width: radius * 2, height: radius * 2))
            }
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: pointer.x - 2.5, y: pointer.y - 2.5,
                                           width: 5, height: 5))
        }

        if found {
            let point = CGPoint(x: field.minX + CGFloat(target.x) * field.width,
                                y: field.minY + CGFloat(target.y) * field.height)
            context.setFillColor(NSColor(calibratedRed: 0.72, green: 0.96,
                                         blue: 1, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 8, y: point.y - 8,
                                           width: 16, height: 16))
            context.setStrokeColor(NSColor.cyan.withAlphaComponent(0.68).cgColor)
            context.setLineWidth(2)
            for radius: CGFloat in [24, 42, 64] {
                context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                 width: radius * 2, height: radius * 2))
            }
        }
        context.restoreGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(1)
        context.stroke(field)
    }
}

struct HuntCanvasView: NSViewRepresentable {
    let target: HuntPoint
    let found: Bool
    let proximity: Double
    let round: Int
    let onPointer: (HuntPoint?, HuntSize) -> Void

    final class Coordinator { var round = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> HuntCanvas { HuntCanvas(frame: .zero) }

    func updateNSView(_ view: HuntCanvas, context: Context) {
        view.target = target
        view.found = found
        view.proximity = proximity
        view.onPointer = onPointer
        if context.coordinator.round != round {
            view.clearTrail()
            context.coordinator.round = round
        }
        view.needsDisplay = true
    }
}
