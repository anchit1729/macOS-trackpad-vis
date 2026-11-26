import AppKit
import SwiftUI

@main
struct HapticCodeReviewApp: App {
    @StateObject private var model = CodeReviewModel()

    var body: some Scene {
        WindowGroup("Haptic Code Review") {
            CodeWorkspace(model: model)
                .frame(minWidth: 980, minHeight: 620)
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

private struct CodeWorkspace: View {
    @ObservedObject var model: CodeReviewModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("HAPTIC CODE REVIEW")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.purple)
                Text("Feel what needs\nyour attention.")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                Text("Move down the code or scroll beneath the pointer. Each annotated line has its own texture.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open code") { model.openFile() }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    Button("Export copy") { model.saveCopy() }
                        .buttonStyle(.bordered)
                }
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
                Divider()
                Text("CUE KEY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                cueRow("Risk", "Three rough pulses")
                cueRow("Suggestion", "Rising sweep")
                cueRow("Question", "Wavering tone")
                cueRow("Test gap", "Hollow regular ticks")
                cueRow("To do", "Soft slow tick")
                Spacer(minLength: 8)
                Text(model.fileStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 294)
            .background(Color(red: 0.075, green: 0.082, blue: 0.105))

            VStack(spacing: 0) {
                HStack {
                    Text(model.documentTitle)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("\(model.annotationCount) HAPTIC NOTES")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .frame(height: 48)
                CodeEditorView(model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.activeAnnotation == nil ? "waveform" : "waveform.path")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.activeAnnotation.map { "LINE \($0.line) · \($0.kind.title.uppercased())" }
                             ?? "MOVE THROUGH THE CODE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Text(model.activeAnnotation?.message
                             ?? "Agent notes and code markers appear here when you reach their lines.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(17)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            }
            .background(Color(red: 0.09, green: 0.10, blue: 0.13))
        }
        .preferredColorScheme(.dark)
    }

    private func cueRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).frame(width: 80, alignment: .leading)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
