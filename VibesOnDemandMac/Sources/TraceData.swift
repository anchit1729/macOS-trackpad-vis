import Foundation

struct TracePoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

enum TraceShape: String, CaseIterable, Sendable {
    case rising = "Rising"
    case falling = "Falling"
    case peak = "Peak"
    case trough = "Trough"
    case waves = "Waves"
    case plateau = "Plateau"
}

struct TraceSeries: Equatable, Identifiable, Sendable {
    let id: Int
    let position: TracePoint
    let shape: TraceShape
    let values: [Double]

    var label: String { "Point \(String(format: "%02d", id + 1))" }
}

enum TraceLibrary {
    static let series: [TraceSeries] = {
        var state: UInt64 = 29
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(UInt32(truncatingIfNeeded: state >> 32)) / Double(UInt32.max)
        }
        var points: [TraceSeries] = []
        for id in 0..<36 {
            let column = id % 9
            let row = id / 9
            let x = 0.085 + Double(column) * 0.102 + (random() - 0.5) * 0.055
            let y = 0.14 + Double(row) * 0.22 + (random() - 0.5) * 0.095
            let shape = TraceShape.allCases[(id * 5 + row) % TraceShape.allCases.count]
            let phase = random() * 2 * Double.pi
            let values = (0..<48).map { step -> Double in
                let t = Double(step) / 47
                let base: Double = switch shape {
                case .rising: 0.16 + 0.72 * t
                case .falling: 0.84 - 0.68 * t
                case .peak: 0.18 + 0.70 * exp(-pow((t - 0.52) / 0.22, 2))
                case .trough: 0.82 - 0.67 * exp(-pow((t - 0.48) / 0.21, 2))
                case .waves: 0.50 + 0.29 * sin(4 * .pi * t + phase)
                case .plateau: 0.19 + 0.58 / (1 + exp(-20 * (t - 0.38)))
                }
                return min(0.95, max(0.05, base + 0.035 * sin(17 * t + phase)))
            }
            points.append(.init(id: id, position: .init(x: x, y: y),
                                shape: shape, values: values))
        }
        return points
    }()
}

struct TraceTone: Equatable, Sendable {
    let hertz: Double
    let weight: Double
}

struct TraceHapticFrame: Equatable, Sendable {
    let level: Double
    let value: Double
    let tones: [TraceTone]
}

enum TraceHapticMapping {
    static func smooth(_ values: [Double], amount: Double) -> [Double] {
        guard let first = values.first else { return [] }
        let memory = min(0.85, max(0, amount))
        var previous = first
        return values.map { value in
            previous = previous * memory + value * (1 - memory)
            return previous
        }
    }

    static func value(in values: [Double], at progress: Double) -> Double? {
        guard !values.isEmpty, progress.isFinite else { return nil }
        let position = min(1, max(0, progress)) * Double(values.count - 1)
        let lower = Int(position)
        let upper = min(values.count - 1, lower + 1)
        let blend = position - Double(lower)
        return values[lower] * (1 - blend) + values[upper] * blend
    }

    static func frame(values: [Double], progress: Double, strength: Double) -> TraceHapticFrame? {
        guard let raw = value(in: values, at: progress), raw.isFinite,
              !values.isEmpty else { return nil }
        let y = min(1, max(0, raw))
        let step = 1 / Double(max(1, values.count - 1))
        let before = value(in: values, at: progress - step) ?? y
        let after = value(in: values, at: progress + step) ?? y
        let slope = min(1, abs(after - before) * 2.5)
        let crest = min(1, max(0, y - (before + after) / 2) * 12)
        let accentWeight = 0.06 + 0.13 * slope + 0.15 * crest
        let middleWeight = 0.30 + 0.07 * y
        let ceiling = min(0.50, max(0, strength))
        let level = ceiling * 0.25 * pow(4, y)
        return .init(level: level, value: y, tones: [
            .init(hertz: 145 + 275 * y, weight: 1 - middleWeight - accentWeight),
            .init(hertz: 430 + 610 * y, weight: middleWeight),
            .init(hertz: 1_250 + 800 * crest + 250 * slope, weight: accentWeight)
        ])
    }
}
