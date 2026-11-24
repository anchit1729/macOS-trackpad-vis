import Foundation

struct FluidSurfaceMesh: Sendable {
    let vertices: [Vector3]
    let normals: [Vector3]

    var triangleCount: Int { vertices.count / 3 }
}

/// Builds a smooth density field, then extracts an isosurface with six
/// tetrahedra per grid cell. The output is a simple triangle soup.
enum FluidSurfaceMesher {
    // A finer display grid gives smoother contours without increasing solver cost.
    private static let h = 0.04
    private static let nx = Int(Fluid3DSimulation.width / h) + 1
    private static let ny = Int(Fluid3DSimulation.height / h) + 1
    private static let nz = Int(Fluid3DSimulation.depth / h) + 1
    private static let iso = 3.5
    private static let tetrahedra = [
        [0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
        [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]
    ]
    private static let corners = [
        (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
        (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)
    ]

    private struct SurfaceVertex {
        let position: Vector3
        let normal: Vector3
    }

    static func build(from particles: [FluidParticle3D]) -> FluidSurfaceMesh {
        var density = [Double](repeating: 0, count: nx * ny * nz)
        let radius = 0.08
        let radiusSquared = radius * radius
        for particle in particles {
            let gx = particle.position.x / h
            let gy = particle.position.y / h
            let gz = particle.position.z / h
            let extent = Int(ceil(radius / h))
            let x0 = Int(gx), y0 = Int(gy), z0 = Int(gz)
            for z in max(0, z0 - extent)...min(nz - 1, z0 + extent) {
                for y in max(0, y0 - extent)...min(ny - 1, y0 + extent) {
                    for x in max(0, x0 - extent)...min(nx - 1, x0 + extent) {
                        let dx = Double(x) * h - particle.position.x
                        let dy = Double(y) * h - particle.position.y
                        let dz = Double(z) * h - particle.position.z
                        let t = max(0, 1 - (dx * dx + dy * dy + dz * dz) / radiusSquared)
                        density[index(x, y, z)] += t * t
                    }
                }
            }
        }
        density = blur(density, axis: 0)
        density = blur(density, axis: 1)
        density = blur(density, axis: 2)
        // Force an air layer at the tank wall so the isosurface closes.
        for z in 0..<nz {
            for y in 0..<ny {
                for x in 0..<nx where x == 0 || y == 0 || z == 0
                    || x == nx - 1 || y == ny - 1 || z == nz - 1 {
                    density[index(x, y, z)] = 0
                }
            }
        }

        var vertices: [Vector3] = []
        var normals: [Vector3] = []
        vertices.reserveCapacity(30_000)
        normals.reserveCapacity(30_000)
        for z in 0..<(nz - 1) {
            for y in 0..<(ny - 1) {
                for x in 0..<(nx - 1) {
                    var positions: [Vector3] = []
                    var values: [Double] = []
                    var gradients: [Vector3] = []
                    positions.reserveCapacity(8)
                    values.reserveCapacity(8)
                    gradients.reserveCapacity(8)
                    for (dx, dy, dz) in corners {
                        let xx = x + dx, yy = y + dy, zz = z + dz
                        positions.append(.init(x: Double(xx) * h,
                                               y: Double(yy) * h,
                                               z: Double(zz) * h))
                        values.append(density[index(xx, yy, zz)])
                        gradients.append(normal(at: xx, yy, zz, density: density))
                    }
                    guard let minimum = values.min(), let maximum = values.max(),
                          minimum < iso, maximum >= iso else { continue }
                    for tetra in tetrahedra {
                        let inside = tetra.filter { values[$0] >= iso }
                        let outside = tetra.filter { values[$0] < iso }
                        if inside.count == 1 {
                            let a = inside[0]
                            appendTriangle(edge(a, outside[0], positions, values, gradients),
                                           edge(a, outside[1], positions, values, gradients),
                                           edge(a, outside[2], positions, values, gradients),
                                           vertices: &vertices, normals: &normals)
                        } else if inside.count == 3 {
                            let a = outside[0]
                            appendTriangle(edge(a, inside[0], positions, values, gradients),
                                           edge(a, inside[1], positions, values, gradients),
                                           edge(a, inside[2], positions, values, gradients),
                                           vertices: &vertices, normals: &normals)
                        } else if inside.count == 2 {
                            let a = inside[0], b = inside[1]
                            let c = outside[0], d = outside[1]
                            let ac = edge(a, c, positions, values, gradients)
                            let ad = edge(a, d, positions, values, gradients)
                            let bc = edge(b, c, positions, values, gradients)
                            let bd = edge(b, d, positions, values, gradients)
                            appendTriangle(ac, ad, bc, vertices: &vertices, normals: &normals)
                            appendTriangle(ad, bd, bc, vertices: &vertices, normals: &normals)
                        }
                    }
                }
            }
        }
        return .init(vertices: vertices, normals: normals)
    }

    private static func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
        x + nx * (y + ny * z)
    }

    private static func blur(_ source: [Double], axis: Int) -> [Double] {
        var result = source
        for z in 0..<nz {
            for y in 0..<ny {
                for x in 0..<nx {
                    var total = source[index(x, y, z)] * 2
                    var weight = 2.0
                    for direction in [-1, 1] {
                        let xx = x + (axis == 0 ? direction : 0)
                        let yy = y + (axis == 1 ? direction : 0)
                        let zz = z + (axis == 2 ? direction : 0)
                        if (0..<nx).contains(xx), (0..<ny).contains(yy), (0..<nz).contains(zz) {
                            total += source[index(xx, yy, zz)]
                            weight += 1
                        }
                    }
                    result[index(x, y, z)] = total / weight
                }
            }
        }
        return result
    }

    private static func normal(at x: Int, _ y: Int, _ z: Int,
                               density: [Double]) -> Vector3 {
        let left = density[index(max(0, x - 1), y, z)]
        let right = density[index(min(nx - 1, x + 1), y, z)]
        let below = density[index(x, max(0, y - 1), z)]
        let above = density[index(x, min(ny - 1, y + 1), z)]
        let back = density[index(x, y, max(0, z - 1))]
        let front = density[index(x, y, min(nz - 1, z + 1))]
        return Vector3(x: left - right, y: below - above, z: back - front).normalized
    }

    private static func edge(_ a: Int, _ b: Int, _ points: [Vector3],
                             _ values: [Double], _ gradients: [Vector3]) -> SurfaceVertex {
        let span = values[b] - values[a]
        let t = abs(span) > 0.000001 ? min(1, max(0, (iso - values[a]) / span)) : 0.5
        return .init(position: points[a] + (points[b] - points[a]) * t,
                     normal: (gradients[a] * (1 - t) + gradients[b] * t).normalized)
    }

    private static func appendTriangle(_ a: SurfaceVertex, _ b: SurfaceVertex,
                                       _ c: SurfaceVertex, vertices: inout [Vector3],
                                       normals: inout [Vector3]) {
        let face = Vector3.cross(b.position - a.position, c.position - a.position)
        guard face.lengthSquared > 1e-12 else { return }
        let outward = a.normal + b.normal + c.normal
        if Vector3.dot(face, outward) >= 0 {
            vertices.append(contentsOf: [a.position, b.position, c.position])
            normals.append(contentsOf: [a.normal, b.normal, c.normal])
        } else {
            vertices.append(contentsOf: [a.position, c.position, b.position])
            normals.append(contentsOf: [a.normal, c.normal, b.normal])
        }
    }
}
