import XCTest
@testable import HapticFluidLab

final class FluidSimulationTests: XCTestCase {
    func testAllScenesSeedWaterInsideDomain() {
        for scene in FluidScene.allCases {
            let simulation = FluidSimulation(scene: scene)
            XCTAssertGreaterThan(simulation.particles.count, 500)
            XCTAssertTrue(simulation.particles.allSatisfy {
                (0...FluidSimulation.width).contains($0.position.x)
                    && (0...FluidSimulation.height).contains($0.position.y)
            })
        }
    }

    func testProjectionReducesMeanDivergence() {
        let simulation = FluidSimulation(scene: .vortex)
        simulation.step(seconds: 1.0 / 60)
        XCTAssertGreaterThan(simulation.divergenceBeforeProjection, 0)
        XCTAssertLessThan(simulation.divergenceAfterProjection,
                          simulation.divergenceBeforeProjection)
    }

    func testParticlesStayFiniteAndInsideTank() {
        let simulation = FluidSimulation(scene: .damBreak)
        for _ in 0..<40 { simulation.step(seconds: 1.0 / 30) }
        XCTAssertTrue(simulation.particles.allSatisfy {
            $0.position.x.isFinite && $0.position.y.isFinite
                && $0.velocity.x.isFinite && $0.velocity.y.isFinite
                && (0...FluidSimulation.width).contains($0.position.x)
                && (0...FluidSimulation.height).contains($0.position.y)
        })
    }

    func testLocalEnergyFollowsNearbyMotion() {
        let simulation = FluidSimulation(scene: .collidingStreams)
        let near = simulation.localEnergy(near: .init(x: 0.16, y: 0.4))
        let empty = simulation.localEnergy(near: .init(x: 0.5, y: 0.7))
        XCTAssertGreaterThan(near.particleCount, 0)
        XCTAssertGreaterThan(near.kineticEnergy, 0)
        XCTAssertEqual(empty.particleCount, 0)
        XCTAssertEqual(empty.kineticEnergy, 0)
    }

    func testPressureMagnitudeIsAvailableInsideWater() {
        let simulation = FluidSimulation(scene: .damBreak)
        for _ in 0..<30 { simulation.step(seconds: 1.0 / 30) }
        let pressure = simulation.particles.map {
            simulation.localEnergy(near: $0.position).pressureMagnitude
        }
        XCTAssertGreaterThan(pressure.max() ?? 0, 0.01)
        XCTAssertEqual(simulation.localEnergy(near: .init(x: -1, y: -1)).pressureMagnitude, 0)
    }

    func testGrainsKeepAnEvenNearestNeighbourSpacing() {
        let simulation = FluidSimulation(scene: .damBreak)
        for _ in 0..<30 { simulation.step(seconds: 1.0 / 30) }
        var nearest: [Double] = []
        for i in simulation.particles.indices {
            var distance = Double.infinity
            for j in simulation.particles.indices where i != j {
                distance = min(distance,
                               (simulation.particles[i].position
                                - simulation.particles[j].position).length)
            }
            nearest.append(distance)
        }
        nearest.sort()
        XCTAssertGreaterThan(nearest[nearest.count / 10], 0.007)
    }

    func testParticlesDoNotStickToTheCeiling() {
        let simulation = FluidSimulation(scene: .damBreak)
        for _ in 0..<90 { simulation.step(seconds: 1.0 / 30) }
        let nearCeiling = simulation.particles.filter {
            $0.position.y > FluidSimulation.height - 0.02
        }.count
        XCTAssertLessThan(nearCeiling, 20)
    }
}
