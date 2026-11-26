import AppKit
import SwiftUI

@main
struct HapticBeatLabApp: App {
    @StateObject private var model = BeatGameModel()

    var body: some Scene {
        WindowGroup("Haptic Beat Lab") {
            BeatWorkspace(model: model)
                .frame(minWidth: 920, minHeight: 620)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    model.stop()
                }
                .onDisappear { model.stopOutput() }
        }
        .windowStyle(.titleBar)
    }
}

private struct BeatWorkspace: View {
    @ObservedObject var model: BeatGameModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("HAPTIC BEAT LAB")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.purple)
                Text("Find the beat.\nFeel the hit.")
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                Text("Click each circle when its approach ring reaches the border.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                Picker("Haptic mode", selection: $model.mode) {
                    ForEach(BeatMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.mode == .guide
                     ? "Guide: low to high pitch gives left to right and down to up. The texture grows stronger nearby."
                     : "Augment: pulses mark the approaching beat. Hit quality adds a distinct impact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.isPlaying ? "Restart round" : "Start round") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                Divider()
                Toggle("Trackpad haptics", isOn: $model.hapticsEnabled)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text("\(Int(model.strength * 100))%")
                            .monospacedDigit()
                    }
                    Slider(value: $model.strength, in: 0.15...0.50)
                }
                Text(model.outputStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("A short, original target sequence. No music or osu! assets are used.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(width: 300)
            .background(.white)

            VStack(spacing: 0) {
                HStack {
                    metric("SCORE", model.score)
                    metric("COMBO", model.combo)
                    metric("MISSES", model.misses)
                    Spacer()
                    Text("\(min(model.targetIndex + 1, BeatSequence.targets.count))/\(BeatSequence.targets.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                BeatCanvasView(model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .padding(.horizontal, 16)
                HStack {
                    Text(model.message)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.purple)
                    Spacer()
                    Text(model.mode == .guide ? "PROXIMITY + TIMING" : "TIMING + IMPACT")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .frame(height: 49)
            }
            .background(Color(red: 0.965, green: 0.96, blue: 0.98))
        }
        .preferredColorScheme(.light)
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)").font(.system(size: 17, weight: .bold, design: .monospaced))
        }
        .frame(width: 85, alignment: .leading)
    }
}
