import XCTest
@testable import HapticTerrainAtlas

final class GeoGridTests: XCTestCase {
    func testGridHasNineDistinctPointsAndFindsNearest() throws {
        let centre = GeoPoint(latitude: 51.1784, longitude: -115.5708)
        let points = GeoGrid.points(around: centre, latitudeSpan: 0.15, longitudeSpan: 0.2)
        XCTAssertEqual(points.count, 9)
        XCTAssertEqual(points[4], centre)
        let current = WeatherResponse.Current(time: "2026-11-22T18:30", interval: 900,
                                              temperature_2m: 3,
                                              precipitation: 1.2, snowfall: 0,
                                              wind_speed_10m: 18, wind_gusts_10m: 24,
                                              cloud_cover: 70, weather_code: 61)
        let weather = Array(repeating: WeatherResponse(current: current), count: 9)
        let grid = try GeoGridBuilder.build(centre: centre, latitudeSpan: 0.15,
                                             longitudeSpan: 0.2, elevations: Array(0..<9).map(Double.init), weather: weather)
        XCTAssertEqual(grid.nearest(to: centre)?.elevationMetres, 4)
        XCTAssertNil(grid.nearest(to: GeoPoint(latitude: 52, longitude: -115.5708)))
        XCTAssertEqual(grid.weatherTimeUTC, "2026-11-22T18:30")
        XCTAssertEqual(grid.weatherIntervalSeconds, 900)
        XCTAssertEqual(grid.samples[4].weatherCode, 61)
        XCTAssertGreaterThan(grid.samples[4].slopeMetresPerKilometre, 0)
        XCTAssertEqual(Set(points.map { "\($0.latitude),\($0.longitude)" }).count, 9)
    }

    func testIncompleteGridIsRejected() {
        let centre = GeoPoint(latitude: 0, longitude: 0)
        XCTAssertThrowsError(try GeoGridBuilder.build(centre: centre, latitudeSpan: 1,
                                                       longitudeSpan: 1, elevations: [], weather: []))
    }

    func testServiceModelsDecodeDocumentedShapes() throws {
        let elevation = try JSONDecoder().decode(ElevationResponse.self, from: Data(#"{"elevation":[38.0]}"#.utf8))
        let weather = try JSONDecoder().decode([WeatherResponse].self, from: Data(#"[{"current":{"temperature_2m":2.1,"precipitation":0.4,"snowfall":0.2,"wind_speed_10m":12.0,"wind_gusts_10m":22.0,"cloud_cover":80,"weather_code":71}}]"#.utf8))
        XCTAssertEqual(elevation.elevation, [38])
        XCTAssertEqual(weather[0].current.precipitation, 0.4)
        XCTAssertEqual(weather[0].current.weather_code, 71)
    }

    func testTerrainMetricsRespondToAHighCentrePoint() throws {
        let centre = GeoPoint(latitude: 51, longitude: -115)
        let current = WeatherResponse.Current(time: nil, interval: nil, temperature_2m: 5,
                                              precipitation: 0, snowfall: nil,
                                              wind_speed_10m: 5, wind_gusts_10m: nil,
                                              cloud_cover: nil, weather_code: nil)
        let weather = Array(repeating: WeatherResponse(current: current), count: 9)
        var elevations = Array(repeating: 1_000.0, count: 9)
        elevations[4] = 2_000
        let grid = try GeoGridBuilder.build(centre: centre, latitudeSpan: 0.03,
                                             longitudeSpan: 0.03,
                                             elevations: elevations, weather: weather)
        XCTAssertEqual(grid.samples[4].reliefMetres, 1_000)
        XCTAssertGreaterThan(grid.samples[4].slopeMetresPerKilometre, 120)
        XCTAssertEqual(HapticClipLibrary.terrainKind(for: grid.samples[4]), .cliff)
    }

    func testWeatherFieldsCanBeMissing() throws {
        let response = try JSONDecoder().decode(WeatherResponse.self,
            from: Data(#"{"current":{"temperature_2m":5,"precipitation":0,"wind_speed_10m":8}}"#.utf8))
        XCTAssertNil(response.current.weather_code)
        XCTAssertNil(response.current.snowfall)
    }
}
