import XCTest
@testable import HapticBeatLab

final class BeatTests: XCTestCase {
    func testSequenceAndJudgementWindows() {
        let targets = BeatSequence.targets
        XCTAssertEqual(targets.count, 16)
        XCTAssertTrue(zip(targets, targets.dropFirst()).allSatisfy { $0.time < $1.time })
        let first = targets[0]
        XCTAssertEqual(BeatSequence.judge(cursor: first.centre, target: first,
                                          time: first.time, width: 800, height: 500), .perfect)
        XCTAssertEqual(BeatSequence.judge(cursor: first.centre, target: first,
                                          time: first.time + 0.12, width: 800, height: 500), .good)
        XCTAssertNil(BeatSequence.judge(cursor: first.centre, target: first,
                                        time: first.time + 0.25, width: 800, height: 500))
        XCTAssertNil(BeatSequence.judge(cursor: .init(x: 0.95, y: 0.05), target: first,
                                        time: first.time, width: 800, height: 500))
    }

    func testGuideRespondsToCursorAndAugmentDoesNot() {
        let far = BeatTexture.frame(mode: .guide,
                                    guidance: .init(proximity: 0, horizontal: -1, vertical: -1),
                                    secondsToBeat: 0.2, strength: 0.5)!
        let near = BeatTexture.frame(mode: .guide,
                                     guidance: .init(proximity: 1, horizontal: 1, vertical: 1),
                                     secondsToBeat: 0.2, strength: 0.5)!
        let augment = BeatTexture.frame(mode: .augment,
                                        guidance: .init(proximity: 1, horizontal: 1, vertical: 1),
                                        secondsToBeat: 0.2, strength: 0.5)!
        XCTAssertGreaterThan(near.level, far.level)
        XCTAssertGreaterThan(near.tones[0].hertz, far.tones[0].hertz)
        XCTAssertGreaterThan(near.tones[1].hertz, far.tones[1].hertz)
        XCTAssertGreaterThan(near.tones[2].hertz, far.tones[2].hertz)
        XCTAssertEqual(augment, BeatTexture.frame(mode: .augment, guidance: nil,
                                                   secondsToBeat: 0.2, strength: 0.5))
        XCTAssertLessThanOrEqual(near.level, 0.5)
    }

    func testResultPatternsDifferAndStayCapped() {
        let perfect = BeatTexture.result(.perfect, seconds: 0.01, strength: 0.5)!
        let good = BeatTexture.result(.good, seconds: 0.01, strength: 0.5)!
        let miss = BeatTexture.result(nil, seconds: 0.01, strength: 0.5)!
        XCTAssertNotEqual(perfect, good)
        XCTAssertNotEqual(good, miss)
        XCTAssertTrue([perfect, good, miss].allSatisfy { $0.level <= 0.5 })
        XCTAssertNil(BeatTexture.result(.perfect, seconds: 0.3, strength: 0.5))
    }
}
