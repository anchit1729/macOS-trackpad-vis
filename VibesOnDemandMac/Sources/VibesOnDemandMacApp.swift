import AppKit
import SwiftUI

@main
struct VibesOnDemandMacApp: App {
    @StateObject private var model = TraceModel()

    var body: some Scene {
        WindowGroup("Vibes on Demand") {
            TraceWorkspace(model: model)
                .frame(minWidth: 930, minHeight: 630)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    model.setAppActive(false)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.setAppActive(true)
                }
                .onDisappear { model.stopOutput() }
        }
        .windowStyle(.titleBar)
    }
}

private struct TraceWorkspace: View {
    @ObservedObject var model: TraceModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 290)
            Rectangle().fill(.black.opacity(0.08)).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text("EXPLORE THE SCATTERPLOT")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("36 SYNTHETIC POINTS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 25)
                .frame(height: 48)
                TraceCanvasView(model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                footer
                    .frame(height: 46)
            }
            .background(Color(red: 0.97, green: 0.965, blue: 0.975))
        }
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("VIBES ON DEMAND")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.purple)
            Text("Feel the\nshape of data.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineSpacing(0)
                .padding(.top, 15)
            Text("Each point contains a short time series. Touch it to reveal the shape through the trackpad.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)

            Divider().padding(.vertical, 24)
            sectionLabel("INTERACTION")
            instruction("Press and hold", "Play a trace. Release to close.")
            instruction("Click", "Pin a trace on screen.")
            instruction("Move over the chart", "Scrub the pinned trace.")
            instruction("Click away", "Close a pinned trace.")

            Divider().padding(.vertical, 21)
            sectionLabel("FEEDBACK")
            Toggle("Trackpad haptics", isOn: $model.hapticsEnabled)
                .toggleStyle(.switch)
                .padding(.top, 12)
            Toggle("Show line chart", isOn: $model.showLine)
                .toggleStyle(.switch)
                .padding(.top, 7)
            setting("Strength", value: $model.strength, range: 0.15...0.50,
                    display: "\(Int(model.strength * 100))%")
            setting("Trace duration", value: $model.duration, range: 0.5...2.5,
                    display: String(format: "%.1f s", model.duration))
            setting("Smoothing", value: $model.smoothing, range: 0...0.85,
                    display: "\(Int(model.smoothing * 100))%")
            Spacer(minLength: 15)
            Text(model.outputStatus)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Synthetic demo data · local only")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 7)
        }
        .padding(23)
        .background(.white)
    }

    private var footer: some View {
        HStack {
            Text(model.selectedSeries?.label ?? "Choose a point")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            if let selected = model.selectedSeries {
                Text("·  \(selected.shape.rawValue)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.selectedSeries != nil {
                Text("LEVEL  \(Int(model.currentValue * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 26)
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func instruction(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.top, 11)
    }

    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                         display: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            Slider(value: value, in: range)
                .tint(.purple)
        }
        .padding(.top, 11)
    }
}
