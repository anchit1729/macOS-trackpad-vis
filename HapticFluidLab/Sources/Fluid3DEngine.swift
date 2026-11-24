import Foundation

struct Fluid3DFrame: Sendable {
    let particles: [FluidParticle3D]
    let pressure: [Double]
    let fluid: [Bool]
    let surface: FluidSurfaceMesh

    func sample(near point: Vector3, radius: Double = 0.12) -> LocalFluidSample {
        var energy = 0.0
        var weightSum = 0.0
        var count = 0
        for particle in particles {
            let dist = (particle.position - point).lengthSquared
            let weight = max(0, 1 - dist / (radius * radius))
            guard weight > 0 else { continue }
            energy += weight * 0.5 * particle.velocity.lengthSquared
            weightSum += weight
            count += 1
        }
        return .init(kineticEnergy: weightSum > 0 ? energy / weightSum : 0,
                     pressureMagnitude: Fluid3DSimulation.pressureMagnitude(
                        at: point, pressure: pressure, fluid: fluid),
                     particleCount: count)
    }
}

actor Fluid3DEngine {
    private let simulation = Fluid3DSimulation()
    private var scene: FluidScene = .damBreak
    private var resetVersion = 0
    private var lastSurface: FluidSurfaceMesh?

    func advance(scene: FluidScene, resetVersion: Int, playing: Bool,
                 flipRatio: Double) -> Fluid3DFrame {
        let changed = self.scene != scene || self.resetVersion != resetVersion
        if changed {
            simulation.reset(to: scene)
            self.scene = scene
            self.resetVersion = resetVersion
        }
        simulation.flipRatio = flipRatio
        if playing { simulation.step(seconds: 1.0 / 30) }
        if playing || changed || lastSurface == nil {
            lastSurface = FluidSurfaceMesher.build(from: simulation.particles)
        }
        return .init(particles: simulation.particles,
                     pressure: simulation.pressureField,
                     fluid: simulation.fluidCells,
                     surface: lastSurface!)
    }
}
