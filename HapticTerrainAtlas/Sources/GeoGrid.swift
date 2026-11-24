import Foundation

struct GeoPoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct GeoSample: Equatable, Sendable {
    let point: GeoPoint
    let elevationMetres: Double
    let reliefMetres: Double
    let slopeMetresPerKilometre: Double
    let temperatureCelsius: Double
    let precipitationMillimetres: Double
    let snowfallCentimetres: Double?
    let windKilometresPerHour: Double
    let windGustKilometresPerHour: Double?
    let cloudCoverPercent: Int?
    let weatherCode: Int?
}

struct GeoGrid: Sendable {
    let centre: GeoPoint
    let latitudeSpan: Double
    let longitudeSpan: Double
    let weatherTimeUTC: String?
    let weatherIntervalSeconds: Int?
    let samples: [GeoSample]

    static func points(around centre: GeoPoint, latitudeSpan: Double, longitudeSpan: Double) -> [GeoPoint] {
        (-1...1).flatMap { row in
            (-1...1).map { column in
                GeoPoint(latitude: centre.latitude + Double(row) * latitudeSpan / 3,
                         longitude: centre.longitude + Double(column) * longitudeSpan / 3)
            }
        }
    }

    func nearest(to point: GeoPoint) -> GeoSample? {
        guard abs(point.latitude - centre.latitude) <= latitudeSpan / 2,
              abs(point.longitude - centre.longitude) <= longitudeSpan / 2 else { return nil }
        return samples.min { first, second in
            distanceSquared(first.point, point) < distanceSquared(second.point, point)
        }
    }

    private func distanceSquared(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let latitude = (a.latitude - b.latitude) * 111
        let longitude = (a.longitude - b.longitude) * 111 * cos(centre.latitude * .pi / 180)
        return latitude * latitude + longitude * longitude
    }
}

enum GeoDataError: LocalizedError {
    case invalidResponse
    case missingValues

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The data service returned an invalid response."
        case .missingValues: "The data service returned an incomplete grid."
        }
    }
}

struct ElevationResponse: Decodable {
    let elevation: [Double]
}

struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let time: String?
        let interval: Int?
        let temperature_2m: Double
        let precipitation: Double
        let snowfall: Double?
        let wind_speed_10m: Double
        let wind_gusts_10m: Double?
        let cloud_cover: Int?
        let weather_code: Int?
    }
    let current: Current
}

enum GeoGridBuilder {
    static func build(centre: GeoPoint, latitudeSpan: Double, longitudeSpan: Double,
                      elevations: [Double], weather: [WeatherResponse]) throws -> GeoGrid {
        let points = GeoGrid.points(around: centre, latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan)
        guard elevations.count == points.count, weather.count == points.count else {
            throw GeoDataError.missingValues
        }
        let samples = points.indices.map { index in
            let row = index / 3
            let column = index % 3
            let neighbours = points.indices.filter { other in
                other != index && abs(other / 3 - row) <= 1 && abs(other % 3 - column) <= 1
            }
            let mean = neighbours.reduce(0.0) { $0 + elevations[$1] } / Double(neighbours.count)
            let slope = neighbours.map { other in
                let latitudeKm = (points[index].latitude - points[other].latitude) * 111
                let longitudeKm = (points[index].longitude - points[other].longitude)
                    * 111 * cos(centre.latitude * .pi / 180)
                let distanceKm = max(0.09, hypot(latitudeKm, longitudeKm))
                return abs(elevations[index] - elevations[other]) / distanceKm
            }.max() ?? 0
            return GeoSample(point: points[index], elevationMetres: elevations[index],
                      reliefMetres: elevations[index] - mean,
                      slopeMetresPerKilometre: slope,
                      temperatureCelsius: weather[index].current.temperature_2m,
                      precipitationMillimetres: weather[index].current.precipitation,
                      snowfallCentimetres: weather[index].current.snowfall,
                      windKilometresPerHour: weather[index].current.wind_speed_10m,
                      windGustKilometresPerHour: weather[index].current.wind_gusts_10m,
                      cloudCoverPercent: weather[index].current.cloud_cover,
                      weatherCode: weather[index].current.weather_code)
        }
        return GeoGrid(centre: centre, latitudeSpan: latitudeSpan,
                       longitudeSpan: longitudeSpan,
                       weatherTimeUTC: weather.first?.current.time,
                       weatherIntervalSeconds: weather.first?.current.interval,
                       samples: samples)
    }
}
