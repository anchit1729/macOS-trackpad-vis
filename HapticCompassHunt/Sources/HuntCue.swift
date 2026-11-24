import Foundation

struct HuntPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct HuntSize: Equatable, Sendable {
    let width: Double
    let height: Double
}

struct HuntCue: Equatable, Sendable {
    let distancePixels: Double
    let proximity: Double
    let level: Double
    let cycleMilliseconds: Double
    let horizontalWeight: Double
    let verticalWeight: Double
    let horizontalHertz: Double
    let verticalHertz: Double
}

struct HuntTextureFrame: Equatable {
    let level: Double
    let tones: [(hertz: Double, weight: Double)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.level == rhs.level && lhs.tones.count == rhs.tones.count &&
        zip(lhs.tones, rhs.tones).allSatisfy {
            $0.hertz == $1.hertz && $0.weight == $1.weight
        }
    }
}

enum HuntTexture {
    /// A continuous proximity bed carries two directional accents each cycle.
    static func frame(for cue: HuntCue, at milliseconds: Double) -> HuntTextureFrame {
        let cycle = max(1, cue.cycleMilliseconds)
        let phase = (milliseconds.isFinite ? max(0, milliseconds) : 0)
            .truncatingRemainder(dividingBy: cycle) / cycle
        func pulse(at centre: Double) -> Double {
            let distance = abs(phase - centre)
            return exp(-pow(distance / 0.075, 2))
        }
        let horizontal = pulse(at: 0.18) * cue.horizontalWeight
        let vertical = pulse(at: 0.65) * cue.verticalWeight
        let accent = max(horizontal, vertical)
        let ripple = 0.5 + 0.5 * sin(2 * .pi * phase * 3)
        let proximity = min(1, max(0, cue.proximity))
        let bodyHz = 110 + 45 * proximity + 8 * sin(2 * .pi * phase)
        let directionHz = horizontal >= vertical ? cue.horizontalHertz : cue.verticalHertz
        let directionWeight = 0.08 + 0.53 * accent
        let glintWeight = 0.05 + 0.13 * proximity * ripple
        let bodyWeight = 1 - directionWeight - glintWeight
        return .init(level: min(0.50, cue.level * (0.72 + 0.22 * accent + 0.06 * ripple)),
                     tones: [(bodyHz, bodyWeight),
                             (directionHz, directionWeight),
                             (1_400 + 800 * proximity + 110 * ripple, glintWeight)])
    }
}

enum HuntCueMapping {
    static func cue(cursor: HuntPoint, target: HuntPoint, size: HuntSize) -> HuntCue? {
        guard size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite,
              cursor.x.isFinite, cursor.y.isFinite,
              target.x.isFinite, target.y.isFinite else { return nil }
        let dx = (target.x - cursor.x) * size.width
        let dy = (target.y - cursor.y) * size.height
        let distance = hypot(dx, dy)
        let reach = hypot(size.width, size.height) * 0.75
        let proximity = 1 - min(1, distance / reach)
        let directionScale = max(distance, 0.0001)
        return .init(distancePixels: distance,
                     proximity: proximity,
                     level: min(0.50, 0.16 + 0.34 * proximity * proximity),
                     cycleMilliseconds: 840 - 540 * proximity,
                     horizontalWeight: 0.32 + 0.68 * abs(dx) / directionScale,
                     verticalWeight: 0.32 + 0.68 * abs(dy) / directionScale,
                     horizontalHertz: dx >= 0 ? 600 : 220,
                     verticalHertz: dy >= 0 ? 950 : 350)
    }

    static func found(cursor: HuntPoint, target: HuntPoint, size: HuntSize) -> Bool {
        guard let cue = cue(cursor: cursor, target: target, size: size) else { return false }
        return cue.distancePixels <= max(24, min(size.width, size.height) * 0.045)
    }
}
