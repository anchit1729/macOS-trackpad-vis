import AppKit
import CoreFoundation
import Darwin

/// Private waveform calls follow the MIT-licensed nospeaker example.
/// The public fallback uses tap counts to encode direction.
@MainActor
final class HuntHapticOutput {
    private typealias DeviceList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias MotorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias MotorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias MotorClose = @convention(c) (CFTypeRef) -> Int32
    private typealias WaveCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    private typealias WavePlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    private var library: UnsafeMutableRawPointer?
    private var motor: CFTypeRef?
    private var closeMotor: MotorClose?
    private var createWave: WaveCreate?
    private var playWave: WavePlay?
    private var renderTask: Task<Void, Never>?
    private var cue: HuntCue?
    private var strength = 0.42
    private var generation = 0
    private(set) var status = "Off"
    var usesExpressiveMotor: Bool { motor != nil }

    func enable() {
        guard library == nil else { return }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW
        ) else {
            status = "Standard tap code"
            return
        }
        library = handle
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let list = symbol("MTDeviceCreateList", as: DeviceList.self),
              let getID = symbol("MTDeviceGetDeviceID", as: DeviceID.self),
              let makeMotor = symbol("MTActuatorCreateFromDeviceID", as: MotorCreate.self),
              let openMotor = symbol("MTActuatorOpen", as: MotorOpen.self),
              let makeWave = symbol("MTActuationCreateFromDictionary", as: WaveCreate.self),
              let play = symbol("MTActuationActuate", as: WavePlay.self),
              let devices = list()?.takeRetainedValue() else {
            status = "Standard tap code"
            return
        }
        let builtIn = symbol("MTDeviceIsBuiltIn", as: IsBuiltIn.self)
        var candidates: [(UInt64, Bool)] = []
        for index in 0..<CFArrayGetCount(devices) {
            guard let value = CFArrayGetValueAtIndex(devices, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            var id: UInt64 = 0
            if getID(device, &id) == 0 { candidates.append((id, builtIn?(device) ?? false)) }
        }
        for (id, _) in candidates.sorted(by: { $0.1 && !$1.1 }) {
            guard let candidate = makeMotor(id)?.takeRetainedValue() else { continue }
            if openMotor(candidate) == 0 {
                motor = candidate
                closeMotor = symbol("MTActuatorClose", as: MotorClose.self)
                createWave = makeWave
                playWave = play
                status = "Expressive trackpad ready"
                return
            }
        }
        status = "Standard tap code"
    }

    func update(_ newCue: HuntCue?, strength: Double) {
        cue = newCue
        self.strength = min(0.50, max(0.15, strength))
        if newCue == nil { stop(); return }
        guard renderTask == nil else { return }
        let token = generation
        renderTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var next = clock.now
            var elapsed = 0.0
            while !Task.isCancelled, generation == token, let current = cue {
                if motor != nil {
                    var frame = HuntTexture.frame(for: current, at: elapsed)
                    frame = .init(level: min(0.50, frame.level * self.strength / 0.42),
                                  tones: frame.tones)
                    actuate(frame, duration: 12)
                    elapsed += 12
                    next = next.advanced(by: .milliseconds(12))
                    if clock.now > next.advanced(by: .milliseconds(30)) { next = clock.now }
                    try? await clock.sleep(until: next)
                } else {
                    let start = clock.now
                    await pulse(positive: current.horizontalHertz > 300)
                    try? await clock.sleep(until: start.advanced(by: .milliseconds(
                        Int(current.cycleMilliseconds * 0.46))))
                    guard !Task.isCancelled else { break }
                    await pulse(positive: current.verticalHertz > 400)
                    try? await clock.sleep(until: start.advanced(by: .milliseconds(
                        Int(current.cycleMilliseconds))))
                }
            }
            if generation == token { renderTask = nil }
        }
    }

    func found() {
        stop()
        let token = generation
        renderTask = Task { [weak self] in
            guard let self else { return }
            for (index, hertz) in [260.0, 420.0, 680.0].enumerated() {
                guard !Task.isCancelled else { break }
                if motor != nil {
                    actuate(.init(level: min(0.50, (0.38 + Double(index) * 0.04)
                                             * strength / 0.42),
                                  tones: [(hertz, 0.72), (hertz * 2.1, 0.28)]), duration: 70)
                }
                else { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
                try? await Task.sleep(for: .milliseconds(115))
            }
            if generation == token { renderTask = nil }
        }
    }

    private func pulse(positive: Bool) async {
        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(.generic, performanceTime: .now)
        if !positive {
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            performer.perform(.generic, performanceTime: .now)
        }
    }

    private func actuate(_ frame: HuntTextureFrame, duration: Double) {
        guard let motor, let createWave, let playWave else { return }
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": duration],
            "Tones": frame.tones.map { tone in
                ["Type": "Sine", "Amplitude": tone.weight, "DurationMS": duration,
                 "DelayMS": 0.0, "FrequencykHz": tone.hertz / 1_000] as [String: Any]
            }
        ]
        guard let wave = createWave(shape as CFDictionary, 0) else { return }
        let pointer = Unmanaged.passUnretained(motor as AnyObject).toOpaque()
        _ = playWave(wave, pointer, 0, Float(min(0.50, max(0, frame.level))), 0)
        Unmanaged<AnyObject>.fromOpaque(wave).release()
    }

    func stop() {
        generation += 1
        cue = nil
        renderTask?.cancel()
        renderTask = nil
    }

    func disable() {
        stop()
        if let motor { _ = closeMotor?(motor) }
        motor = nil
        createWave = nil
        playWave = nil
        if let library { dlclose(library) }
        library = nil
        status = "Off"
    }
}
