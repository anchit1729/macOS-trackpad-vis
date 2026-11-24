import AppKit
import MapKit
import SwiftUI

final class TrackingMapView: MKMapView {
    var onPoint: ((GeoPoint?) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        area = NSTrackingArea(rect: .zero,
                              options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
        if let area { addTrackingArea(area) }
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let coordinate = convert(point, toCoordinateFrom: self)
        onPoint?(GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPoint?(nil)
        super.mouseExited(with: event)
    }
}

struct AtlasMapView: NSViewRepresentable {
    @ObservedObject var model: AtlasModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> TrackingMapView {
        let map = TrackingMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        map.showsCompass = true
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 51.1784, longitude: -115.5708),
                                         span: MKCoordinateSpan(latitudeDelta: 0.23, longitudeDelta: 0.30)), animated: false)
        map.onPoint = { [weak model] point in model?.explore(point) }
        return map
    }

    func updateNSView(_ map: TrackingMapView, context: Context) {
        guard context.coordinator.lastSamples != model.grid?.samples || context.coordinator.lastLayer != model.layer else { return }
        context.coordinator.lastSamples = model.grid?.samples
        context.coordinator.lastLayer = model.layer
        map.removeAnnotations(map.annotations)
        guard let grid = model.grid else { return }
        let annotations = grid.samples.enumerated().map { index, sample in
            SampleAnnotation(index: index, sample: sample)
        }
        map.addAnnotations(annotations)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let model: AtlasModel
        var lastSamples: [GeoSample]?
        var lastLayer: MapLayer?

        init(model: AtlasModel) { self.model = model }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let region = mapView.region
            model.setViewport(centre: GeoPoint(latitude: region.center.latitude, longitude: region.center.longitude),
                              latitudeSpan: region.span.latitudeDelta, longitudeSpan: region.span.longitudeDelta)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let sample = annotation as? SampleAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "sample") as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: sample, reuseIdentifier: "sample")
            view.annotation = sample
            let kind = HapticClipLibrary.kind(for: sample.sample, layer: model.layer)
            view.markerTintColor = switch kind {
            case .lowland: .systemGreen
            case .incline: .systemBrown
            case .ridge: .systemOrange
            case .cliff: .systemRed
            case .basin: .systemIndigo
            case .clear: .systemYellow
            case .cloudy: .systemGray
            case .fog: .systemGray
            case .drizzle: .systemCyan
            case .rain: .systemBlue
            case .downpour: .systemIndigo
            case .snow: .systemCyan
            case .wind: .systemTeal
            case .gust: .systemPurple
            case .thunder: .systemPurple
            case .frost: .systemBlue
            case .heat: .systemOrange
            }
            view.glyphText = kind.glyph
            view.canShowCallout = false
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? SampleAnnotation else { return }
            model.select(annotation.sample)
        }
    }
}

final class SampleAnnotation: NSObject, MKAnnotation {
    let index: Int
    let sample: GeoSample
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: sample.point.latitude, longitude: sample.point.longitude)
    }

    init(index: Int, sample: GeoSample) {
        self.index = index
        self.sample = sample
    }
}
