import Foundation

struct BeatPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct BeatTarget: Equatable, Sendable {
    let number: Int
    let centre: BeatPoint
    let time: Double
}

struct BeatGuidance: Equatable, Sendable {
    let proximity: Double
    let horizontal: Double
    let vertical: Double
}

enum BeatMode: String, CaseIterable, Sendable {
    case guide = "Guide"
    case augment = "Augment"
}

enum BeatJudgement: Equatable, Sendable {
    case perfect
    case good

    var points: Int { self == .perfect ? 100 : 50 }
    var label: String { self == .perfect ? "PERFECT" : "GOOD" }
}

enum BeatSequence {
    static let targets: [BeatTarget] = {
        let positions: [BeatPoint] = [
            .init(x: 0.25, y: 0.68), .init(x: 0.51, y: 0.48),
            .init(x: 0.78, y: 0.66), .init(x: 0.65, y: 0.29),
            .init(x: 0.34, y: 0.33), .init(x: 0.18, y: 0.56),
            .init(x: 0.43, y: 0.73), .init(x: 0.74, y: 0.50),
            .init(x: 0.55, y: 0.25), .init(x: 0.27, y: 0.45),
            .init(x: 0.52, y: 0.61), .init(x: 0.82, y: 0.30),
            .init(x: 0.61, y: 0.74), .init(x: 0.36, y: 0.55),
            .init(x: 0.20, y: 0.27), .init(x: 0.67, y: 0.48)
        ]
        return positions.enumerated().map { index, point in
            .init(number: index + 1, centre: point, time: 1.6 + Double(index) * 0.86)
        }
    }()

    static func judge(cursor: BeatPoint, target: BeatTarget, time: Double,
                      width: Double, height: Double) -> BeatJudgement? {
        guard width > 0, height > 0, time.isFinite else { return nil }
        let distance = hypot((cursor.x - target.centre.x) * width,
                             (cursor.y - target.centre.y) * height)
        let timing = abs(time - target.time)
        guard distance <= 38, timing <= 0.18 else { return nil }
        return timing <= 0.07 ? .perfect : .good
    }

    static func guidance(cursor: BeatPoint?, target: BeatTarget,
                         width: Double, height: Double) -> BeatGuidance? {
        guard let cursor, width > 0, height > 0 else { return nil }
        let distance = hypot((cursor.x - target.centre.x) * width,
                             (cursor.y - target.centre.y) * height)
        let horizontal = target.centre.x - cursor.x
        let vertical = target.centre.y - cursor.y
        return .init(proximity: max(0, 1 - distance / 260),
                     horizontal: abs(horizontal) < 0.03 ? 0 : (horizontal > 0 ? 1 : -1),
                     vertical: abs(vertical) < 0.03 ? 0 : (vertical > 0 ? 1 : -1))
    }
}

struct BeatTone: Equatable, Sendable {
    let hertz: Double
    let weight: Double
}

struct BeatFrame: Equatable, Sendable {
    let level: Double
    let tones: [BeatTone]
}

enum BeatTexture {
    static func frame(mode: BeatMode, guidance: BeatGuidance?, secondsToBeat: Double,
                      strength: Double) -> BeatFrame? {
        guard secondsToBeat.isFinite, strength.isFinite else { return nil }
        let cap = min(0.50, max(0, strength))
        guard cap > 0, secondsToBeat > -0.18, secondsToBeat < 1.1 else { return nil }
        let approach = max(0, 1 - max(0, secondsToBeat) / 1.1)
        let pulse = pow(max(0, cos(2 * .pi * secondsToBeat * (2.2 + 2.8 * approach))), 8)
        switch mode {
        case .guide:
            let near = min(1, max(0, guidance?.proximity ?? 0))
            let axisPhase = abs(secondsToBeat).truncatingRemainder(dividingBy: 0.36)
            let horizontalWeight = axisPhase < 0.18 ? 0.29 : 0.12
            let verticalWeight = axisPhase < 0.18 ? 0.12 : 0.29
            return .init(level: cap * (0.10 + 0.52 * near + 0.28 * pulse * approach), tones: [
                .init(hertz: 170 + 250 * near, weight: 0.49),
                .init(hertz: 530 + 110 * (guidance?.horizontal ?? 0), weight: horizontalWeight),
                .init(hertz: 920 + 130 * (guidance?.vertical ?? 0), weight: verticalWeight),
                .init(hertz: 1_480, weight: 0.10)
            ])
        case .augment:
            return .init(level: cap * (0.025 + 0.75 * pulse * approach), tones: [
                .init(hertz: 360, weight: 0.30),
                .init(hertz: 880 + 260 * approach, weight: 0.48),
                .init(hertz: 1_500, weight: 0.22)
            ])
        }
    }

    static func result(_ judgement: BeatJudgement?, seconds: Double,
                       strength: Double) -> BeatFrame? {
        guard seconds >= 0, seconds < 0.22 else { return nil }
        let cap = min(0.50, max(0, strength))
        let decay = exp(-13 * seconds)
        if judgement == .perfect {
            return .init(level: cap * (0.25 + 0.75 * decay), tones: [
                .init(hertz: 320 + 800 * min(1, seconds / 0.18), weight: 0.6),
                .init(hertz: 1_360, weight: 0.4)
            ])
        }
        if judgement == .good {
            return .init(level: cap * (0.18 + 0.62 * decay), tones: [
                .init(hertz: 270, weight: 0.75), .init(hertz: 710, weight: 0.25)
            ])
        }
        return .init(level: cap * 0.46 * decay, tones: [
            .init(hertz: 145, weight: 0.82), .init(hertz: 310, weight: 0.18)
        ])
    }
}
