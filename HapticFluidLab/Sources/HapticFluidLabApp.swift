import AppKit
import SwiftUI

enum FluidViewMode: String, CaseIterable, Identifiable {
    case twoD = "2D"
    case threeD = "3D"

    var id: String { rawValue }
}

@MainActor
final class FluidLabModel: ObservableObject {
    @Published var viewMode: FluidViewMode = .threeD {
        didSet { receive(nil) }
    }
    @Published var scene: FluidScene = .damBreak
    @Published var playing = true
    @Published var flipRatio = 0.88
    @Published var showGrid = false
    @Published var showVectors = false
    @Published var resetVersion = 0
    @Published var cameraResetVersion = 0
    @Published var hapticsEnabled = false {
        didSet {
            if hapticsEnabled { output.enable() }
            else { output.disable() }
            outputStatus = output.status
        }
    }
    @Published var strength = 0.42
    @Published var hapticMetric: HapticMetric = .kineticEnergy {
        didSet { updateOutput() }
    }
    @Published private(set) var sample: LocalFluidSample?
    @Published private(set) var simulationFPS = 0.0
    @Published private(set) var triangleCount = 0
    @Published private(set) var outputStatus = "Off"
    private let output = FluidTrackpadOutput()
    private var appActive = true

    func receive(_ value: LocalFluidSample?) {
        sample = value
        updateOutput()
    }

    func receiveFPS(_ value: Double) { simulationFPS = value }
    func receiveTriangles(_ value: Int) { triangleCount = value }

    func setAppActive(_ active: Bool) {
        appActive = active
        updateOutput()
    }

    func updateOutput() {
        guard hapticsEnabled, appActive, let sample else {
            output.stop()
            return
        }
        output.update(FluidHapticMapping.response(
            for: sample, metric: hapticMetric, strength: strength))
    }

    func stopOutput() { output.stop() }
}

@main
struct HapticFluidLabApp: App {
    @StateObject private var model = FluidLabModel()

    var body: some Scene {
        WindowGroup("Haptic Fluid Lab") {
            FluidLabView(model: model)
                .frame(minWidth: 1050, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willResignActiveNotification)) { _ in
                        model.setAppActive(false)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                        model.setAppActive(true)
                }
                .onDisappear { model.stopOutput() }
        }
        .windowResizability(.contentMinSize)
    }
}

private struct FluidLabView: View {
    @ObservedObject var model: FluidLabModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("FLUID LAB")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.cyan)
                Text("Feel the flow")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(model.viewMode == .threeD
                     ? "Move over the water to feel it. Drag to orbit the camera."
                     : "Move the pointer over water. Drag inside the tank to stir it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("View", selection: $model.viewMode) {
                    ForEach(FluidViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Divider()
                Text("SCENE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(FluidScene.allCases) { scene in
                    Button {
                        model.scene = scene
                        model.receive(nil)
                    } label: {
                        HStack {
                            Text(scene.rawValue)
                            Spacer()
                            if model.scene == scene { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(model.scene == scene ? .cyan : .gray)
                    .accessibilityLabel("Show \(scene.rawValue) simulation")
                }
                Text(model.scene.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(model.playing ? "Pause" : "Play") {
                        model.playing.toggle()
                    }
                    Button("Reset") { model.resetVersion += 1 }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("FLIP blend")
                        Spacer()
                        Text("\(Int(model.flipRatio * 100))%")
                            .monospacedDigit()
                    }
                    Slider(value: $model.flipRatio, in: 0...1)
                    Text("0% PIC smooths flow. 100% FLIP keeps motion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.viewMode == .twoD {
                    Toggle("Show grid", isOn: $model.showGrid)
                    Toggle("Show flow vectors", isOn: $model.showVectors)
                } else {
                    Button("Reset camera") { model.cameraResetVersion += 1 }
                    Text("Drag to orbit. Scroll or pinch to zoom. Two fingers pan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Trackpad haptics", isOn: $model.hapticsEnabled)
                Picker("Feel", selection: $model.hapticMetric) {
                    ForEach(HapticMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text("\(Int(model.strength * 100))%")
                            .monospacedDigit()
                    }
                    Slider(value: $model.strength, in: 0.15...0.55)
                        .onChange(of: model.strength) { _, _ in model.updateOutput() }
                }
                Text(model.outputStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            }
            .frame(width: 295)
            .background(Color(nsColor: .windowBackgroundColor))

            VStack(spacing: 0) {
                if model.viewMode == .threeD {
                    Fluid3DCanvasView(scene: model.scene, playing: model.playing,
                                      flipRatio: model.flipRatio,
                                      resetVersion: model.resetVersion,
                                      cameraResetVersion: model.cameraResetVersion,
                                      onSample: { model.receive($0) },
                                      onFPS: { model.receiveFPS($0) },
                                      onTriangles: { model.receiveTriangles($0) })
                        .background(Color.black)
                } else {
                    FluidCanvasView(scene: model.scene, playing: model.playing,
                                    flipRatio: model.flipRatio, showGrid: model.showGrid,
                                    showVectors: model.showVectors,
                                    resetVersion: model.resetVersion,
                                    onSample: { model.receive($0) },
                                    onFPS: { model.receiveFPS($0) })
                        .background(Color.black)
                }
                HStack {
                    Circle().fill((model.sample?.particleCount ?? 0) > 0 ? .cyan : .gray)
                        .frame(width: 8, height: 8)
                    Text(model.hapticMetric == .pressure ? "Local pressure" : "Local energy")
                    Text(String(format: "%.3f", model.hapticMetric == .pressure
                                ? model.sample?.pressureMagnitude ?? 0
                                : model.sample?.kineticEnergy ?? 0))
                        .monospacedDigit()
                    Spacer()
                    Text(model.viewMode == .threeD
                         ? "\(Int(model.simulationFPS.rounded())) fps · \(model.triangleCount) triangles"
                         : "\(Int(model.simulationFPS.rounded())) fps · 48 × 36 grid")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}
