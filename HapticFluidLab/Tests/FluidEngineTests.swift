import XCTest
@testable import HapticFluidLab

final class FluidEngineTests: XCTestCase {
    func testActorProducesFramesAndAppliesSceneChanges() async {
        let engine = FluidEngine()
        let dam = await engine.advance(scene: .damBreak, resetVersion: 0,
                                       playing: true, flipRatio: 0.88, stirs: [])
        let vortex = await engine.advance(scene: .vortex, resetVersion: 0,
                                          playing: true, flipRatio: 0.88, stirs: [])
        XCTAssertGreaterThan(dam.particles.count, 500)
        XCTAssertGreaterThan(vortex.particles.count, dam.particles.count)
        XCTAssertFalse(vortex.arrows.isEmpty)
        XCTAssertLessThan(vortex.divergenceAfter, vortex.divergenceBefore)
    }
}
