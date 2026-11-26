import AppKit
import SwiftUI

@MainActor
final class BeatGameModel: ObservableObject {
    @Published private(set) var elapsed = 0.0
    @Published private(set) var targetIndex = 0
    @Published private(set) var score = 0
    @Published private(set) var combo = 0
    @Published private(set) var misses = 0
    @Published private(set) var message = "PRESS START"
    @Published private(set) var isPlaying = false
    @Published private(set) var outputStatus = "Off"
    @Published var mode: BeatMode = .guide
    @Published var strength = 0.42
    @Published var hapticsEnabled = false {
        didSet {
            if hapticsEnabled { output.enable() }
            else { output.disable() }
            outputStatus = output.status
        }
    }

    private let output = BeatTrackpadOutput()
    private var loop: Task<Void, Never>?
    private var generation = 0
    private var pointer: BeatPoint?
    private var fieldSize = CGSize(width: 800, height: 500)
    private var result: (judgement: BeatJudgement?, at: Double)?
    private var lastPulseHigh = false
    private var tickCount = 0
    private var startedAt = 0.0

    var currentTarget: BeatTarget? {
        BeatSequence.targets.indices.contains(targetIndex) ? BeatSequence.targets[targetIndex] : nil
    }

    func start() {
        stopLoop()
        elapsed = 0
        targetIndex = 0
        score = 0
        combo = 0
        misses = 0
        message = "FOLLOW THE RING"
        result = nil
        lastPulseHigh = false
        tickCount = 0
        isPlaying = true
        startedAt = ProcessInfo.processInfo.systemUptime
        let token = generation
        loop = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var next = clock.now
            var visualTick = 0
            while !Task.isCancelled, generation == token, isPlaying || result != nil {
                let now = ProcessInfo.processInfo.systemUptime
                let time = now - self.startedAt
                if visualTick % 3 == 0 { elapsed = time }
                if isPlaying, let target = currentTarget, time > target.time + 0.18 {
                    misses += 1
                    combo = 0
                    message = "MISS"
                    result = (nil, time)
                    targetIndex += 1
                    if currentTarget == nil { isPlaying = false }
                }
                if let result, time - result.at >= 0.22 { self.result = nil }
                playFrame(at: time)
                visualTick += 1
                next = next.advanced(by: .milliseconds(12))
                if clock.now > next.advanced(by: .milliseconds(30)) { next = clock.now }
                try? await clock.sleep(until: next)
            }
            if generation == token {
                elapsed = timeForFinish()
                if targetIndex == BeatSequence.targets.count { message = "ROUND COMPLETE" }
                loop = nil
            }
        }
    }

    func pointerMoved(_ point: BeatPoint?, size: CGSize) {
        pointer = point
        fieldSize = size
    }

    func attemptHit(_ point: BeatPoint, size: CGSize) {
        guard isPlaying, let target = currentTarget else { return }
        fieldSize = size
        let now = ProcessInfo.processInfo.systemUptime - startedAt
        guard let judgement = BeatSequence.judge(cursor: point, target: target, time: now,
                                                 width: size.width, height: size.height) else {
            message = abs(now - target.time) > 0.18 ? "FOLLOW THE RING" : "AIM AT THE CIRCLE"
            return
        }
        score += judgement.points * max(1, combo + 1)
        combo += 1
        message = judgement.label
        result = (judgement, now)
        targetIndex += 1
        if currentTarget == nil { isPlaying = false }
    }

    func stop() {
        stopLoop()
        isPlaying = false
        result = nil
        message = "PRESS START"
    }

    func stopOutput() {
        stop()
        output.disable()
    }

    private func playFrame(at time: Double) {
        guard hapticsEnabled else { return }
        let frame: BeatFrame?
        if let result {
            frame = BeatTexture.result(result.judgement, seconds: time - result.at,
                                       strength: strength)
        } else if let target = currentTarget, isPlaying {
            let guidance = BeatSequence.guidance(cursor: pointer, target: target,
                                                 width: fieldSize.width, height: fieldSize.height)
            frame = BeatTexture.frame(mode: mode, guidance: guidance,
                                      secondsToBeat: target.time - time, strength: strength)
        } else { frame = nil }
        guard let frame else { lastPulseHigh = false; return }
        let high = frame.level > strength * (mode == .guide ? 0.55 : 0.40)
        let fallbackTap = (result != nil && tickCount % 18 == 0) ||
            (mode == .augment && high && !lastPulseHigh) ||
            (mode == .guide && high && tickCount % 28 == 0)
        output.play(frame, fallbackTap: fallbackTap)
        lastPulseHigh = high
        tickCount += 1
    }

    private func timeForFinish() -> Double {
        BeatSequence.targets.last.map { max(elapsed, $0.time) } ?? elapsed
    }

    private func stopLoop() {
        generation += 1
        loop?.cancel()
        loop = nil
    }
}
