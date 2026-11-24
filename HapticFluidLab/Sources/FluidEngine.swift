import Foundation

struct StirEvent: Sendable {
    let point: Vector2
    let movement: Vector2
}

struct FlowArrow: Sendable {
    let point: Vector2
    let velocity: Vector2
}

struct FluidSnapshot: Sendable {
    let particles: [FluidParticle]
    let arrows: [FlowArrow]
    let divergenceBefore: Double
    let divergenceAfter: Double
    let pressure: [Double]
    let fluid: [Bool]

    func localEnergy(near point: Vector2, radius: Double = 0.08) -> LocalFluidSample {
        let energy = LocalFluidSample.sample(particles, near: point, radius: radius)
        return .init(kineticEnergy: energy.kineticEnergy,
                     pressureMagnitude: FluidSimulation.pressureMagnitude(
                        at: point, pressure: pressure, fluid: fluid),
                     particleCount: energy.particleCount)
    }
}

/// The actor owns mutable solver state. AppKit reads immutable frame snapshots.
actor FluidEngine {
    private let simulation = FluidSimulation()
    private var scene: FluidScene = .damBreak
    private var resetVersion = 0

    func advance(scene: FluidScene, resetVersion: Int, playing: Bool,
                 flipRatio: Double, stirs: [StirEvent]) -> FluidSnapshot {
        if self.scene != scene || self.resetVersion != resetVersion {
            simulation.reset(to: scene)
            self.scene = scene
            self.resetVersion = resetVersion
        }
        simulation.flipRatio = flipRatio
        for stir in stirs { simulation.stir(at: stir.point, movement: stir.movement) }
        if playing { simulation.step(seconds: 1.0 / 30) }
        var arrows: [FlowArrow] = []
        arrows.reserveCapacity(108)
        for y in stride(from: 2, to: FluidSimulation.rows, by: 4) {
            for x in stride(from: 2, to: FluidSimulation.columns, by: 4) {
                let point = Vector2(x: Double(x) * FluidSimulation.cellSize,
                                    y: Double(y) * FluidSimulation.cellSize)
                arrows.append(.init(point: point, velocity: simulation.velocity(at: point)))
            }
        }
        return .init(particles: simulation.particles, arrows: arrows,
                     divergenceBefore: simulation.divergenceBeforeProjection,
                     divergenceAfter: simulation.divergenceAfterProjection,
                     pressure: simulation.pressureField, fluid: simulation.fluidCells)
    }
}
