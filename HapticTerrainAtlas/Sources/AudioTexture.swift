import Foundation

struct PCMTexture {
    static let sampleRate = 16_000
    let samples: [Float]
}

private struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(UInt32(truncatingIfNeeded: state >> 32)) / Double(UInt32.max) * 2 - 1
    }
}

private struct TextureVoice {
    let frequency: Double
    let level: Double
    let sweep: Double
    let rate: Double
    let rise: Double

    init(_ frequency: Double, _ level: Double, sweep: Double = 0, rate: Double = 0, rise: Double = 0) {
        self.frequency = frequency
        self.level = level
        self.sweep = sweep
        self.rate = rate
        self.rise = rise
    }
}

private struct TextureStrike {
    let time: Double
    let frequency: Double
    let level: Double
    let decay: Double
}

private enum NoiseColour { case low, high, white }

private struct TextureRecipe {
    let duration: Double
    let voices: [TextureVoice]
    let noiseLevel: Double
    let noiseColour: NoiseColour
    let pulseRate: Double
    let pulseDepth: Double
    let strikes: [TextureStrike]

    init(_ duration: Double, voices: [TextureVoice], noise: Double = 0,
         colour: NoiseColour = .high, pulseRate: Double = 0,
         pulseDepth: Double = 0, strikes: [TextureStrike] = []) {
        self.duration = duration
        self.voices = voices
        noiseLevel = noise
        noiseColour = colour
        self.pulseRate = pulseRate
        self.pulseDepth = pulseDepth
        self.strikes = strikes
    }

    static func make(_ kind: CueKind, variation: Int) -> TextureRecipe {
        let shift = Double(variation % 3) * 20
        let index = CueKind.allCases.firstIndex(of: kind) ?? 0
        var random = SeededNoise(seed: UInt64(variation + 1) &* 7_919 &+ UInt64(index))
        func scatter(_ count: Int, duration: Double, band: ClosedRange<Double>,
                     level: Double, decay: Double) -> [TextureStrike] {
            (0..<count).map { number in
                let slot = duration / Double(count)
                let time = (Double(number) + 0.35 + random.next() * 0.12) * slot
                let frequency = band.lowerBound + (random.next() + 1) / 2
                    * (band.upperBound - band.lowerBound)
                return TextureStrike(time: time, frequency: frequency + shift,
                                     level: level, decay: decay)
            }
        }

        switch kind {
        case .lowland:
            return .init(0.5, voices: [.init(120 + shift, 0.62, sweep: 12, rate: 2),
                                       .init(240 + shift, 0.25)], noise: 0.02,
                         colour: .low, pulseRate: 2, pulseDepth: 0.12)
        case .incline:
            return .init(0.5, voices: [.init(160 + shift, 0.56, rise: 470),
                                       .init(420 + shift, 0.23, rise: 430)],
                         noise: 0.07, pulseRate: 2, pulseDepth: 0.18)
        case .ridge:
            return .init(0.5, voices: [.init(145 + shift, 0.44, sweep: 85, rate: 2),
                                       .init(780 + shift, 0.27, sweep: 250, rate: 2)],
                         noise: 0.12, pulseRate: 2, pulseDepth: 0.22)
        case .cliff:
            return .init(0.7, voices: [.init(350 + shift, 0.25, rise: -230)],
                         noise: 0.10, strikes: [
                            .init(time: 0.11, frequency: 2_300 + shift, level: 0.88, decay: 75),
                            .init(time: 0.12, frequency: 105, level: 0.78, decay: 12)])
        case .basin:
            return .init(0.6, voices: [.init(105 + shift, 0.57, sweep: 15, rate: 1.7),
                                       .init(325 + shift, 0.17)], noise: 0.07,
                         colour: .low, pulseRate: 1.7, pulseDepth: 0.43)
        case .clear:
            return .init(0.5, voices: [.init(390 + shift, 0.60),
                                       .init(860 + shift, 0.23)],
                         pulseRate: 2, pulseDepth: 0.12)
        case .cloudy:
            return .init(0.6, voices: [.init(185 + shift, 0.49),
                                       .init(460 + shift, 0.13)], noise: 0.10,
                         colour: .low, pulseRate: 1.7, pulseDepth: 0.22)
        case .fog:
            return .init(0.7, voices: [.init(230 + shift, 0.38, sweep: 45, rate: 1.4),
                                       .init(710 + shift, 0.11)], noise: 0.08,
                         colour: .low, pulseRate: 1.4, pulseDepth: 0.70)
        case .drizzle:
            return .init(0.6, voices: [.init(225 + shift, 0.11)], noise: 0.08,
                         strikes: scatter(5, duration: 0.6, band: 1_500...2_600,
                                          level: 0.42, decay: 95))
        case .rain:
            return .init(0.5, voices: [.init(260 + shift, 0.16)], noise: 0.14,
                         strikes: scatter(10, duration: 0.5, band: 1_200...3_100,
                                          level: 0.68, decay: 65))
        case .downpour:
            return .init(0.5, voices: [.init(280 + shift, 0.15), .init(650 + shift, 0.10)],
                         noise: 0.32, colour: .white,
                         strikes: scatter(20, duration: 0.5, band: 1_400...3_700,
                                          level: 0.65, decay: 72))
        case .snow:
            return .init(0.6, voices: [.init(280 + shift, 0.14), .init(1_100 + shift, 0.09)],
                         noise: 0.12,
                         strikes: scatter(7, duration: 0.6, band: 1_800...3_400,
                                          level: 0.26, decay: 120))
        case .wind:
            return .init(0.6, voices: [.init(350 + shift, 0.48, sweep: 240, rate: 1.7),
                                       .init(1_050 + shift, 0.30, sweep: 390, rate: 1.7)],
                         noise: 0.12, colour: .low, pulseRate: 1.7, pulseDepth: 0.42)
        case .gust:
            return .init(0.7, voices: [.init(320 + shift, 0.55, sweep: 280, rate: 2.7),
                                       .init(1_220 + shift, 0.24, sweep: 350, rate: 2.7)],
                         noise: 0.20, pulseRate: 2.7, pulseDepth: 0.78)
        case .thunder:
            return .init(1.2, voices: [.init(105 + shift, 0.40, sweep: 28, rate: 0.8),
                                       .init(290 + shift, 0.14)], noise: 0.12,
                         colour: .low, pulseRate: 0.8, pulseDepth: 0.32,
                         strikes: [.init(time: 0.15, frequency: 2_450 + shift, level: 0.95, decay: 90),
                                   .init(time: 0.17, frequency: 100, level: 0.85, decay: 5)])
        case .frost:
            return .init(0.7, voices: [.init(430 + shift, 0.22), .init(1_600 + shift, 0.11)],
                         noise: 0.08,
                         strikes: scatter(8, duration: 0.7, band: 2_300...3_600,
                                          level: 0.48, decay: 120))
        case .heat:
            return .init(0.6, voices: [.init(520 + shift, 0.50, sweep: 85, rate: 5),
                                       .init(1_450 + shift, 0.19, sweep: 250, rate: 3)],
                         noise: 0.07, pulseRate: 5, pulseDepth: 0.35)
        }
    }
}

enum AudioTextureSynthesizer {
    static func make(kind: CueKind, variation: Int) -> PCMTexture {
        let recipe = TextureRecipe.make(kind, variation: variation)
        let count = Int(recipe.duration * Double(PCMTexture.sampleRate))
        let sampleRate = Double(PCMTexture.sampleRate)
        let index = CueKind.allCases.firstIndex(of: kind) ?? 0
        var random = SeededNoise(seed: UInt64(variation + 1) &* 13_337 &+ UInt64(index))
        var phases = [Double](repeating: 0, count: recipe.voices.count)
        var smoothedNoise = 0.0
        var samples = [Float](repeating: 0, count: count)
        for sampleIndex in samples.indices {
            let time = Double(sampleIndex) / sampleRate
            let progress = time / recipe.duration
            var value = 0.0
            for voiceIndex in recipe.voices.indices {
                let voice = recipe.voices[voiceIndex]
                let frequency = min(3_900, max(90, voice.frequency + voice.rise * progress
                    + voice.sweep * sin(2 * .pi * voice.rate * time)))
                phases[voiceIndex] += 2 * .pi * frequency / sampleRate
                value += voice.level * sin(phases[voiceIndex])
            }
            let white = random.next()
            smoothedNoise = 0.95 * smoothedNoise + 0.05 * white
            let coloured: Double = switch recipe.noiseColour {
            case .low: smoothedNoise
            case .high: white - smoothedNoise
            case .white: white
            }
            value += recipe.noiseLevel * coloured
            if recipe.pulseDepth > 0 {
                let wave = (1 + sin(2 * .pi * recipe.pulseRate * time - .pi / 2)) / 2
                value *= 1 - recipe.pulseDepth + recipe.pulseDepth * wave
            }
            for strike in recipe.strikes {
                let age = time - strike.time
                if age >= 0 && age < 6 / strike.decay {
                    value += strike.level * exp(-strike.decay * age)
                        * sin(2 * .pi * strike.frequency * age)
                }
            }
            samples[sampleIndex] = Float(value)
        }
        let peak = max(0.001, samples.map { abs($0) }.max() ?? 1)
        return PCMTexture(samples: samples.map { $0 * 0.85 / peak })
    }
}
