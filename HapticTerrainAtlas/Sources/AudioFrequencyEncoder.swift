import Foundation

enum AudioFrequencyEncoder {
    private static let windowSize = 320
    private static let hopSize = 160
    private static let taper = (0..<windowSize).map { offset in
        0.54 - 0.46 * cos(2 * .pi * Double(offset) / Double(windowSize - 1))
    }
    private static let bins = (2...80).map { bin in
        (frequency: Double(bin) * 50, coefficient: 2 * cos(2 * .pi * Double(bin) / Double(windowSize)))
    }

    static func encode(_ audio: PCMTexture, kind: CueKind) -> HapticClip {
        guard audio.samples.count >= windowSize else { return HapticClip(kind: kind, frames: []) }
        var frames: [HapticFrame] = []
        var levels: [Double] = []
        for start in stride(from: 0, to: audio.samples.count, by: hopSize) {
            var window = [Double](repeating: 0, count: windowSize)
            var energy = 0.0
            for offset in 0..<windowSize {
                let sample = Double(audio.samples[(start + offset) % audio.samples.count])
                window[offset] = sample * taper[offset]
                if offset < hopSize { energy += sample * sample }
            }
            let powers = bins.map { bin in
                (frequency: bin.frequency, power: power(in: window, coefficient: bin.coefficient))
            }.sorted { $0.power > $1.power }
            guard let strongest = powers.first, strongest.power > 1e-8 else { continue }
            levels.append(sqrt(energy / Double(hopSize)))
            let second = powers.dropFirst().first { abs($0.frequency - strongest.frequency) >= 200 }
            let firstWeight = sqrt(strongest.power)
            let secondWeight = sqrt(second?.power ?? 0)
            let total = max(1e-9, firstWeight + secondWeight)
            var tones = [HapticTone(hertz: strongest.frequency, weight: firstWeight / total)]
            if let second { tones.append(HapticTone(hertz: second.frequency, weight: secondWeight / total)) }
            frames.append(HapticFrame(milliseconds: 10, strength: 0, tones: tones))
        }
        let peak = max(1e-9, levels.max() ?? 0)
        for index in frames.indices {
            let relative = levels[index] / peak
            frames[index] = HapticFrame(milliseconds: 10,
                                        strength: Float(min(1, max(0.5, pow(relative, 0.55)))),
                                        tones: frames[index].tones)
        }
        return HapticClip(kind: kind, frames: frames)
    }

    private static func power(in samples: [Double], coefficient: Double) -> Double {
        var previous = 0.0
        var older = 0.0
        for sample in samples {
            let next = sample + coefficient * previous - older
            older = previous
            previous = next
        }
        return max(0, previous * previous + older * older - coefficient * previous * older)
    }
}
