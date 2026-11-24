import Foundation

struct HapticResponse: Equatable {
    let metric: HapticMetric
    let level: Double
    let fundamentalHz: Double
    let shimmerHz: Double
    let accentHz: Double
    let activity: Double
}

struct FluidHapticFrame: Equatable {
    let level: Double
    let tones: [(hertz: Double, weight: Double)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.level == rhs.level && zip(lhs.tones, rhs.tones).allSatisfy {
            $0.hertz == $1.hertz && $0.weight == $1.weight
        } && lhs.tones.count == rhs.tones.count
    }
}

enum HapticMetric: String, CaseIterable, Identifiable {
    case kineticEnergy = "Motion"
    case pressure = "Pressure"

    var id: String { rawValue }
}

enum FluidHapticMapping {
    static func response(for sample: LocalFluidSample, metric: HapticMetric,
                         strength: Double) -> HapticResponse? {
        guard sample.particleCount > 0 else { return nil }
        let value: Double
        let scale: Double
        switch metric {
        case .kineticEnergy:
            value = sample.kineticEnergy
            scale = 0.65
        case .pressure:
            value = sample.pressureMagnitude
            scale = 0.45
        }
        guard value.isFinite, value > 0.002 else { return nil }
        let sensation = min(1, sqrt(max(0, value) / scale))
        let ceiling = min(0.55, max(0, strength))
        let level = ceiling * sensation
        guard level > 0.01 else { return nil }
        switch metric {
        case .kineticEnergy:
            return .init(metric: metric, level: level,
                         fundamentalHz: 125 + 145 * sensation,
                         shimmerHz: 440 + 360 * sensation,
                         accentHz: 1_250 + 950 * sensation,
                         activity: sensation)
        case .pressure:
            return .init(metric: metric, level: level,
                         fundamentalHz: 90 + 90 * sensation,
                         shimmerHz: 250 + 110 * sensation,
                         accentHz: 850 + 600 * sensation,
                         activity: sensation)
        }
    }

    /// A low body, moving mid voice, and brief high accents create depth.
    static func frame(for response: HapticResponse, at seconds: Double) -> FluidHapticFrame {
        let time = max(0, seconds.isFinite ? seconds : 0)
        let phase = 2 * Double.pi * time
        let motion = response.metric == .kineticEnergy
        let rate = motion ? 2.2 + response.activity * 2.8 : 1.6 + response.activity * 1.4
        let swell = 0.5 + 0.5 * sin(phase * rate - .pi / 2)
        let ripple = 0.5 + 0.5 * sin(phase * (rate * 2.7) + 0.8)
        let crest = pow(max(0, sin(phase * rate)), motion ? 5 : 9)
        let envelope = motion
            ? 0.66 + 0.20 * swell + 0.14 * ripple
            : 0.70 + 0.16 * swell + 0.14 * crest
        let accentWeight = motion
            ? 0.06 + 0.17 * ripple * response.activity
            : 0.05 + 0.23 * crest * response.activity
        let middleWeight = motion ? 0.26 + 0.10 * swell : 0.19 + 0.08 * crest
        let baseWeight = 1 - middleWeight - accentWeight
        return .init(level: min(0.55, response.level * envelope), tones: [
            (response.fundamentalHz + (motion ? 22 : 9) * sin(phase * rate), baseWeight),
            (response.shimmerHz + (motion ? 65 : 18) * sin(phase * rate + 0.7), middleWeight),
            (response.accentHz + 85 * ripple, accentWeight)
        ])
    }
}
