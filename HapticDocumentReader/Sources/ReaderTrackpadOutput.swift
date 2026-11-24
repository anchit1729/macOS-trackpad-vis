import AppKit
import CoreFoundation
import Darwin

/// This private motor bridge follows the MIT-licensed nospeaker example.
@MainActor
final class ReaderTrackpadOutput {
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
    private(set) var status = "Off"
    var usesExpressiveMotor: Bool { motor != nil }

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
        var candidates: [(id: UInt64, builtIn: Bool)] = []
        for index in 0..<CFArrayGetCount(devices) {
            guard let value = CFArrayGetValueAtIndex(devices, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            var id: UInt64 = 0
            if getID(device, &id) == 0 { candidates.append((id, builtIn?(device) ?? false)) }
        }
        for candidate in candidates.sorted(by: { $0.builtIn && !$1.builtIn }) {
            guard let actuator = makeMotor(candidate.id)?.takeRetainedValue() else { continue }
            if openMotor(actuator) == 0 {
                motor = actuator
                closeMotor = symbol("MTActuatorClose", as: MotorClose.self)
                createWave = makeWave
                playWave = play
                status = "Expressive trackpad ready"
                return
            }
        }
        status = "Standard taps only"
    }

    func play(_ frame: ReaderHapticFrame, fallbackTap: Bool) {
        guard let motor, let createWave, let playWave else {
            if fallbackTap {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            return
        }
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
        _ = playWave(wave, pointer, 0, Float(min(0.50, max(0, frame.level))), 0)
        Unmanaged<AnyObject>.fromOpaque(wave).release()
    }

    func disable() {
        if let motor { _ = closeMotor?(motor) }
        motor = nil
        createWave = nil
        playWave = nil
        if let library { dlclose(library) }
        library = nil
        status = "Off"
    }
}
