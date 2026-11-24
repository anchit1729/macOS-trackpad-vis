import AppKit
import SwiftUI

@main
struct HapticDocumentReaderApp: App {
    @StateObject private var model = ReaderModel()

    var body: some Scene {
        WindowGroup("Haptic Document Reader") {
            ReaderWorkspace(model: model)
                .frame(minWidth: 740, minHeight: 600)
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

private struct ReaderWorkspace: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("HAPTIC DOCUMENT READER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(model.document.title)
                        .font(.system(size: 31, weight: .semibold, design: .serif))
                    Text(model.document.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text("MOVE OVER THE WORDS · SCROLL TO EXPLORE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    Text("Some passages have a hidden haptic layer. No marks show their locations.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)

            ReaderPageView(model: model)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 30)

            HStack(spacing: 20) {
                Toggle("Trackpad haptics", isOn: $model.hapticsEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()
                Text("Strength")
                    .font(.system(size: 12))
                Slider(value: $model.strength, in: 0.15...0.50)
                    .frame(width: 150)
                    .tint(.purple)
                Text("\(Int(model.strength * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.outputStatus)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .frame(height: 72)
        }
        .background(Color(red: 0.965, green: 0.96, blue: 0.97))
        .preferredColorScheme(.light)
    }
}
