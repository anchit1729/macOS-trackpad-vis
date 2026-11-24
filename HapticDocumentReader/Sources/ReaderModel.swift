import AppKit
import SwiftUI

@MainActor
final class ReaderModel: ObservableObject {
    @Published var hapticsEnabled = false {
        didSet {
            if hapticsEnabled { output.enable(); startPlayback() }
            else { stopPlayback(); output.disable() }
            outputStatus = output.status
        }
    }
    @Published var strength = 0.38
    @Published private(set) var outputStatus = "Off"

    let document = ReaderDocument.example
    private let output = ReaderTrackpadOutput()
    private var cue: HiddenCue?
    private var playbackTask: Task<Void, Never>?
    private var activityAt = 0.0
    private var generation = 0
    private var appActive = true

    func hover(characterIndex: Int?) {
        let found = characterIndex.flatMap { document.cue(at: $0) }
        if found != cue {
            cue = found
            activityAt = ProcessInfo.processInfo.systemUptime
            stopPlayback()
            startPlayback()
        } else if found != nil {
            activityAt = ProcessInfo.processInfo.systemUptime
            if playbackTask == nil { startPlayback() }
        }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if !active { cue = nil; stopPlayback() }
    }

    func stopOutput() {
        stopPlayback()
        output.disable()
    }

    private func startPlayback() {
        guard hapticsEnabled, appActive, let cue else { return }
        let token = generation
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var next = clock.now
            let start = ProcessInfo.processInfo.systemUptime
            var lastTap = -1.0
            while !Task.isCancelled, generation == token, self.cue == cue {
                let now = ProcessInfo.processInfo.systemUptime
                if now - activityAt > 1.6 { break }
                let elapsed = now - start
                if let frame = ConnotationPattern.frame(for: cue.kind, seconds: elapsed,
                                                        strength: strength) {
                    let interval = cue.kind == .urgency ? 0.23 : 0.48
                    let fallbackTap = elapsed - lastTap >= interval &&
                        frame.level >= strength * (cue.kind == .urgency ? 0.5 : 0.22)
                    if fallbackTap { lastTap = elapsed }
                    output.play(frame, fallbackTap: fallbackTap)
                }
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
