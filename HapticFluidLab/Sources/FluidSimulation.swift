import Foundation

struct Vector2: Equatable, Sendable {
    var x: Double
    var y: Double

    static let zero = Vector2(x: 0, y: 0)
    var lengthSquared: Double { x * x + y * y }
    var length: Double { sqrt(lengthSquared) }

    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, scale: Double) -> Self { .init(x: a.x * scale, y: a.y * scale) }
}

struct FluidParticle: Sendable {
    var position: Vector2
    var velocity: Vector2
}

enum FluidScene: String, CaseIterable, Identifiable, Sendable {
    case damBreak = "Dam break"
    case collidingStreams = "Colliding streams"
    case vortex = "Vortex"

    var id: String { rawValue }
    var summary: String {
        switch self {
        case .damBreak: "A water column falls and spreads across the floor."
        case .collidingStreams: "Two currents meet and form a moving splash."
        case .vortex: "A rotating pool carries energy around its centre."
        }
    }
}

struct LocalFluidSample: Equatable, Sendable {
    let kineticEnergy: Double
    let pressureMagnitude: Double
    let particleCount: Int

    init(kineticEnergy: Double, pressureMagnitude: Double = 0, particleCount: Int) {
        self.kineticEnergy = kineticEnergy
        self.pressureMagnitude = pressureMagnitude
        self.particleCount = particleCount
    }

    static func sample(_ particles: [FluidParticle], near point: Vector2,
                       radius: Double = 0.08) -> Self {
        guard radius > 0 else { return .init(kineticEnergy: 0, particleCount: 0) }
        var total = 0.0
        var weightSum = 0.0
        var count = 0
        for particle in particles {
            let distanceSquared = (particle.position - point).lengthSquared
            let weight = max(0, 1 - distanceSquared / (radius * radius))
            guard weight > 0 else { continue }
            total += weight * 0.5 * particle.velocity.lengthSquared
            weightSum += weight
            count += 1
        }
        return .init(kineticEnergy: weightSum > 0 ? total / weightSum : 0,
                     particleCount: count)
    }
}

final class FluidSimulation {
    static let columns = 48
    static let rows = 36
    static let cellSize = 1.0 / Double(columns)
    static let width = 1.0
    static let height = 0.75

    private let nx = columns
    private let ny = rows
    private let h = cellSize
    private let gravity = 3.5
    private(set) var particles: [FluidParticle] = []
    private(set) var divergenceBeforeProjection = 0.0
    private(set) var divergenceAfterProjection = 0.0
    var flipRatio = 0.88

    private var u: [Double]
    private var v: [Double]
    private var uWeight: [Double]
    private var vWeight: [Double]
    private var fluid: [Bool]
    private var pressure: [Double]
    private var pressureRightHandSide: [Double]

    var pressureField: [Double] { pressure }
    var fluidCells: [Bool] { fluid }

    init(scene: FluidScene = .damBreak) {
        u = .init(repeating: 0, count: (Self.columns + 1) * Self.rows)
        v = .init(repeating: 0, count: Self.columns * (Self.rows + 1))
        uWeight = .init(repeating: 0, count: (Self.columns + 1) * Self.rows)
        vWeight = .init(repeating: 0, count: Self.columns * (Self.rows + 1))
        fluid = .init(repeating: false, count: Self.columns * Self.rows)
        pressure = .init(repeating: 0, count: Self.columns * Self.rows)
        pressureRightHandSide = .init(repeating: 0, count: Self.columns * Self.rows)
        reset(to: scene)
    }

    func reset(to scene: FluidScene) {
        particles.removeAll(keepingCapacity: true)
        divergenceBeforeProjection = 0
        divergenceAfterProjection = 0
        let spacing = h * 0.52
        switch scene {
        case .damBreak:
            seed(minX: 0.06, maxX: 0.34, minY: 0.06, maxY: 0.68,
                 spacing: spacing) { _ in .zero }
        case .collidingStreams:
            seed(minX: 0.06, maxX: 0.28, minY: 0.25, maxY: 0.62,
                 spacing: spacing) { _ in .init(x: 0.9, y: 0) }
            seed(minX: 0.72, maxX: 0.94, minY: 0.25, maxY: 0.62,
                 spacing: spacing) { _ in .init(x: -0.9, y: 0) }
        case .vortex:
            seed(minX: 0.20, maxX: 0.80, minY: 0.12, maxY: 0.68,
                 spacing: spacing) { point in
                let offset = point - Vector2(x: 0.5, y: 0.4)
                let distance = max(0.08, offset.length)
                return .init(x: -offset.y / distance * 0.9,
                             y: offset.x / distance * 0.9)
            } filter: { point in
                let offset = point - Vector2(x: 0.5, y: 0.4)
                return offset.lengthSquared < 0.27 * 0.27
            }
        }
    }

    private func seed(minX: Double, maxX: Double, minY: Double, maxY: Double,
                      spacing: Double, velocity: (Vector2) -> Vector2,
                      filter: (Vector2) -> Bool = { _ in true }) {
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let point = Vector2(x: x, y: y)
                if filter(point) { particles.append(.init(position: point, velocity: velocity(point))) }
                x += spacing
            }
            y += spacing
        }
    }

    func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, !particles.isEmpty else { return }
        var maxSpeed = 0.0
        for particle in particles { maxSpeed = max(maxSpeed, particle.velocity.length) }
        let substeps = min(5, max(1, Int(ceil(maxSpeed * seconds / h / 1.2))))
        let dt = min(seconds, 1.0 / 20) / Double(substeps)
        for _ in 0..<substeps { substep(dt: dt) }
        regularizeParticleSpacing()
    }

    private func substep(dt: Double) {
        transferParticlesToGrid()
        for index in v.indices where vWeight[index] > 0 { v[index] -= gravity * dt }
        extrapolate(&u, weights: &uWeight, width: nx + 1, height: ny)
        extrapolate(&v, weights: &vWeight, width: nx, height: ny + 1)
        enforceWalls()
        let uBefore = u
        let vBefore = v
        divergenceBeforeProjection = meanDivergence()
        project(dt: dt)
        divergenceAfterProjection = meanDivergence()
        var deltaU = u
        var deltaV = v
        for index in deltaU.indices { deltaU[index] -= uBefore[index] }
        for index in deltaV.indices { deltaV[index] -= vBefore[index] }
        let blend = min(1, max(0, flipRatio))
        for index in particles.indices {
            let point = particles[index].position
            let pic = sampleVelocity(at: point, u: u, v: v)
            let change = sampleVelocity(at: point, u: deltaU, v: deltaV)
            let flip = particles[index].velocity + change
            var velocity = pic * (1 - blend) + flip * blend
            if velocity.length > 3 { velocity = velocity * (3 / velocity.length) }
            particles[index].velocity = velocity
            particles[index].position = point + velocity * dt
            contain(&particles[index])
        }
    }

    private func transferParticlesToGrid() {
        u = .init(repeating: 0, count: u.count)
        v = .init(repeating: 0, count: v.count)
        uWeight = .init(repeating: 0, count: uWeight.count)
        vWeight = .init(repeating: 0, count: vWeight.count)
        fluid = .init(repeating: false, count: fluid.count)
        for particle in particles {
            let x = min(nx - 1, max(0, Int(particle.position.x / h)))
            let y = min(ny - 1, max(0, Int(particle.position.y / h)))
            fluid[x + y * nx] = true
            Self.splat(particle.velocity.x, at: particle.position,
                       into: &u, weights: &uWeight, width: nx + 1, height: ny,
                       offset: .init(x: 0, y: 0.5), h: h)
            Self.splat(particle.velocity.y, at: particle.position,
                       into: &v, weights: &vWeight, width: nx, height: ny + 1,
                       offset: .init(x: 0.5, y: 0), h: h)
        }
        for index in u.indices where uWeight[index] > 0 { u[index] /= uWeight[index] }
        for index in v.indices where vWeight[index] > 0 { v[index] /= vWeight[index] }
    }

    private static func splat(_ value: Double, at point: Vector2,
                              into field: inout [Double], weights: inout [Double],
                              width: Int, height: Int, offset: Vector2, h: Double) {
        let gx = point.x / h - offset.x
        let gy = point.y / h - offset.y
        let left = Int(floor(gx))
        let bottom = Int(floor(gy))
        for y in bottom...(bottom + 1) where (0..<height).contains(y) {
            for x in left...(left + 1) where (0..<width).contains(x) {
                let weight = (1 - abs(gx - Double(x))) * (1 - abs(gy - Double(y)))
                let index = x + y * width
                field[index] += value * weight
                weights[index] += weight
            }
        }
    }

    private func extrapolate(_ field: inout [Double], weights: inout [Double],
                             width: Int, height: Int) {
        for _ in 0..<2 {
            var filled = field
            var filledWeights = weights
            for y in 0..<height {
                for x in 0..<width where weights[x + y * width] == 0 {
                    var sum = 0.0
                    var count = 0.0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let xx = x + dx
                        let yy = y + dy
                        if (0..<width).contains(xx), (0..<height).contains(yy),
                           weights[xx + yy * width] > 0 {
                            sum += field[xx + yy * width]
                            count += 1
                        }
                    }
                    if count > 0 {
                        filled[x + y * width] = sum / count
                        filledWeights[x + y * width] = 0.001
                    }
                }
            }
            field = filled
            weights = filledWeights
        }
    }

    private func enforceWalls() {
        for y in 0..<ny {
            u[y * (nx + 1)] = 0
            u[nx + y * (nx + 1)] = 0
        }
        for x in 0..<nx {
            v[x] = 0
            v[x + ny * nx] = 0
        }
    }

    private func project(dt: Double) {
        // Red-black SOR reaches a useful pressure estimate with fewer passes
        // than Jacobi. Each colour reads only the other colour's cells.
        pressure = .init(repeating: 0, count: pressure.count)
        for y in 0..<ny {
            for x in 0..<nx where fluid[x + y * nx] {
                let index = x + y * nx
                let divergence = (u[x + 1 + y * (nx + 1)] - u[x + y * (nx + 1)]
                                  + v[x + (y + 1) * nx] - v[x + y * nx]) / h
                pressureRightHandSide[index] = -h * h * divergence / dt
            }
        }
        for _ in 0..<40 {
            for colour in 0...1 {
                for y in 0..<ny {
                    for x in 0..<nx where (x + y) & 1 == colour && fluid[x + y * nx] {
                        let index = x + y * nx
                        var sum = pressureRightHandSide[index]
                        var diagonal = 0.0
                        if x > 0 {
                            diagonal += 1
                            if fluid[index - 1] { sum += pressure[index - 1] }
                        }
                        if x + 1 < nx {
                            diagonal += 1
                            if fluid[index + 1] { sum += pressure[index + 1] }
                        }
                        if y > 0 {
                            diagonal += 1
                            if fluid[index - nx] { sum += pressure[index - nx] }
                        }
                        if y + 1 < ny {
                            diagonal += 1
                            if fluid[index + nx] { sum += pressure[index + nx] }
                        }
                        if diagonal > 0 {
                            let estimate = sum / diagonal
                            pressure[index] += 1.5 * (estimate - pressure[index])
                        }
                    }
                }
            }
        }
        for y in 0..<ny {
            for x in 1..<nx {
                let left = x - 1 + y * nx
                let right = x + y * nx
                if fluid[left] || fluid[right] {
                    u[x + y * (nx + 1)] -= dt * ((fluid[right] ? pressure[right] : 0)
                                               - (fluid[left] ? pressure[left] : 0)) / h
                }
            }
        }
        for y in 1..<ny {
            for x in 0..<nx {
                let below = x + (y - 1) * nx
                let above = x + y * nx
                if fluid[below] || fluid[above] {
                    v[x + y * nx] -= dt * ((fluid[above] ? pressure[above] : 0)
                                          - (fluid[below] ? pressure[below] : 0)) / h
                }
            }
        }
        enforceWalls()
    }

    private func meanDivergence() -> Double {
        var sum = 0.0
        var count = 0
        for y in 0..<ny {
            for x in 0..<nx where fluid[x + y * nx] {
                sum += abs((u[x + 1 + y * (nx + 1)] - u[x + y * (nx + 1)]
                            + v[x + (y + 1) * nx] - v[x + y * nx]) / h)
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    private func sampleVelocity(at point: Vector2, u: [Double], v: [Double]) -> Vector2 {
        .init(x: Self.bilinear(u, at: point, width: nx + 1, height: ny,
                               offset: .init(x: 0, y: 0.5), h: h),
              y: Self.bilinear(v, at: point, width: nx, height: ny + 1,
                               offset: .init(x: 0.5, y: 0), h: h))
    }

    private static func bilinear(_ field: [Double], at point: Vector2,
                                 width: Int, height: Int, offset: Vector2, h: Double) -> Double {
        let gx = min(Double(width - 1), max(0, point.x / h - offset.x))
        let gy = min(Double(height - 1), max(0, point.y / h - offset.y))
        let x0 = Int(floor(gx))
        let y0 = Int(floor(gy))
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)
        let tx = gx - Double(x0)
        let ty = gy - Double(y0)
        let a = field[x0 + y0 * width] * (1 - tx) + field[x1 + y0 * width] * tx
        let b = field[x0 + y1 * width] * (1 - tx) + field[x1 + y1 * width] * tx
        return a * (1 - ty) + b * ty
    }

    private func contain(_ particle: inout FluidParticle) {
        let margin = h * 0.6
        if particle.position.x < margin {
            particle.position.x = margin
            particle.velocity.x = 0
        } else if particle.position.x > Self.width - margin {
            particle.position.x = Self.width - margin
            particle.velocity.x = 0
        }
        if particle.position.y < margin {
            particle.position.y = margin
            particle.velocity.y = 0
            particle.velocity.x *= 0.97
        } else if particle.position.y > Self.height - margin {
            particle.position.y = Self.height - margin - 0.003
            particle.velocity.y = min(-0.6, particle.velocity.y)
        }
    }

    /// Keep grains separated after advection. A dense linked-cell grid avoids
    /// pairwise work across the whole particle set.
    private func regularizeParticleSpacing() {
        let spacing = h * 0.52
        let bucketColumns = Int(ceil(Self.width / spacing)) + 1
        let bucketRows = Int(ceil(Self.height / spacing)) + 1
        for _ in 0..<2 {
            var heads = [Int](repeating: -1, count: bucketColumns * bucketRows)
            var next = [Int](repeating: -1, count: particles.count)
            for i in particles.indices {
                let point = particles[i].position
                let x = min(bucketColumns - 1, max(0, Int(point.x / spacing)))
                let y = min(bucketRows - 1, max(0, Int(point.y / spacing)))
                let bucket = x + y * bucketColumns
                next[i] = heads[bucket]
                heads[bucket] = i
            }
            var correction = [Vector2](repeating: .zero, count: particles.count)
            for i in particles.indices {
                let point = particles[i].position
                let cx = min(bucketColumns - 1, max(0, Int(point.x / spacing)))
                let cy = min(bucketRows - 1, max(0, Int(point.y / spacing)))
                for y in max(0, cy - 1)...min(bucketRows - 1, cy + 1) {
                    for x in max(0, cx - 1)...min(bucketColumns - 1, cx + 1) {
                        var j = heads[x + y * bucketColumns]
                        while j >= 0 {
                            if j > i {
                                let delta = point - particles[j].position
                                let distance = delta.length
                                if distance < spacing {
                                    let direction = distance > 0.000001
                                        ? delta * (1 / distance) : Vector2(x: 1, y: 0)
                                    let push = direction * (0.45 * (spacing - distance))
                                    correction[i] = correction[i] + push
                                    correction[j] = correction[j] - push
                                }
                            }
                            j = next[j]
                        }
                    }
                }
            }
            for i in particles.indices {
                particles[i].position = particles[i].position + correction[i]
                contain(&particles[i])
            }
        }
    }

    func stir(at point: Vector2, movement: Vector2) {
        let radius = 0.11
        for index in particles.indices {
            let offset = particles[index].position - point
            let weight = max(0, 1 - offset.lengthSquared / (radius * radius))
            guard weight > 0 else { continue }
            let outward = offset.length > 0.001 ? offset * (0.4 / offset.length) : .zero
            particles[index].velocity = particles[index].velocity
                + (movement * 8 + outward) * weight
        }
    }

    func localEnergy(near point: Vector2, radius: Double = 0.08) -> LocalFluidSample {
        let energy = LocalFluidSample.sample(particles, near: point, radius: radius)
        return .init(kineticEnergy: energy.kineticEnergy,
                     pressureMagnitude: Self.pressureMagnitude(at: point, pressure: pressure,
                                                               fluid: fluid),
                     particleCount: energy.particleCount)
    }

    static func pressureMagnitude(at point: Vector2, pressure: [Double],
                                  fluid: [Bool]) -> Double {
        guard (0...width).contains(point.x), (0...height).contains(point.y) else { return 0 }
        let cx = Int(point.x / cellSize)
        let cy = Int(point.y / cellSize)
        var weightedPressure = 0.0
        var totalWeight = 0.0
        for y in max(0, cy - 1)...min(rows - 1, cy + 1) {
            for x in max(0, cx - 1)...min(columns - 1, cx + 1) {
                let index = x + y * columns
                guard fluid[index] else { continue }
                let centre = Vector2(x: (Double(x) + 0.5) * cellSize,
                                     y: (Double(y) + 0.5) * cellSize)
                let distance = (centre - point).lengthSquared / (cellSize * cellSize)
                let weight = 1 / (1 + distance)
                weightedPressure += abs(pressure[index]) * weight
                totalWeight += weight
            }
        }
        return totalWeight > 0 ? weightedPressure / totalWeight : 0
    }

    func velocity(at point: Vector2) -> Vector2 {
        sampleVelocity(at: point, u: u, v: v)
    }
}
