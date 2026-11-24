import XCTest
@testable import VibesOnDemandMac

final class TraceTests: XCTestCase {
    func testLibraryHasBoundedDistinctExamples() {
        let series = TraceLibrary.series
        XCTAssertEqual(series.count, 36)
        XCTAssertEqual(Set(series.map(\.id)).count, 36)
        XCTAssertEqual(Set(series.map(\.shape)).count, TraceShape.allCases.count)
        XCTAssertTrue(series.allSatisfy { $0.values.count == 48 })
        XCTAssertTrue(series.allSatisfy { point in
            (0...1).contains(point.position.x) && (0...1).contains(point.position.y) &&
            point.values.allSatisfy { (0...1).contains($0) }
        })
    }

    func testInterpolationAndSmoothing() {
        XCTAssertEqual(TraceHapticMapping.value(in: [0, 1], at: 0.25), 0.25)
        XCTAssertNil(TraceHapticMapping.value(in: [], at: 0.5))
        XCTAssertEqual(TraceHapticMapping.smooth([0, 1], amount: 0), [0, 1])
        XCTAssertEqual(TraceHapticMapping.smooth([0, 1], amount: 0.5), [0, 0.5])
    }

    func testValueChangesForceAndFrequencyWithinCap() {
        let low = TraceHapticMapping.frame(values: [0, 1], progress: 0, strength: 0.5)!
        let high = TraceHapticMapping.frame(values: [0, 1], progress: 1, strength: 0.5)!
        XCTAssertLessThan(low.level, high.level)
        XCTAssertLessThan(low.tones[0].hertz, high.tones[0].hertz)
        XCTAssertEqual(low.level, 0.125, accuracy: 0.0001)
        XCTAssertEqual(high.level, 0.5, accuracy: 0.0001)
        XCTAssertEqual(high.tones.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
        XCTAssertEqual(TraceHapticMapping.frame(values: [1], progress: 0,
                                                 strength: 10)?.level, 0.5)
    }

    func testPeakAddsHighFrequencyAccent() {
        let peak = TraceHapticMapping.frame(values: [0.2, 0.9, 0.2],
                                            progress: 0.5, strength: 0.4)!
        let flat = TraceHapticMapping.frame(values: [0.9, 0.9, 0.9],
                                            progress: 0.5, strength: 0.4)!
        XCTAssertGreaterThan(peak.tones[2].weight, flat.tones[2].weight)
        XCTAssertGreaterThan(peak.tones[2].hertz, flat.tones[2].hertz)
    }

    func testHoldPinAndScrubState() async {
        await MainActor.run {
            let model = TraceModel()
            model.beginPress(0)
            XCTAssertEqual(model.selectedID, 0)
            XCTAssertFalse(model.pinned)
            model.endPress(quickClick: true)
            XCTAssertTrue(model.pinned)
            model.scrub(0.75)
            XCTAssertEqual(model.progress, 0.75, accuracy: 0.0001)
            model.beginPress(0)
            model.endPress(quickClick: true)
            XCTAssertNil(model.selectedID)
            model.beginPress(1)
            model.endPress(quickClick: false)
            XCTAssertNil(model.selectedID)
        }
    }
}
