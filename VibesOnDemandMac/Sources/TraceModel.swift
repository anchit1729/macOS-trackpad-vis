import AppKit
import SwiftUI

@MainActor
final class TraceModel: ObservableObject {
    @Published private(set) var selectedID: Int?
    @Published private(set) var pinned = false
    @Published private(set) var progress = 0.0
    @Published private(set) var currentValue = 0.0
    @Published private(set) var outputStatus = "Off"
    @Published private(set) var usesExpressiveMotor = false
    @Published var showLine = true
    @Published var hapticsEnabled = false {
        didSet {
            if hapticsEnabled { output.enable() }
            else { output.disable() }
            outputStatus = output.status
            usesExpressiveMotor = output.usesExpressiveMotor
        }
    }
    @Published var strength = 0.42
    @Published var duration = 1.2
    @Published var smoothing = 0.12 {
        didSet { updateSmoothedValues() }
    }

    private let output = TraceTrackpadOutput()
    private var playbackTask: Task<Void, Never>?
    private var generation = 0
    private var appActive = true
    private var pressedWasPinned = false
    private var smoothedValues: [Double] = []
    private var scrubProgress: Double?
    private var lastScrubAt = 0.0

    var selectedSeries: TraceSeries? {
        guard let selectedID else { return nil }
        return TraceLibrary.series.first { $0.id == selectedID }
    }

    func beginPress(_ id: Int) {
        guard let series = TraceLibrary.series.first(where: { $0.id == id }) else { return }
        pressedWasPinned = selectedID == id && pinned
        selectedID = series.id
        pinned = false
        progress = 0
        currentValue = series.values[0]
        scrubProgress = nil
        updateSmoothedValues()
        restartPlayback()
    }

    func endPress(quickClick: Bool) {
        guard selectedID != nil else { return }
        if quickClick && !pressedWasPinned {
            pinned = true
            return
        }
        clearSelection()
    }

    func clearSelection() {
        stopPlayback()
        selectedID = nil
        pinned = false
        scrubProgress = nil
        progress = 0
        currentValue = 0
    }

    func scrub(_ position: Double?) {
        guard pinned else { return }
        if let position {
            let bounded = min(1, max(0, position))
            scrubProgress = bounded
            lastScrubAt = ProcessInfo.processInfo.systemUptime
            progress = bounded
            currentValue = TraceHapticMapping.value(in: smoothedValues, at: bounded) ?? 0
        } else if scrubProgress != nil {
            scrubProgress = nil
        }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if active, selectedID != nil { restartPlayback() }
        else {
            stopPlayback()
            if !pinned { clearSelection() }
        }
    }

    func stopOutput() { stopPlayback(); output.disable() }

    private func updateSmoothedValues() {
        smoothedValues = selectedSeries.map {
            TraceHapticMapping.smooth($0.values, amount: smoothing)
        } ?? []
    }

    private func restartPlayback() {
        stopPlayback()
        guard appActive, selectedID != nil else { return }
        let token = generation
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var next = clock.now
            var elapsed = 0.0
            var tick = 0
            while !Task.isCancelled, generation == token, selectedID != nil {
                let span = max(0.5, min(2.5, duration)) * 1_000
                let phase = elapsed.truncatingRemainder(dividingBy: span + 240)
                let now = ProcessInfo.processInfo.systemUptime
                let scrubbing = scrubProgress != nil
                let position = scrubProgress ?? min(1, phase / span)
                let shouldPlay = scrubbing ? now - lastScrubAt < 0.18 : phase < span
                if shouldPlay {
                    if let frame = TraceHapticMapping.frame(values: smoothedValues,
                                                            progress: position, strength: strength) {
                        if hapticsEnabled { output.play(frame, fallbackTap: tick % 25 == 0) }
                        if tick % 3 == 0 {
                            progress = position
                            currentValue = frame.value
                        }
                    }
                } else if !scrubbing && tick % 3 == 0 { progress = 1 }
                tick += 1
                elapsed += 12
                next = next.advanced(by: .milliseconds(12))
                if clock.now > next.advanced(by: .milliseconds(30)) { next = clock.now }
                try? await clock.sleep(until: next)
            }
            if generation == token { playbackTask = nil }
        }
    }

    private func stopPlayback() {
        generation += 1
        playbackTask?.cancel()
        playbackTask = nil
    }
}
