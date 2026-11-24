import XCTest
@testable import HapticFluidLab

final class FluidHapticMappingTests: XCTestCase {
    func testDryPointerIsSilent() {
        XCTAssertNil(FluidHapticMapping.response(
            for: .init(kineticEnergy: 1, particleCount: 0),
            metric: .kineticEnergy, strength: 0.4))
    }

    func testMoreEnergyProducesMoreFeedback() {
        let low = FluidHapticMapping.response(
            for: .init(kineticEnergy: 0.02, particleCount: 5),
            metric: .kineticEnergy, strength: 0.4)!
        let high = FluidHapticMapping.response(
            for: .init(kineticEnergy: 0.6, particleCount: 5),
            metric: .kineticEnergy, strength: 0.4)!
        XCTAssertLessThan(low.level, high.level)
        XCTAssertLessThan(low.fundamentalHz, high.fundamentalHz)
    }

    func testStrengthCapsOutput() {
        let response = FluidHapticMapping.response(
            for: .init(kineticEnergy: 100, particleCount: 5),
            metric: .kineticEnergy, strength: 10)!
        XCTAssertEqual(response.level, 0.55)
    }

    func testPressureResponseUsesPressureNotMotion() {
        let still = LocalFluidSample(kineticEnergy: 0, pressureMagnitude: 0.2,
                                     particleCount: 5)
        let response = FluidHapticMapping.response(for: still, metric: .pressure,
                                                    strength: 0.4)
        XCTAssertNotNil(response)
        XCTAssertNil(FluidHapticMapping.response(for: still, metric: .kineticEnergy,
                                                 strength: 0.4))
    }

    func testLayeredFramesMoveWithinTheMotorLimit() {
        let sample = LocalFluidSample(kineticEnergy: 0.5, pressureMagnitude: 0.3,
                                      particleCount: 8)
        for metric in HapticMetric.allCases {
            let response = FluidHapticMapping.response(for: sample, metric: metric,
                                                        strength: 0.55)!
            let frames = stride(from: 0.0, through: 0.6, by: 0.012).map {
                FluidHapticMapping.frame(for: response, at: $0)
            }
            XCTAssertGreaterThan(Set(frames.map { Int($0.level * 10_000) }).count, 2)
            for frame in frames {
                XCTAssertEqual(frame.tones.count, 3)
                XCTAssertLessThanOrEqual(frame.level, 0.55)
                XCTAssertGreaterThan(frame.level, 0)
                XCTAssertEqual(frame.tones.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
                XCTAssertTrue(frame.tones.allSatisfy { (90...4_000).contains($0.hertz) && $0.weight > 0 })
            }
        }
    }

    func testMotionAndPressureHaveDistinctLayers() {
        let sample = LocalFluidSample(kineticEnergy: 0.5, pressureMagnitude: 0.5,
                                      particleCount: 8)
        let motion = FluidHapticMapping.response(for: sample, metric: .kineticEnergy,
                                                 strength: 0.4)!
        let pressure = FluidHapticMapping.response(for: sample, metric: .pressure,
                                                   strength: 0.4)!
        XCTAssertGreaterThan(motion.accentHz, pressure.accentHz)
        XCTAssertGreaterThan(motion.shimmerHz, pressure.shimmerHz)
        XCTAssertNotEqual(FluidHapticMapping.frame(for: motion, at: 0.1).tones[0].hertz,
                          FluidHapticMapping.frame(for: pressure, at: 0.1).tones[0].hertz)
    }
}
