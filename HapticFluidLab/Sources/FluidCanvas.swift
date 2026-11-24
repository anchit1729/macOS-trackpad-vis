import AppKit
import SwiftUI

@MainActor
final class FluidCanvas: NSView {
    private let engine = FluidEngine()
    private var snapshot: FluidSnapshot?
    var scene: FluidScene = .damBreak
    var resetVersion = 0
    var flipRatio = 0.88
    var playing = true
    var showGrid = false
    var showVectors = false
    var onSample: (LocalFluidSample?) -> Void = { _ in }
    var onFPS: (Double) -> Void = { _ in }

    private nonisolated(unsafe) var timer: Timer?
    private var tracking: NSTrackingArea?
    private var pointer: Vector2?
    private var previousDrag: Vector2?
    private var pendingStirs: [StirEvent] = []
    private var stepInFlight = false
    private var lastFrameTime: TimeInterval?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    deinit { timer?.invalidate() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited,
                         .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    func setScene(_ newScene: FluidScene) {
        guard newScene != scene else { return }
        scene = newScene
        snapshot = nil
        onSample(nil)
    }

    private func tick() {
        guard !stepInFlight else { return }
        stepInFlight = true
        let stirs = pendingStirs
        pendingStirs.removeAll(keepingCapacity: true)
        let scene = scene
        let resetVersion = resetVersion
        let playing = playing
        let flipRatio = flipRatio
        Task { [weak self] in
            guard let self else { return }
            let frame = await engine.advance(scene: scene, resetVersion: resetVersion,
                                             playing: playing, flipRatio: flipRatio, stirs: stirs)
            snapshot = frame
            stepInFlight = false
            let now = ProcessInfo.processInfo.systemUptime
            if let lastFrameTime {
                onFPS(min(30, 1 / max(0.001, now - lastFrameTime)))
            }
            lastFrameTime = now
            samplePointer()
            needsDisplay = true
        }
    }

    private func samplePointer() {
        onSample(pointer.flatMap { snapshot?.localEnergy(near: $0) })
    }

    private func location(for event: NSEvent) -> Vector2? {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local), bounds.width > 0, bounds.height > 0 else { return nil }
        let rect = tankRect
        guard rect.contains(local) else { return nil }
        return .init(x: Double((local.x - rect.minX) / rect.width),
                     y: Double((local.y - rect.minY) / rect.width))
    }

    private var tankRect: CGRect {
        let width = min(bounds.width - 24, (bounds.height - 24) / 0.75)
        let height = width * 0.75
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                      width: width, height: height)
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = location(for: event)
        samplePointer()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        previousDrag = nil
        onSample(nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        previousDrag = location(for: event)
        pointer = previousDrag
        samplePointer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = location(for: event) else { return }
        if let previousDrag {
            pendingStirs.append(.init(point: point, movement: point - previousDrag))
        }
        previousDrag = point
        pointer = point
        samplePointer()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { previousDrag = nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.09, alpha: 1).cgColor)
        context.fill(bounds)
        let tank = tankRect
        context.setFillColor(NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.17, alpha: 1).cgColor)
        context.fill(tank)
        context.saveGState()
        context.clip(to: tank)

        if showGrid {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.07).cgColor)
            context.setLineWidth(0.5)
            for x in 0...FluidSimulation.columns {
                let px = tank.minX + CGFloat(x) / CGFloat(FluidSimulation.columns) * tank.width
                context.move(to: .init(x: px, y: tank.minY))
                context.addLine(to: .init(x: px, y: tank.maxY))
            }
            for y in 0...FluidSimulation.rows {
                let py = tank.minY + CGFloat(y) / CGFloat(FluidSimulation.rows) * tank.height
                context.move(to: .init(x: tank.minX, y: py))
                context.addLine(to: .init(x: tank.maxX, y: py))
            }
            context.strokePath()
        }

        let palettes = [
            NSColor(calibratedRed: 0.21, green: 0.57, blue: 0.88, alpha: 0.80),
            NSColor(calibratedRed: 0.30, green: 0.75, blue: 0.95, alpha: 0.88),
            NSColor(calibratedRed: 0.73, green: 0.94, blue: 1, alpha: 0.96)
        ]
        for band in 0..<palettes.count {
            context.setFillColor(palettes[band].cgColor)
            for particle in snapshot?.particles ?? [] {
                let speed = particle.velocity.length
                let particleBand = speed < 0.45 ? 0 : (speed < 1.1 ? 1 : 2)
                guard particleBand == band else { continue }
                let size: CGFloat = 3.5
                let x = tank.minX + CGFloat(particle.position.x) * tank.width
                let y = tank.minY + CGFloat(particle.position.y) * tank.width
                context.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2,
                                               width: size, height: size))
            }
        }

        if showVectors {
            context.setStrokeColor(NSColor.cyan.withAlphaComponent(0.40).cgColor)
            context.setLineWidth(1)
            for arrow in snapshot?.arrows ?? [] {
                let origin = CGPoint(x: tank.minX + CGFloat(arrow.point.x) * tank.width,
                                     y: tank.minY + CGFloat(arrow.point.y) * tank.width)
                context.move(to: origin)
                context.addLine(to: CGPoint(x: origin.x + CGFloat(arrow.velocity.x) * 14,
                                            y: origin.y + CGFloat(arrow.velocity.y) * 14))
            }
            context.strokePath()
        }

        if let pointer {
            let point = CGPoint(x: tank.minX + CGFloat(pointer.x) * tank.width,
                                y: tank.minY + CGFloat(pointer.y) * tank.width)
            let radius = tank.width * 0.08
            let energy = snapshot?.localEnergy(near: pointer)
            context.setStrokeColor(NSColor.white.withAlphaComponent(
                (energy?.particleCount ?? 0) > 0 ? 0.60 : 0.20).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                             width: radius * 2, height: radius * 2))
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5,
                                           width: 5, height: 5))
        }
        context.restoreGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(1)
        context.stroke(tank)
    }
}

struct FluidCanvasView: NSViewRepresentable {
    let scene: FluidScene
    let playing: Bool
    let flipRatio: Double
    let showGrid: Bool
    let showVectors: Bool
    let resetVersion: Int
    let onSample: (LocalFluidSample?) -> Void
    let onFPS: (Double) -> Void

    func makeNSView(context: Context) -> FluidCanvas { FluidCanvas(frame: .zero) }

    func updateNSView(_ view: FluidCanvas, context: Context) {
        view.onSample = onSample
        view.onFPS = onFPS
        view.setScene(scene)
        view.playing = playing
        view.flipRatio = flipRatio
        view.showGrid = showGrid
        view.showVectors = showVectors
        view.resetVersion = resetVersion
        view.needsDisplay = true
    }
}
