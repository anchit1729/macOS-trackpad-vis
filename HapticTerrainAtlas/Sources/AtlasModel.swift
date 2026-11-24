import AppKit
import MapKit
import SwiftUI

@MainActor
final class AtlasModel: ObservableObject {
    @Published var grid: GeoGrid?
    @Published var selected: GeoSample?
    @Published var layer: MapLayer = .both { didSet { refreshTexture() } }
    @Published var hapticsEnabled = false
    @Published var intensity = HapticIntensity.standard { didSet { refreshTexture() } }
    @Published var previewingCue: CueKind?
    @Published var status = "Load the visible map to explore live data."
    @Published var isLoading = false

    private(set) var viewportCentre = GeoPoint(latitude: 51.1784, longitude: -115.5708)
    private(set) var latitudeSpan = 0.23
    private(set) var longitudeSpan = 0.30
    private var hoveredSample: GeoSample?
    private var lastPointerAt = -Double.infinity
    private var idleTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private let player = TrackpadClipPlayer()

    var motorStatus: String {
        guard hapticsEnabled else { return "Haptics off" }
        return player.usesExpressiveMotor ? "Audio-derived trackpad tones · 100–4,000 Hz" : "Standard taps; audio tones unavailable"
    }

    func setViewport(centre: GeoPoint, latitudeSpan: Double, longitudeSpan: Double) {
        viewportCentre = centre
        self.latitudeSpan = max(0.01, min(2, latitudeSpan))
        self.longitudeSpan = max(0.01, min(2, longitudeSpan))
    }

    func load() {
        guard !isLoading else { return }
        pause()
        isLoading = true
        status = "Loading elevation and current weather…"
        let centre = viewportCentre
        let latSpan = latitudeSpan
        let lonSpan = longitudeSpan
        Task {
            do {
                let result = try await OpenMeteoGridSource().load(centre: centre,
                                                                   latitudeSpan: latSpan,
                                                                   longitudeSpan: lonSpan)
                grid = result
                selected = result.nearest(to: centre)
                status = "Live grid loaded. Move across the map to feel its texture."
            } catch {
                status = "Data could not load: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func setHaptics(_ enabled: Bool) {
        hapticsEnabled = enabled
        if enabled {
            player.enable()
            refreshTexture()
        } else {
            pause()
            player.disable()
        }
        objectWillChange.send()
    }

    func explore(_ point: GeoPoint?) {
        guard let point, let grid, let sample = grid.nearest(to: point) else {
            pause()
            return
        }
        if selected != sample { selected = sample }
        hoveredSample = sample
        lastPointerAt = ProcessInfo.processInfo.systemUptime
        refreshTexture()
        if hapticsEnabled { startIdleWatchdog() }
    }

    func select(_ sample: GeoSample) {
        selected = sample
        hoveredSample = sample
        lastPointerAt = ProcessInfo.processInfo.systemUptime
        refreshTexture()
        if hapticsEnabled { startIdleWatchdog() }
    }

    func preview() {
        guard hapticsEnabled, let selected else { return }
        preview(HapticClipLibrary.kind(for: selected, layer: layer))
    }

    func preview(_ kind: CueKind) {
        guard hapticsEnabled else { return }
        previewTask?.cancel()
        previewingCue = kind
        let milliseconds = player.preview(kind, intensity: intensity)
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(milliseconds)))
            if !Task.isCancelled { previewingCue = nil }
        }
    }

    func pause() {
        hoveredSample = nil
        previewTask?.cancel()
        previewTask = nil
        previewingCue = nil
        idleTask?.cancel()
        idleTask = nil
        player.stop()
    }

    private func refreshTexture() {
        guard hapticsEnabled, let hoveredSample, NSApp.isActive,
              !HapticActivityPolicy.shouldStop(lastInput: lastPointerAt,
                                               now: ProcessInfo.processInfo.systemUptime) else { return }
        let kind = HapticClipLibrary.kind(for: hoveredSample, layer: layer)
        player.sustain(kind, intensity: intensity * HapticClipLibrary.drive(for: hoveredSample, kind: kind))
    }

    private func startIdleWatchdog() {
        guard idleTask == nil else { return }
        idleTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if HapticActivityPolicy.shouldStop(lastInput: lastPointerAt,
                                                   now: ProcessInfo.processInfo.systemUptime) {
                    pause()
                    return
                }
            }
        }
    }
}
