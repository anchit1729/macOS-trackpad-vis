import XCTest
@testable import HapticFluidLab

final class Fluid3DEngineTests: XCTestCase {
    func testActorBuildsSurfaceAndChangesScene() async {
        let engine = Fluid3DEngine()
        let dam = await engine.advance(scene: .damBreak, resetVersion: 0,
                                       playing: true, flipRatio: 0.88)
        let vortex = await engine.advance(scene: .vortex, resetVersion: 0,
                                          playing: true, flipRatio: 0.88)
        XCTAssertGreaterThan(dam.surface.triangleCount, 1_000)
        XCTAssertGreaterThan(vortex.surface.triangleCount, 1_000)
        XCTAssertNotEqual(dam.particles.count, vortex.particles.count)
        let sample = vortex.sample(near: vortex.particles[0].position)
        XCTAssertGreaterThan(sample.particleCount, 0)
    }
}
