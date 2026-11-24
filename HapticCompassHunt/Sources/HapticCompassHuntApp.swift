import AppKit
import SwiftUI

@main
struct HapticCompassHuntApp: App {
    @StateObject private var model = HuntGameModel()

    var body: some Scene {
        WindowGroup("Haptic Compass Hunt") {
            HuntView(model: model)
                .frame(minWidth: 1050, minHeight: 680)
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

private struct HuntView: View {
    @ObservedObject var model: HuntGameModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("HAPTIC COMPASS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.cyan)
                Text("Find the hidden point")
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Move through the field. Follow the trackpad cues until you reach the point.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()
                HStack {
                    Image(systemName: model.phase == .found ? "checkmark.circle.fill"
                          : "scope")
                        .font(.title2)
                        .foregroundStyle(model.phase == .found ? .green : .cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.phase == .found ? "Signal found" :
                             model.phase == .searching ? "Searching" : "Ready to search")
                            .font(.headline)
                        Text(model.phase == .found
                             ? "Round \(model.round) · \(model.foundSeconds ?? 1) s"
                             : "Round \(model.round) · target hidden")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                Button(model.phase == .found ? "Find another point" : "New location") {
                    model.newRound()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .keyboardShortcut("n", modifiers: [.command])

                Divider()
                Toggle("Trackpad cues", isOn: $model.hapticsEnabled)
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

                Text("READ THE CUES")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                cueRow(number: "01", title: "Horizontal",
                       detail: model.usesExpressiveMotor
                           ? "Low pitch: left · high pitch: right"
                           : "Two taps: left · one tap: right")
                cueRow(number: "02", title: "Vertical",
                       detail: model.usesExpressiveMotor
                           ? "Low pitch: down · high pitch: up"
                           : "Two taps: down · one tap: up")
                cueRow(number: "↗", title: "Proximity",
                       detail: model.usesExpressiveMotor
                           ? "The steady texture grows deeper and faster nearby."
                           : "Faster pulses mean closer.")
                Text("Two accents in the texture show direction and axis distance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(width: 330)
            .background(Color(nsColor: .windowBackgroundColor))

            VStack(spacing: 0) {
                HStack {
                    Text(model.phase == .found ? "LOCATION REVEALED" : "LOCATION HIDDEN")
                        .tracking(1.4)
                    Spacer()
                    Text("MOVE THE POINTER")
                        .tracking(1.4)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background(Color.black)

                HuntCanvasView(target: model.target,
                               found: model.phase == .found,
                               proximity: model.cue?.proximity ?? 0,
                               round: model.round,
                               onPointer: { model.pointerMoved($0, size: $1) })
                    .background(Color.black)

                HStack {
                    Circle()
                        .fill(model.phase == .found ? .green : .cyan)
                        .frame(width: 7, height: 7)
                    Text(model.phase == .found ? "Point acquired" :
                         model.phase == .searching ? "Follow both pulses" :
                         "Enter the field to begin")
                    Spacer()
                    Text("⌘N  NEW POINT")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background(Color.black)
            }
        }
    }

    private func cueRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
