import AppKit
import SwiftUI

enum HuntPhase: Equatable {
    case ready
    case searching
    case found
}

@MainActor
final class HuntGameModel: ObservableObject {
    @Published private(set) var target = HuntPoint(x: 0.5, y: 0.5)
    @Published private(set) var phase: HuntPhase = .ready
    @Published private(set) var cue: HuntCue?
    @Published private(set) var round = 1
    @Published private(set) var foundSeconds: Int?
    @Published private(set) var outputStatus = "Off"
    @Published private(set) var usesExpressiveMotor = false
    @Published var strength = 0.42 {
        didSet { updateOutput() }
    }
    @Published var hapticsEnabled = true {
        didSet {
            if hapticsEnabled { output.enable() }
            else { output.disable() }
            refreshOutputStatus()
            updateOutput()
        }
    }

    private let output = HuntHapticOutput()
    private var appActive = true
    private var startedAt: Date?
    private var lastPointer: HuntPoint?
    private var lastSize: HuntSize?

    init(target: HuntPoint? = nil, startHaptics: Bool = true) {
        self.target = target ?? Self.pickTarget(awayFrom: nil)
        hapticsEnabled = startHaptics
        if startHaptics { output.enable() }
        refreshOutputStatus()
    }

    private func refreshOutputStatus() {
        outputStatus = output.status
        usesExpressiveMotor = output.usesExpressiveMotor
    }

    func pointerMoved(_ pointer: HuntPoint?, size: HuntSize) {
        lastPointer = pointer
        lastSize = size
        if phase == .found { return }
        guard let pointer else {
            cue = nil
            output.stop()
            return
        }
        if startedAt == nil { startedAt = Date() }
        if HuntCueMapping.found(cursor: pointer, target: target, size: size) {
            phase = .found
            cue = nil
            foundSeconds = max(1, Int(Date().timeIntervalSince(startedAt ?? Date())))
            if hapticsEnabled, appActive { output.found() }
            else { output.stop() }
            return
        }
        phase = .searching
        cue = HuntCueMapping.cue(cursor: pointer, target: target, size: size)
        updateOutput()
    }

    func newRound() {
        let oldTarget = target
        target = Self.pickTarget(awayFrom: lastPointer ?? oldTarget)
        round += 1
        phase = .ready
        cue = nil
        foundSeconds = nil
        startedAt = nil
        output.stop()
        if let lastPointer, let lastSize { pointerMoved(lastPointer, size: lastSize) }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        updateOutput()
    }

    func stopOutput() { output.stop() }

    private func updateOutput() {
        guard hapticsEnabled, appActive, phase == .searching else {
            output.stop()
            return
        }
        output.update(cue, strength: strength)
    }

    private static func pickTarget(awayFrom point: HuntPoint?) -> HuntPoint {
        for _ in 0..<30 {
            let next = HuntPoint(x: Double.random(in: 0.12...0.88),
                                 y: Double.random(in: 0.12...0.88))
            guard let point else { return next }
            if hypot(next.x - point.x, next.y - point.y) > 0.28 { return next }
        }
        return HuntPoint(x: 0.25, y: 0.75)
    }
}
