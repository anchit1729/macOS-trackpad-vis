import XCTest
@testable import HapticCompassHunt

final class HuntCueTests: XCTestCase {
    private let size = HuntSize(width: 1_000, height: 700)
    private let target = HuntPoint(x: 0.7, y: 0.6)

    func testNearerCursorGetsStrongerFasterCue() {
        let far = HuntCueMapping.cue(cursor: .init(x: 0.1, y: 0.1),
                                     target: target, size: size)!
        let near = HuntCueMapping.cue(cursor: .init(x: 0.65, y: 0.57),
                                      target: target, size: size)!
        XCTAssertGreaterThan(near.level, far.level)
        XCTAssertLessThan(near.cycleMilliseconds, far.cycleMilliseconds)
        XCTAssertLessThanOrEqual(near.level, 0.50)
    }

    func testPitchEncodesHorizontalAndVerticalSigns() {
        let rightUp = HuntCueMapping.cue(cursor: .init(x: 0.1, y: 0.1),
                                         target: target, size: size)!
        let leftDown = HuntCueMapping.cue(cursor: .init(x: 0.9, y: 0.9),
                                          target: target, size: size)!
        XCTAssertGreaterThan(rightUp.horizontalHertz, leftDown.horizontalHertz)
        XCTAssertGreaterThan(rightUp.verticalHertz, leftDown.verticalHertz)
    }

    func testAxisWeightTracksDirection() {
        let mostlyHorizontal = HuntCueMapping.cue(cursor: .init(x: 0.1, y: 0.6),
                                                  target: target, size: size)!
        XCTAssertGreaterThan(mostlyHorizontal.horizontalWeight,
                             mostlyHorizontal.verticalWeight)
    }

    func testFoundRadiusUsesScreenDistance() {
        XCTAssertTrue(HuntCueMapping.found(cursor: .init(x: 0.68, y: 0.6),
                                           target: target, size: size))
        XCTAssertFalse(HuntCueMapping.found(cursor: .init(x: 0.5, y: 0.6),
                                            target: target, size: size))
    }

    func testInvalidGeometryProducesNoCue() {
        XCTAssertNil(HuntCueMapping.cue(cursor: target, target: target,
                                        size: .init(width: 0, height: 700)))
    }

    func testContinuousTextureHasDirectionalAccentsAndBoundedLayers() {
        let cue = HuntCueMapping.cue(cursor: .init(x: 0.1, y: 0.1),
                                     target: target, size: size)!
        let horizontal = HuntTexture.frame(for: cue, at: cue.cycleMilliseconds * 0.18)
        let vertical = HuntTexture.frame(for: cue, at: cue.cycleMilliseconds * 0.65)
        XCTAssertEqual(horizontal.tones[1].hertz, cue.horizontalHertz)
        XCTAssertEqual(vertical.tones[1].hertz, cue.verticalHertz)
        for time in stride(from: 0.0, through: cue.cycleMilliseconds, by: 12) {
            let frame = HuntTexture.frame(for: cue, at: time)
            XCTAssertGreaterThan(frame.level, 0)
            XCTAssertLessThanOrEqual(frame.level, 0.50)
            XCTAssertEqual(frame.tones.count, 3)
            XCTAssertEqual(frame.tones.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
            XCTAssertTrue(frame.tones.allSatisfy { (100...4_000).contains($0.hertz) && $0.weight > 0 })
        }
    }

    func testProximityDeepensTheContinuousBody() {
        let far = HuntCueMapping.cue(cursor: .init(x: 0.1, y: 0.1),
                                     target: target, size: size)!
        let near = HuntCueMapping.cue(cursor: .init(x: 0.65, y: 0.57),
                                      target: target, size: size)!
        let farFrame = HuntTexture.frame(for: far, at: 0)
        let nearFrame = HuntTexture.frame(for: near, at: 0)
        XCTAssertGreaterThan(nearFrame.level, farFrame.level)
        XCTAssertGreaterThan(nearFrame.tones[0].hertz, farFrame.tones[0].hertz)
        XCTAssertGreaterThan(nearFrame.tones[2].hertz, farFrame.tones[2].hertz)
    }

    @MainActor
    func testFindingPointKeepsSuccessStateOnLaterPointerMoves() {
        let model = HuntGameModel(target: target, startHaptics: false)
        model.pointerMoved(target, size: size)
        XCTAssertEqual(model.phase, .found)
        model.pointerMoved(nil, size: size)
        XCTAssertEqual(model.phase, .found)
        XCTAssertNotNil(model.foundSeconds)
        model.newRound()
        XCTAssertEqual(model.round, 2)
    }
}
