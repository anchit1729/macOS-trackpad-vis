import AppKit
import SceneKit
import SwiftUI

@MainActor
final class Fluid3DCanvas: SCNView {
    var fluidScene: FluidScene = .damBreak
    var resetVersion = 0
    var flipRatio = 0.88
    var playing = true
    var onSample: (LocalFluidSample?) -> Void = { _ in }
    var onFPS: (Double) -> Void = { _ in }
    var onTriangles: (Int) -> Void = { _ in }

    private let engine = Fluid3DEngine()
    private let waterNode = SCNNode()
    private let cameraNode = SCNNode()
    private let waterMaterial = SCNMaterial()
    private var currentFrame: Fluid3DFrame?
    private nonisolated(unsafe) var timer: Timer?
    private var tracking: NSTrackingArea?
    private var pointer: CGPoint?
    private var stepInFlight = false
    private var lastFrameTime: TimeInterval?

    override init(frame: NSRect) {
        super.init(frame: frame, options: nil)
        setupScene()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    deinit { timer?.invalidate() }

    private func setupScene() {
        let scene = SCNScene()
        scene.background.contents = NSColor.black
        backgroundColor = .black
        self.scene = scene
        allowsCameraControl = true
        preferredFramesPerSecond = 30
        antialiasingMode = .multisampling4X
        isPlaying = true

        waterMaterial.lightingModel = .physicallyBased
        waterMaterial.diffuse.contents = NSColor(calibratedRed: 0.015, green: 0.16,
                                                 blue: 0.28, alpha: 1)
        waterMaterial.roughness.contents = 0.10
        waterMaterial.metalness.contents = 0.02
        waterMaterial.selfIllumination.contents = NSColor(calibratedRed: 0.0, green: 0.012,
                                                          blue: 0.025, alpha: 1)
        waterMaterial.isDoubleSided = true
        waterMaterial.shaderModifiers = [.fragment: """
            vec3 n = normalize(_surface.normal);
            vec3 v = normalize(_surface.view);
            float facing = abs(dot(n, v));
            float rim = pow(1.0 - facing, 3.0);
            vec3 lightDirection = normalize(vec3(0.35, 0.75, 0.55));
            float diffuse = 0.35 + 0.65 * max(0.0, dot(n, lightDirection));
            float highlight = pow(max(0.0, dot(reflect(-lightDirection, n), v)), 70.0);
            _output.color.rgb = vec3(0.018, 0.13, 0.24) * diffuse
                              + rim * vec3(0.07, 0.24, 0.32)
                              + highlight * vec3(0.70, 0.85, 1.0);
            """]
        scene.rootNode.addChildNode(waterNode)

        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = NSColor(calibratedRed: 0.018, green: 0.055,
                                                blue: 0.080, alpha: 1)
        floorMaterial.roughness.contents = 0.7
        let floor = SCNNode(geometry: SCNPlane(width: Fluid3DSimulation.width,
                                                height: Fluid3DSimulation.depth))
        floor.geometry?.firstMaterial = floorMaterial
        floor.eulerAngles.x = -.pi / 2
        floor.position = .init(Float(Fluid3DSimulation.width / 2), 0.002,
                               Float(Fluid3DSimulation.depth / 2))
        scene.rootNode.addChildNode(floor)

        let edgeMaterial = SCNMaterial()
        edgeMaterial.diffuse.contents = NSColor(calibratedRed: 0.22, green: 0.63,
                                               blue: 0.72, alpha: 0.26)
        edgeMaterial.lightingModel = .constant
        edgeMaterial.blendMode = .alpha
        let width = CGFloat(Fluid3DSimulation.width)
        let height = CGFloat(Fluid3DSimulation.height)
        let depth = CGFloat(Fluid3DSimulation.depth)
        for y in [0.0, height] {
            for z in [0.0, depth] {
                addEdge(size: .init(width: width, height: 0.003), depth: 0.003,
                        at: .init(Float(width / 2), Float(y), Float(z)),
                        material: edgeMaterial, scene: scene)
            }
        }
        for x in [0.0, width] {
            for z in [0.0, depth] {
                addEdge(size: .init(width: 0.003, height: height), depth: 0.003,
                        at: .init(Float(x), Float(height / 2), Float(z)),
                        material: edgeMaterial, scene: scene)
            }
            for y in [0.0, height] {
                addEdge(size: .init(width: 0.003, height: 0.003), depth: depth,
                        at: .init(Float(x), Float(y), Float(depth / 2)),
                        material: edgeMaterial, scene: scene)
            }
        }

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.color = NSColor(calibratedRed: 0.73, green: 0.94, blue: 1,
                                   alpha: 1)
        key.light?.intensity = 700
        key.position = .init(0.15, 1.8, 1.2)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.color = NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.8,
                                    alpha: 1)
        fill.light?.intensity = 350
        fill.position = .init(1.5, 0.9, -0.7)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedWhite: 0.08, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 46
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 10
        scene.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        resetCamera()
    }

    private func addEdge(size: CGSize, depth: CGFloat, at position: SCNVector3,
                         material: SCNMaterial, scene: SCNScene) {
        let geometry = SCNBox(width: size.width, height: size.height,
                              length: depth, chamferRadius: 0)
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    func resetCamera() {
        cameraNode.position = .init(1.8, 1.55, 1.8)
        cameraNode.look(at: .init(0.6, 0.27, 0.4))
        pointOfView = cameraNode
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited,
                                .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        samplePointer()
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        onSample(nil)
        super.mouseExited(with: event)
    }

    private func tick() {
        guard !stepInFlight else { return }
        stepInFlight = true
        let selected = fluidScene
        let reset = resetVersion
        let playing = playing
        let flip = flipRatio
        Task { [weak self] in
            guard let self else { return }
            let next = await engine.advance(scene: selected, resetVersion: reset,
                                            playing: playing, flipRatio: flip)
            currentFrame = next
            install(next.surface)
            stepInFlight = false
            let now = ProcessInfo.processInfo.systemUptime
            if let lastFrameTime { onFPS(min(30, 1 / max(0.001, now - lastFrameTime))) }
            lastFrameTime = now
            onTriangles(next.surface.triangleCount)
            samplePointer()
        }
    }

    private func install(_ mesh: FluidSurfaceMesh) {
        guard !mesh.vertices.isEmpty else { waterNode.geometry = nil; return }
        let vertices = mesh.vertices.map {
            SCNVector3(Float($0.x), Float($0.y), Float($0.z))
        }
        let normals = mesh.normals.map {
            SCNVector3(Float($0.x), Float($0.y), Float($0.z))
        }
        let indices = (0..<vertices.count).map(UInt32.init)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                             SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices,
                                                                  primitiveType: .triangles)])
        geometry.firstMaterial = waterMaterial
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        waterNode.geometry = geometry
        SCNTransaction.commit()
    }

    private func samplePointer() {
        guard let pointer, let currentFrame else { onSample(nil); return }
        guard let hit = hitTest(pointer, options: nil).first(where: { $0.node === waterNode }) else {
            onSample(nil)
            return
        }
        let point = hit.worldCoordinates
        let normal = hit.worldNormal
        let inward = Vector3(x: Double(point.x - normal.x * 0.055),
                             y: Double(point.y - normal.y * 0.055),
                             z: Double(point.z - normal.z * 0.055))
        onSample(currentFrame.sample(near: inward))
    }
}

struct Fluid3DCanvasView: NSViewRepresentable {
    let scene: FluidScene
    let playing: Bool
    let flipRatio: Double
    let resetVersion: Int
    let cameraResetVersion: Int
    let onSample: (LocalFluidSample?) -> Void
    let onFPS: (Double) -> Void
    let onTriangles: (Int) -> Void

    final class Coordinator { var cameraResetVersion = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Fluid3DCanvas { Fluid3DCanvas(frame: .zero) }

    func updateNSView(_ view: Fluid3DCanvas, context: Context) {
        view.onSample = onSample
        view.onFPS = onFPS
        view.onTriangles = onTriangles
        view.fluidScene = scene
        view.playing = playing
        view.flipRatio = flipRatio
        view.resetVersion = resetVersion
        if context.coordinator.cameraResetVersion != cameraResetVersion {
            view.resetCamera()
            context.coordinator.cameraResetVersion = cameraResetVersion
        }
    }
}
