import XCTest
@testable import HapticFluidLab

final class Fluid3DSimulationTests: XCTestCase {
    func testScenesSeedParticlesInsideTank() {
        for scene in FluidScene.allCases {
            let simulation = Fluid3DSimulation(scene: scene)
            XCTAssertGreaterThan(simulation.particles.count, 1_000)
            XCTAssertTrue(simulation.particles.allSatisfy { particle in
                (0...Fluid3DSimulation.width).contains(particle.position.x)
                    && (0...Fluid3DSimulation.height).contains(particle.position.y)
                    && (0...Fluid3DSimulation.depth).contains(particle.position.z)
            })
        }
    }

    func testProjectionReducesVortexDivergence() {
        let simulation = Fluid3DSimulation(scene: .vortex)
        simulation.step(seconds: 1.0 / 30)
        XCTAssertGreaterThan(simulation.divergenceBeforeProjection, 0.01)
        XCTAssertLessThan(simulation.divergenceAfterProjection,
                          simulation.divergenceBeforeProjection)
    }

    func testParticlesRemainFiniteAfterMotion() {
        let simulation = Fluid3DSimulation(scene: .collidingStreams)
        for _ in 0..<30 { simulation.step(seconds: 1.0 / 30) }
        XCTAssertTrue(simulation.particles.allSatisfy { particle in
            particle.position.x.isFinite && particle.position.y.isFinite
                && particle.position.z.isFinite && particle.velocity.length.isFinite
                && (0...Fluid3DSimulation.width).contains(particle.position.x)
                && (0...Fluid3DSimulation.height).contains(particle.position.y)
                && (0...Fluid3DSimulation.depth).contains(particle.position.z)
        })
        let sample = simulation.localSample(near: simulation.particles[0].position)
        XCTAssertGreaterThan(sample.particleCount, 0)
        XCTAssertGreaterThan(sample.pressureMagnitude, 0)
    }

    func testMesherBuildsFiniteOrientedSurface() {
        let simulation = Fluid3DSimulation(scene: .damBreak)
        let mesh = FluidSurfaceMesher.build(from: simulation.particles)
        XCTAssertGreaterThan(mesh.triangleCount, 1_000)
        XCTAssertEqual(mesh.vertices.count, mesh.normals.count)
        XCTAssertTrue(mesh.vertices.allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        })
        XCTAssertTrue(mesh.normals.allSatisfy { abs($0.length - 1) < 0.001 })
    }
}
