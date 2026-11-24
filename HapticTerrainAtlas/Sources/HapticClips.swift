import Foundation

enum MapLayer: String, CaseIterable, Identifiable {
    case terrain = "Terrain"
    case weather = "Weather"
    case both = "Both"
    var id: String { rawValue }
}

enum CueKind: String, CaseIterable, Identifiable {
    case lowland = "Lowland"
    case incline = "Incline"
    case ridge = "Ridge"
    case cliff = "Cliff"
    case basin = "Basin"
    case clear = "Clear sky"
    case cloudy = "Cloud cover"
    case fog = "Fog"
    case drizzle = "Drizzle"
    case rain = "Rain"
    case downpour = "Downpour"
    case snow = "Snow"
    case wind = "Wind"
    case gust = "Gusts"
    case thunder = "Thunder"
    case frost = "Frost"
    case heat = "Heat"
    var id: String { rawValue }

    static let terrainCases: [CueKind] = [.lowland, .incline, .ridge, .cliff, .basin]
    static let weatherCases: [CueKind] = [.clear, .cloudy, .fog, .drizzle, .rain,
                                          .downpour, .snow, .wind, .gust, .thunder, .frost, .heat]

    var description: String {
        switch self {
        case .lowland: "Rounded, low resonance"
        case .incline: "A rising sweep under the finger"
        case .ridge: "A narrow, rough crest"
        case .cliff: "A sharp drop with a hard edge"
        case .basin: "A deep, hollow echo"
        case .clear: "Open, light harmonics"
        case .cloudy: "A soft, muted blanket"
        case .fog: "Diffuse, slow pulses"
        case .drizzle: "Sparse, fine drops"
        case .rain: "Steady drops over a soft bed"
        case .downpour: "Dense splatter and a broad wash"
        case .snow: "Fine, dry grains"
        case .wind: "A smooth, moving sweep"
        case .gust: "Irregular surges"
        case .thunder: "A crack over a rolling rumble"
        case .frost: "Brittle, icy ticks"
        case .heat: "A wavering shimmer"
        }
    }

    var glyph: String {
        switch self {
        case .lowland: "•"
        case .incline: "↗"
        case .ridge: "▲"
        case .cliff: "▾"
        case .basin: "◡"
        case .clear: "☼"
        case .cloudy: "☁"
        case .fog: "≋"
        case .drizzle: "·"
        case .rain: "☂"
        case .downpour: "☔"
        case .snow: "✳"
        case .wind: "➝"
        case .gust: "➷"
        case .thunder: "ϟ"
        case .frost: "❄"
        case .heat: "☀"
        }
    }
}

struct HapticTone: Equatable {
    let hertz: Double
    let weight: Double
}

struct HapticFrame: Equatable {
    let milliseconds: Double
    let strength: Float
    let tones: [HapticTone]
}

struct HapticClip: Equatable {
    let kind: CueKind
    let frames: [HapticFrame]
    var durationMilliseconds: Double { frames.reduce(0) { $0 + $1.milliseconds } }
}

enum HapticIntensity {
    static let minimum = 0.25
    static let standard = 0.42
    static let maximum = 0.55

    static func level(for frame: HapticFrame, intensity: Double) -> Float {
        let bounded = min(maximum, max(minimum, intensity))
        return Float(bounded) * min(1, max(0, frame.strength))
    }
}

enum HapticActivityPolicy {
    static let idleSeconds: TimeInterval = 6

    static func shouldStop(lastInput: TimeInterval, now: TimeInterval) -> Bool {
        now - lastInput >= idleSeconds
    }
}

enum HapticPreviewPlan {
    static func cycles(for durationMilliseconds: Double) -> Int {
        guard durationMilliseconds > 0 else { return 0 }
        return min(3, max(1, Int(ceil(1_200 / durationMilliseconds))))
    }
}

enum HapticClipLibrary {
    static func kind(for sample: GeoSample, layer: MapLayer) -> CueKind {
        let terrain = terrainKind(for: sample)
        if layer == .terrain { return terrain }
        let weather = weatherKind(for: sample)
        if layer == .weather { return weather }
        return weather == .clear || weather == .cloudy ? terrain : weather
    }

    static func terrainKind(for sample: GeoSample) -> CueKind {
        if sample.slopeMetresPerKilometre >= 120 { return .cliff }
        if sample.reliefMetres <= -140 { return .basin }
        if sample.elevationMetres >= 1_800 && sample.reliefMetres >= 70 { return .ridge }
        if sample.slopeMetresPerKilometre >= 35 { return .incline }
        return .lowland
    }

    static func weatherKind(for sample: GeoSample) -> CueKind {
        let code = sample.weatherCode ?? -1
        if (95...99).contains(code) { return .thunder }
        if [65, 67, 82].contains(code) || sample.precipitationMillimetres >= 2 { return .downpour }
        if (71...77).contains(code) || [85, 86].contains(code)
            || (sample.snowfallCentimetres ?? 0) >= 0.1 { return .snow }
        if [61, 63, 66, 80, 81].contains(code) || sample.precipitationMillimetres >= 0.3 { return .rain }
        if (51...57).contains(code) || sample.precipitationMillimetres > 0 { return .drizzle }
        if [45, 48].contains(code) { return .fog }
        if let gust = sample.windGustKilometresPerHour,
           gust >= 45, gust - sample.windKilometresPerHour >= 15 { return .gust }
        if sample.windKilometresPerHour >= 25 { return .wind }
        if sample.temperatureCelsius <= -8 { return .frost }
        if sample.temperatureCelsius >= 30 { return .heat }
        if code == 3 || (sample.cloudCoverPercent ?? 0) >= 70 { return .cloudy }
        return .clear
    }

    static func drive(for sample: GeoSample, kind: CueKind) -> Double {
        func scaled(_ value: Double, from low: Double, to high: Double) -> Double {
            0.72 + 0.28 * min(1, max(0, (value - low) / (high - low)))
        }
        switch kind {
        case .incline, .ridge, .cliff, .basin:
            return scaled(sample.slopeMetresPerKilometre, from: 35, to: 160)
        case .drizzle, .rain, .downpour:
            return scaled(sample.precipitationMillimetres, from: 0, to: 3)
        case .snow:
            return scaled(sample.snowfallCentimetres ?? 0, from: 0, to: 2)
        case .wind:
            return scaled(sample.windKilometresPerHour, from: 25, to: 55)
        case .gust:
            return scaled(sample.windGustKilometresPerHour ?? 0, from: 45, to: 85)
        case .frost:
            return scaled(-sample.temperatureCelsius, from: 8, to: 30)
        case .heat:
            return scaled(sample.temperatureCelsius, from: 30, to: 42)
        case .thunder: return 0.9
        case .lowland, .clear, .cloudy, .fog: return 0.82
        }
    }

    static func clip(for kind: CueKind, variation: Int) -> HapticClip {
        let audio = AudioTextureSynthesizer.make(kind: kind, variation: variation)
        return AudioFrequencyEncoder.encode(audio, kind: kind)
    }
}
