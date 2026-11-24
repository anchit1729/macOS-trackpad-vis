import AppKit
import SwiftUI

private enum SidebarPanel: String, CaseIterable, Identifiable {
    case place = "Place"
    case gallery = "Texture gallery"
    var id: String { rawValue }
}

@main
struct HapticTerrainAtlasApp: App {
    @StateObject private var model = AtlasModel()
    @State private var panel: SidebarPanel = .place

    var body: some Scene {
        WindowGroup("Haptic Terrain Atlas") {
            HStack(spacing: 0) {
                AtlasMapView(model: model)
                    .frame(minWidth: 650, minHeight: 680)
                Divider()
                sidebar.frame(width: 360)
            }
            .frame(minWidth: 1_040, minHeight: 680)
            .onAppear { model.load() }
            .onDisappear { model.pause() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                model.pause()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Haptic Terrain Atlas").font(.title2.bold())
                Text("Explore a place by sight and touch.").foregroundStyle(.secondary)
            }

            Picker("Map layer", selection: $model.layer) {
                ForEach(MapLayer.allCases) { layer in Text(layer.rawValue).tag(layer) }
            }
            .pickerStyle(.segmented)

            HStack {
                Button(model.isLoading ? "Loading…" : "Load this view") { model.load() }
                    .disabled(model.isLoading)
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let time = model.grid?.weatherTimeUTC {
                Text("Weather model: \(time.replacingOccurrences(of: "T", with: " ")) UTC")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()
            Toggle("Trackpad haptics", isOn: Binding(get: { model.hapticsEnabled },
                                                       set: { model.setHaptics($0) }))
            Text(model.motorStatus).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Strength")
                Slider(value: $model.intensity,
                       in: HapticIntensity.minimum...HapticIntensity.maximum)
                Text("\(Int(model.intensity * 100))%")
                    .monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            .font(.subheadline)
            .disabled(!model.hapticsEnabled)
            Text("The selected data changes force. Feedback stops when you leave the map or pause for six seconds.")
                .font(.caption2).foregroundStyle(.secondary)

            Divider()
            Picker("Details", selection: $panel) {
                ForEach(SidebarPanel.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)

            ScrollView {
                if panel == .place { placePanel } else { galleryPanel }
            }
            .frame(maxHeight: .infinity)

            Text("Elevation: Copernicus DEM · Weather: Open-Meteo")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var placePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let sample = model.selected {
                let cue = HapticClipLibrary.kind(for: sample, layer: model.layer)
                HStack(alignment: .top, spacing: 10) {
                    Text(cue.glyph).font(.title).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cue.rawValue).font(.headline)
                        Text(cue.description).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.preview() } label: {
                        Image(systemName: "play.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .help("Preview this texture")
                    .disabled(!model.hapticsEnabled)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                Text(String(format: "Sample at %.4f°, %.4f°", sample.point.latitude, sample.point.longitude))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                metric("Elevation", String(format: "%.0f m", sample.elevationMetres))
                metric("Local relief", String(format: "%+.0f m", sample.reliefMetres))
                metric("Grid gradient", String(format: "%.0f m/km", sample.slopeMetresPerKilometre))
                Divider()
                metric("Temperature", String(format: "%.1f °C", sample.temperatureCelsius))
                let minutes = model.grid?.weatherIntervalSeconds.map { $0 / 60 }
                metric(minutes.map { "Precipitation (\($0) min)" } ?? "Precipitation",
                       String(format: "%.1f mm", sample.precipitationMillimetres))
                metric("Snowfall", sample.snowfallCentimetres.map { String(format: "%.1f cm", $0) } ?? "—")
                metric("Wind", String(format: "%.0f km/h", sample.windKilometresPerHour))
                metric("Gusts (past hour)", sample.windGustKilometresPerHour.map { String(format: "%.0f km/h", $0) } ?? "—")
                metric("Cloud cover", sample.cloudCoverPercent.map { "\($0)%" } ?? "—")
                metric("Weather", HapticClipLibrary.weatherKind(for: sample).rawValue)
                metric("Weather code", sample.weatherCode.map(String.init) ?? "—")
                metric("Data response", "\(Int(HapticClipLibrary.drive(for: sample, kind: cue) * 100))% of set strength")
                Text("Map markers show the cue selected by this layer. In Both mode, active weather takes priority.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Load the map, then move across it or select a marker.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var galleryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try every texture, even when the current weather is calm.")
                .font(.caption).foregroundStyle(.secondary)
            cueSection("Terrain", cues: CueKind.terrainCases)
            cueSection("Weather", cues: CueKind.weatherCases)
            Text("Each texture starts from generated audio. Two frequency peaks drive each 10 ms motor frame.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cueSection(_ title: String, cues: [CueKind]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            ForEach(cues) { cue in
                Button { model.preview(cue) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(cue.glyph).font(.title3).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cue.rawValue).font(.subheadline.bold())
                            Text(cue.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: model.previewingCue == cue ? "waveform" : "play.circle")
                            .foregroundStyle(model.previewingCue == cue ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!model.hapticsEnabled)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}
