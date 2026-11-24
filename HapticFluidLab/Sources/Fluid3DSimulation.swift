import Foundation

struct Vector3: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Self(x: 0, y: 0, z: 0)
    var lengthSquared: Double { x * x + y * y + z * z }
    var length: Double { sqrt(lengthSquared) }

    static func + (a: Self, b: Self) -> Self {
        .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }
    static func - (a: Self, b: Self) -> Self {
        .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }
    static func * (a: Self, scale: Double) -> Self {
        .init(x: a.x * scale, y: a.y * scale, z: a.z * scale)
    }
    static func / (a: Self, scale: Double) -> Self { a * (1 / scale) }
    static func cross(_ a: Self, _ b: Self) -> Self {
        .init(x: a.y * b.z - a.z * b.y,
              y: a.z * b.x - a.x * b.z,
              z: a.x * b.y - a.y * b.x)
    }
    static func dot(_ a: Self, _ b: Self) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    var normalized: Self { length > 0.00001 ? self / length : .init(x: 0, y: 1, z: 0) }
}

struct FluidParticle3D: Sendable {
    var position: Vector3
    var velocity: Vector3
}

final class Fluid3DSimulation {
    static let nx = 24
    static let ny = 16
    static let nz = 16
    static let h = 0.05
    static let width = Double(nx) * h
    static let height = Double(ny) * h
    static let depth = Double(nz) * h

    private(set) var particles: [FluidParticle3D] = []
    private(set) var divergenceBeforeProjection = 0.0
    private(set) var divergenceAfterProjection = 0.0
    var flipRatio = 0.88

    private var u = [Double](repeating: 0, count: (nx + 1) * ny * nz)
    private var v = [Double](repeating: 0, count: nx * (ny + 1) * nz)
    private var w = [Double](repeating: 0, count: nx * ny * (nz + 1))
    private var uWeight = [Double](repeating: 0, count: (nx + 1) * ny * nz)
    private var vWeight = [Double](repeating: 0, count: nx * (ny + 1) * nz)
    private var wWeight = [Double](repeating: 0, count: nx * ny * (nz + 1))
    private var fluid = [Bool](repeating: false, count: nx * ny * nz)
    private var pressure = [Double](repeating: 0, count: nx * ny * nz)
    private var rhs = [Double](repeating: 0, count: nx * ny * nz)

    var pressureField: [Double] { pressure }
    var fluidCells: [Bool] { fluid }

    init(scene: FluidScene = .damBreak) { reset(to: scene) }

    func reset(to scene: FluidScene) {
        particles.removeAll(keepingCapacity: true)
        divergenceBeforeProjection = 0
        divergenceAfterProjection = 0
        let spacing = Self.h * 0.68
        switch scene {
        case .damBreak:
            seed(x: 0.08...0.42, y: 0.07...0.69, z: 0.09...0.71,
                 spacing: spacing) { _ in .zero }
        case .collidingStreams:
            seed(x: 0.08...0.33, y: 0.19...0.64, z: 0.16...0.64,
                 spacing: spacing) { _ in .init(x: 0.85, y: 0, z: 0) }
            seed(x: 0.87...1.12, y: 0.19...0.64, z: 0.16...0.64,
                 spacing: spacing) { _ in .init(x: -0.85, y: 0, z: 0) }
        case .vortex:
            seed(x: 0.25...0.95, y: 0.11...0.58, z: 0.08...0.72,
                 spacing: spacing) { point in
                let offset = point - Vector3(x: 0.6, y: 0.35, z: 0.4)
                let radius = max(0.10, hypot(offset.x, offset.z))
                return .init(x: -offset.z / radius * 0.8,
                             y: 0, z: offset.x / radius * 0.8)
            } filter: { point in
                let offset = point - Vector3(x: 0.6, y: 0.35, z: 0.4)
                return offset.lengthSquared < 0.32 * 0.32
            }
        }
    }

    private func seed(x: ClosedRange<Double>, y: ClosedRange<Double>,
                      z: ClosedRange<Double>, spacing: Double,
                      velocity: (Vector3) -> Vector3,
                      filter: (Vector3) -> Bool = { _ in true }) {
        var zz = z.lowerBound
        while zz <= z.upperBound {
            var yy = y.lowerBound
            while yy <= y.upperBound {
                var xx = x.lowerBound
                while xx <= x.upperBound {
                    let point = Vector3(x: xx, y: yy, z: zz)
                    if filter(point) {
                        particles.append(.init(position: point, velocity: velocity(point)))
                    }
                    xx += spacing
                }
                yy += spacing
            }
            zz += spacing
        }
    }

    func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, !particles.isEmpty else { return }
        var speed = 0.0
        for particle in particles { speed = max(speed, particle.velocity.length) }
        let substeps = min(3, max(1, Int(ceil(speed * seconds / (Self.h * 1.5)))))
        let dt = min(seconds, 1.0 / 20) / Double(substeps)
        for _ in 0..<substeps { substep(dt: dt) }
    }

    private func substep(dt: Double) {
        transferToGrid()
        for index in v.indices where vWeight[index] > 0 { v[index] -= 2.8 * dt }
        Self.extrapolate(&u, weights: &uWeight, nx: Self.nx + 1, ny: Self.ny, nz: Self.nz)
        Self.extrapolate(&v, weights: &vWeight, nx: Self.nx, ny: Self.ny + 1, nz: Self.nz)
        Self.extrapolate(&w, weights: &wWeight, nx: Self.nx, ny: Self.ny, nz: Self.nz + 1)
        enforceWalls()
        let oldU = u, oldV = v, oldW = w
        divergenceBeforeProjection = meanDivergence()
        project(dt: dt)
        divergenceAfterProjection = meanDivergence()
        var changeU = u, changeV = v, changeW = w
        for i in changeU.indices { changeU[i] -= oldU[i] }
        for i in changeV.indices { changeV[i] -= oldV[i] }
        for i in changeW.indices { changeW[i] -= oldW[i] }
        let blend = min(1, max(0, flipRatio))
        for i in particles.indices {
            let old = particles[i]
            let pic = sampleVelocity(at: old.position, u: u, v: v, w: w)
            let change = sampleVelocity(at: old.position, u: changeU, v: changeV, w: changeW)
            var velocity = pic * (1 - blend) + (old.velocity + change) * blend
            if velocity.length > 2.5 { velocity = velocity.normalized * 2.5 }
            var position = old.position + velocity * dt
            let margin = Self.h * 0.6
            if position.x < margin || position.x > Self.width - margin {
                position.x = min(Self.width - margin, max(margin, position.x))
                velocity.x = 0
            }
            if position.y < margin || position.y > Self.height - margin {
                position.y = min(Self.height - margin, max(margin, position.y))
                velocity.y = 0
                velocity.x *= 0.97
                velocity.z *= 0.97
            }
            if position.z < margin || position.z > Self.depth - margin {
                position.z = min(Self.depth - margin, max(margin, position.z))
                velocity.z = 0
            }
            particles[i] = .init(position: position, velocity: velocity)
        }
    }

    private func transferToGrid() {
        u = .init(repeating: 0, count: u.count)
        v = .init(repeating: 0, count: v.count)
        w = .init(repeating: 0, count: w.count)
        uWeight = .init(repeating: 0, count: uWeight.count)
        vWeight = .init(repeating: 0, count: vWeight.count)
        wWeight = .init(repeating: 0, count: wWeight.count)
        fluid = .init(repeating: false, count: fluid.count)
        for particle in particles {
            let x = min(Self.nx - 1, max(0, Int(particle.position.x / Self.h)))
            let y = min(Self.ny - 1, max(0, Int(particle.position.y / Self.h)))
            let z = min(Self.nz - 1, max(0, Int(particle.position.z / Self.h)))
            fluid[Self.index(x, y, z, nx: Self.nx, ny: Self.ny)] = true
            Self.splat(particle.velocity.x, at: particle.position, into: &u,
                       weights: &uWeight, nx: Self.nx + 1, ny: Self.ny, nz: Self.nz,
                       offset: .init(x: 0, y: 0.5, z: 0.5))
            Self.splat(particle.velocity.y, at: particle.position, into: &v,
                       weights: &vWeight, nx: Self.nx, ny: Self.ny + 1, nz: Self.nz,
                       offset: .init(x: 0.5, y: 0, z: 0.5))
            Self.splat(particle.velocity.z, at: particle.position, into: &w,
                       weights: &wWeight, nx: Self.nx, ny: Self.ny, nz: Self.nz + 1,
                       offset: .init(x: 0.5, y: 0.5, z: 0))
        }
        for i in u.indices where uWeight[i] > 0 { u[i] /= uWeight[i] }
        for i in v.indices where vWeight[i] > 0 { v[i] /= vWeight[i] }
        for i in w.indices where wWeight[i] > 0 { w[i] /= wWeight[i] }
    }

    private static func index(_ x: Int, _ y: Int, _ z: Int, nx: Int, ny: Int) -> Int {
        x + nx * (y + ny * z)
    }

    private static func splat(_ value: Double, at point: Vector3,
                              into field: inout [Double], weights: inout [Double],
                              nx: Int, ny: Int, nz: Int, offset: Vector3) {
        let gx = point.x / h - offset.x
        let gy = point.y / h - offset.y
        let gz = point.z / h - offset.z
        let x0 = Int(floor(gx)), y0 = Int(floor(gy)), z0 = Int(floor(gz))
        for z in z0...(z0 + 1) where (0..<nz).contains(z) {
            for y in y0...(y0 + 1) where (0..<ny).contains(y) {
                for x in x0...(x0 + 1) where (0..<nx).contains(x) {
                    let weight = (1 - abs(gx - Double(x)))
                        * (1 - abs(gy - Double(y))) * (1 - abs(gz - Double(z)))
                    let i = index(x, y, z, nx: nx, ny: ny)
                    field[i] += value * weight
                    weights[i] += weight
                }
            }
        }
    }

    private static func extrapolate(_ field: inout [Double], weights: inout [Double],
                                    nx: Int, ny: Int, nz: Int) {
        var filled = field
        var filledWeights = weights
        for z in 0..<nz {
            for y in 0..<ny {
                for x in 0..<nx {
                    let i = index(x, y, z, nx: nx, ny: ny)
                    guard weights[i] == 0 else { continue }
                    var sum = 0.0
                    var count = 0.0
                    if x > 0, weights[i - 1] > 0 { sum += field[i - 1]; count += 1 }
                    if x + 1 < nx, weights[i + 1] > 0 { sum += field[i + 1]; count += 1 }
                    if y > 0, weights[i - nx] > 0 { sum += field[i - nx]; count += 1 }
                    if y + 1 < ny, weights[i + nx] > 0 { sum += field[i + nx]; count += 1 }
                    let stride = nx * ny
                    if z > 0, weights[i - stride] > 0 {
                        sum += field[i - stride]; count += 1
                    }
                    if z + 1 < nz, weights[i + stride] > 0 {
                        sum += field[i + stride]; count += 1
                    }
                    if count > 0 {
                        filled[i] = sum / count
                        filledWeights[i] = 0.001
                    }
                }
            }
        }
        field = filled
        weights = filledWeights
    }

    private func enforceWalls() {
        for z in 0..<Self.nz {
            for y in 0..<Self.ny {
                u[Self.index(0, y, z, nx: Self.nx + 1, ny: Self.ny)] = 0
                u[Self.index(Self.nx, y, z, nx: Self.nx + 1, ny: Self.ny)] = 0
            }
            for x in 0..<Self.nx {
                v[Self.index(x, 0, z, nx: Self.nx, ny: Self.ny + 1)] = 0
                v[Self.index(x, Self.ny, z, nx: Self.nx, ny: Self.ny + 1)] = 0
            }
        }
        for y in 0..<Self.ny {
            for x in 0..<Self.nx {
                w[Self.index(x, y, 0, nx: Self.nx, ny: Self.ny)] = 0
                w[Self.index(x, y, Self.nz, nx: Self.nx, ny: Self.ny)] = 0
            }
        }
    }

    private func divergence(_ x: Int, _ y: Int, _ z: Int) -> Double {
        (u[Self.index(x + 1, y, z, nx: Self.nx + 1, ny: Self.ny)]
         - u[Self.index(x, y, z, nx: Self.nx + 1, ny: Self.ny)]
         + v[Self.index(x, y + 1, z, nx: Self.nx, ny: Self.ny + 1)]
         - v[Self.index(x, y, z, nx: Self.nx, ny: Self.ny + 1)]
         + w[Self.index(x, y, z + 1, nx: Self.nx, ny: Self.ny)]
         - w[Self.index(x, y, z, nx: Self.nx, ny: Self.ny)]) / Self.h
    }

    private func meanDivergence() -> Double {
        var total = 0.0
        var count = 0
        for z in 0..<Self.nz {
            for y in 0..<Self.ny {
                for x in 0..<Self.nx where fluid[Self.index(x, y, z,
                                                       nx: Self.nx, ny: Self.ny)] {
                    total += abs(divergence(x, y, z))
                    count += 1
                }
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    private func project(dt: Double) {
        pressure = .init(repeating: 0, count: pressure.count)
        for z in 0..<Self.nz {
            for y in 0..<Self.ny {
                for x in 0..<Self.nx {
                    let i = Self.index(x, y, z, nx: Self.nx, ny: Self.ny)
                    if fluid[i] { rhs[i] = -Self.h * Self.h * divergence(x, y, z) / dt }
                }
            }
        }
        let stride = Self.nx * Self.ny
        for _ in 0..<36 {
            for colour in 0...1 {
                for z in 0..<Self.nz {
                    for y in 0..<Self.ny {
                        for x in 0..<Self.nx where ((x + y + z) & 1) == colour {
                            let i = Self.index(x, y, z, nx: Self.nx, ny: Self.ny)
                            guard fluid[i] else { continue }
                            var sum = rhs[i]
                            var diagonal = 0.0
                            if x > 0 { diagonal += 1; if fluid[i - 1] { sum += pressure[i - 1] } }
                            if x + 1 < Self.nx {
                                diagonal += 1; if fluid[i + 1] { sum += pressure[i + 1] }
                            }
                            if y > 0 {
                                diagonal += 1; if fluid[i - Self.nx] { sum += pressure[i - Self.nx] }
                            }
                            if y + 1 < Self.ny {
                                diagonal += 1; if fluid[i + Self.nx] { sum += pressure[i + Self.nx] }
                            }
                            if z > 0 {
                                diagonal += 1; if fluid[i - stride] { sum += pressure[i - stride] }
                            }
                            if z + 1 < Self.nz {
                                diagonal += 1; if fluid[i + stride] { sum += pressure[i + stride] }
                            }
                            if diagonal > 0 {
                                let estimate = sum / diagonal
                                pressure[i] += 1.5 * (estimate - pressure[i])
                            }
                        }
                    }
                }
            }
        }
        for z in 0..<Self.nz {
            for y in 0..<Self.ny {
                for x in 1..<Self.nx {
                    let a = Self.index(x - 1, y, z, nx: Self.nx, ny: Self.ny)
                    let b = a + 1
                    if fluid[a] || fluid[b] {
                        let i = Self.index(x, y, z, nx: Self.nx + 1, ny: Self.ny)
                        u[i] -= dt * ((fluid[b] ? pressure[b] : 0)
                                     - (fluid[a] ? pressure[a] : 0)) / Self.h
                    }
                }
            }
        }
        for z in 0..<Self.nz {
            for y in 1..<Self.ny {
                for x in 0..<Self.nx {
                    let a = Self.index(x, y - 1, z, nx: Self.nx, ny: Self.ny)
                    let b = a + Self.nx
                    if fluid[a] || fluid[b] {
                        let i = Self.index(x, y, z, nx: Self.nx, ny: Self.ny + 1)
                        v[i] -= dt * ((fluid[b] ? pressure[b] : 0)
                                     - (fluid[a] ? pressure[a] : 0)) / Self.h
                    }
                }
            }
        }
        for z in 1..<Self.nz {
            for y in 0..<Self.ny {
                for x in 0..<Self.nx {
                    let a = Self.index(x, y, z - 1, nx: Self.nx, ny: Self.ny)
                    let b = a + stride
                    if fluid[a] || fluid[b] {
                        let i = Self.index(x, y, z, nx: Self.nx, ny: Self.ny)
                        w[i] -= dt * ((fluid[b] ? pressure[b] : 0)
                                     - (fluid[a] ? pressure[a] : 0)) / Self.h
                    }
                }
            }
        }
        enforceWalls()
    }

    private func sampleVelocity(at point: Vector3, u: [Double], v: [Double],
                                w: [Double]) -> Vector3 {
        .init(x: Self.sample(u, at: point, nx: Self.nx + 1, ny: Self.ny,
                             nz: Self.nz, offset: .init(x: 0, y: 0.5, z: 0.5)),
              y: Self.sample(v, at: point, nx: Self.nx, ny: Self.ny + 1,
                             nz: Self.nz, offset: .init(x: 0.5, y: 0, z: 0.5)),
              z: Self.sample(w, at: point, nx: Self.nx, ny: Self.ny,
                             nz: Self.nz + 1, offset: .init(x: 0.5, y: 0.5, z: 0)))
    }

    private static func sample(_ field: [Double], at point: Vector3, nx: Int,
                               ny: Int, nz: Int, offset: Vector3) -> Double {
        let gx = min(Double(nx - 1), max(0, point.x / h - offset.x))
        let gy = min(Double(ny - 1), max(0, point.y / h - offset.y))
        let gz = min(Double(nz - 1), max(0, point.z / h - offset.z))
        let x0 = Int(gx), y0 = Int(gy), z0 = Int(gz)
        let x1 = min(nx - 1, x0 + 1)
        let y1 = min(ny - 1, y0 + 1)
        let z1 = min(nz - 1, z0 + 1)
        let tx = gx - Double(x0), ty = gy - Double(y0), tz = gz - Double(z0)
        let a = field[index(x0, y0, z0, nx: nx, ny: ny)] * (1 - tx)
            + field[index(x1, y0, z0, nx: nx, ny: ny)] * tx
        let b = field[index(x0, y1, z0, nx: nx, ny: ny)] * (1 - tx)
            + field[index(x1, y1, z0, nx: nx, ny: ny)] * tx
        let c = field[index(x0, y0, z1, nx: nx, ny: ny)] * (1 - tx)
            + field[index(x1, y0, z1, nx: nx, ny: ny)] * tx
        let d = field[index(x0, y1, z1, nx: nx, ny: ny)] * (1 - tx)
            + field[index(x1, y1, z1, nx: nx, ny: ny)] * tx
        return ((a * (1 - ty) + b * ty) * (1 - tz)
                + (c * (1 - ty) + d * ty) * tz)
    }

    func localSample(near point: Vector3, radius: Double = 0.10) -> LocalFluidSample {
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
                     pressureMagnitude: Self.pressureMagnitude(at: point,
                                                               pressure: pressure, fluid: fluid),
                     particleCount: count)
    }

    static func pressureMagnitude(at point: Vector3, pressure: [Double],
                                  fluid: [Bool]) -> Double {
        guard (0...width).contains(point.x), (0...height).contains(point.y),
              (0...depth).contains(point.z) else { return 0 }
        let x = min(nx - 1, Int(point.x / h))
        let y = min(ny - 1, Int(point.y / h))
        let z = min(nz - 1, Int(point.z / h))
        var total = 0.0
        var weightSum = 0.0
        for zz in max(0, z - 1)...min(nz - 1, z + 1) {
            for yy in max(0, y - 1)...min(ny - 1, y + 1) {
                for xx in max(0, x - 1)...min(nx - 1, x + 1) {
                    let i = index(xx, yy, zz, nx: nx, ny: ny)
                    guard fluid[i] else { continue }
                    let centre = Vector3(x: (Double(xx) + 0.5) * h,
                                         y: (Double(yy) + 0.5) * h,
                                         z: (Double(zz) + 0.5) * h)
                    let weight = 1 / (1 + (centre - point).lengthSquared / (h * h))
                    total += abs(pressure[i]) * weight
                    weightSum += weight
                }
            }
        }
        return weightSum > 0 ? total / weightSum : 0
    }
}
