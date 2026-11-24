import AppKit
import CoreFoundation
import Darwin

/// Uses the private MultitouchSupport waveform interface demonstrated by nospeaker.
/// Output starts only after the user enables haptics. Public API fallback gives sparse taps.
@MainActor
final class FluidTrackpadOutput {
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
    private var target: HapticResponse?
    private var generation = 0
    private(set) var status = "Off"

    func enable() {
        guard library == nil else { return }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW
        ) else {
            status = "Standard taps only"
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
            status = "Standard taps only"
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
        status = "Standard taps only"
    }

    func update(_ response: HapticResponse?) {
        target = response
        if response == nil { stop(); return }
        guard renderTask == nil else { return }
        let token = generation
        renderTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var next = clock.now
            var smoothed = 0.0
            var fallbackTicks = 0
            var elapsed = 0.0
            while !Task.isCancelled, generation == token, let response = target {
                smoothed += (response.level - smoothed) * 0.28
                if motor != nil {
                    let frame = FluidHapticMapping.frame(for: response, at: elapsed)
                    let ratio = response.level > 0 ? smoothed / response.level : 0
                    actuate(frame, level: frame.level * ratio)
                } else if fallbackTicks % 35 == 0 {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
                fallbackTicks += 1
                elapsed += 0.012
                next = next.advanced(by: .milliseconds(12))
                if clock.now > next.advanced(by: .milliseconds(30)) { next = clock.now }
                try? await clock.sleep(until: next)
            }
            if generation == token { renderTask = nil }
        }
    }

    func stop() {
        generation += 1
        target = nil
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

    private func actuate(_ frame: FluidHapticFrame, level: Double) {
        guard let motor, let createWave, let playWave else { return }
        let duration = 12.0
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": duration],
            "Tones": frame.tones.map { tone in
                ["Type": "Sine", "Amplitude": tone.weight, "DurationMS": duration,
                 "DelayMS": 0.0, "FrequencykHz": tone.hertz / 1_000] as [String: Any]
            }
        ]
        guard let wave = createWave(shape as CFDictionary, 0) else { return }
        let pointer = Unmanaged.passUnretained(motor as AnyObject).toOpaque()
        _ = playWave(wave, pointer, 0, Float(min(0.55, max(0, level))), 0)
        Unmanaged<AnyObject>.fromOpaque(wave).release()
    }
}
