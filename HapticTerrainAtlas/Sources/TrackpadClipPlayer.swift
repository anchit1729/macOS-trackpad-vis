import AppKit
import CoreFoundation
import Darwin
import Foundation

/// Private MultitouchSupport calls follow the public MIT-licensed nospeaker example.
/// They are loaded only after the user enables map haptics.
@MainActor
final class TrackpadClipPlayer {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    private typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var motor: CFTypeRef?
    private var closeMotor: ActuatorClose?
    private var makeActuation: ActuationCreate?
    private var playActuation: ActuationPlay?
    private var task: Task<Void, Never>?
    private var activeKind: CueKind?
    private var intensity = HapticIntensity.standard
    private var clipCache: [CueKind: [Int: HapticClip]] = [:]
    private(set) var usesExpressiveMotor = false

    func enable() {
        guard handle == nil else { return }
        guard let library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else { return }
        handle = library
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let list = symbol("MTDeviceCreateList", as: CreateList.self),
              let getID = symbol("MTDeviceGetDeviceID", as: GetID.self),
              let createMotor = symbol("MTActuatorCreateFromDeviceID", as: ActuatorCreate.self),
              let openMotor = symbol("MTActuatorOpen", as: ActuatorOpen.self),
              let make = symbol("MTActuationCreateFromDictionary", as: ActuationCreate.self),
              let play = symbol("MTActuationActuate", as: ActuationPlay.self),
              let devices = list()?.takeRetainedValue() else { return }
        let isBuiltIn = symbol("MTDeviceIsBuiltIn", as: IsBuiltIn.self)
        var candidates: [(id: UInt64, builtIn: Bool)] = []
        for index in 0..<CFArrayGetCount(devices) {
            guard let value = CFArrayGetValueAtIndex(devices, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            var id: UInt64 = 0
            if getID(device, &id) == 0 { candidates.append((id, isBuiltIn?(device) ?? false)) }
        }
        for candidate in candidates.sorted(by: { $0.builtIn && !$1.builtIn }) {
            guard let actuator = createMotor(candidate.id)?.takeRetainedValue() else { continue }
            if openMotor(actuator) == 0 {
                motor = actuator
                closeMotor = symbol("MTActuatorClose", as: ActuatorClose.self)
                makeActuation = make
                playActuation = play
                usesExpressiveMotor = true
                return
            }
        }
    }

    func sustain(_ kind: CueKind, intensity: Double) {
        self.intensity = intensity
        guard activeKind != kind || task == nil else { return }
        stop()
        activeKind = kind
        let clip = cachedClip(for: kind, variation: Int.random(in: 0..<3))
        task = Task { [weak self] in
            guard let self else { return }
            await render(clip, cycles: nil)
        }
    }

    @discardableResult
    func preview(_ kind: CueKind, intensity: Double) -> Double {
        stop()
        self.intensity = intensity
        let clip = cachedClip(for: kind, variation: Int.random(in: 0..<3))
        let cycles = HapticPreviewPlan.cycles(for: clip.durationMilliseconds)
        task = Task { [weak self] in
            guard let self else { return }
            await render(clip, cycles: cycles)
        }
        return clip.durationMilliseconds * Double(cycles)
    }

    private func render(_ clip: HapticClip, cycles: Int?) async {
        if !usesExpressiveMotor {
            repeat {
                guard !Task.isCancelled else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                if cycles == nil { try? await Task.sleep(for: .seconds(1.2)) }
            } while cycles == nil && !Task.isCancelled
            return
        }
        guard !clip.frames.isEmpty else { return }
        let clock = ContinuousClock()
        var nextFrame = clock.now
        var completed = 0
        while !Task.isCancelled {
            for frame in clip.frames {
                guard !Task.isCancelled else { return }
                actuate(frame)
                nextFrame = nextFrame.advanced(by: .milliseconds(Int(frame.milliseconds)))
                if clock.now > nextFrame.advanced(by: .milliseconds(15)) {
                    nextFrame = clock.now
                }
                try? await clock.sleep(until: nextFrame)
            }
            completed += 1
            if let cycles, completed >= cycles { return }
        }
    }

    private func cachedClip(for kind: CueKind, variation: Int) -> HapticClip {
        if let clip = clipCache[kind]?[variation] { return clip }
        let clip = HapticClipLibrary.clip(for: kind, variation: variation)
        clipCache[kind, default: [:]][variation] = clip
        return clip
    }

    func stop() {
        task?.cancel()
        task = nil
        activeKind = nil
    }

    func disable() {
        stop()
        if let motor { _ = closeMotor?(motor) }
        motor = nil
        makeActuation = nil
        playActuation = nil
        usesExpressiveMotor = false
        if let handle { dlclose(handle) }
        handle = nil
    }

    private func actuate(_ frame: HapticFrame) {
        guard let motor, let makeActuation, let playActuation else { return }
        let total = max(0.001, frame.tones.reduce(0) { $0 + $1.weight })
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": frame.milliseconds],
            "Tones": frame.tones.map { ["Type": "Sine", "Amplitude": $0.weight / total,
                                      "DurationMS": frame.milliseconds, "DelayMS": 0.0,
                                      "FrequencykHz": $0.hertz / 1_000] as [String: Any] }
        ]
        guard let actuation = makeActuation(shape as CFDictionary, 0) else { return }
        let pointer = Unmanaged.passUnretained(motor as AnyObject).toOpaque()
        _ = playActuation(actuation, pointer, 0,
                          HapticIntensity.level(for: frame, intensity: intensity), 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
    }
}
