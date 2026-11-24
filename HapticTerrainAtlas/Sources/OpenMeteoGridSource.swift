import Foundation

struct OpenMeteoGridSource {
    var session: URLSession = .shared

    func load(centre: GeoPoint, latitudeSpan: Double, longitudeSpan: Double) async throws -> GeoGrid {
        let points = GeoGrid.points(around: centre, latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan)
        let latitudes = points.map { String($0.latitude) }.joined(separator: ",")
        let longitudes = points.map { String($0.longitude) }.joined(separator: ",")
        var elevationURL = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
        elevationURL.queryItems = [URLQueryItem(name: "latitude", value: latitudes),
                                   URLQueryItem(name: "longitude", value: longitudes)]
        var weatherURL = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        weatherURL.queryItems = [URLQueryItem(name: "latitude", value: latitudes),
                                 URLQueryItem(name: "longitude", value: longitudes),
                                 URLQueryItem(name: "current", value: "temperature_2m,precipitation,snowfall,wind_speed_10m,wind_gusts_10m,cloud_cover,weather_code"),
                                 URLQueryItem(name: "forecast_days", value: "1")]

        async let elevations = get(elevationURL.url!)
        async let weather = get(weatherURL.url!)
        let elevationResponse = try JSONDecoder().decode(ElevationResponse.self, from: await elevations)
        let weatherResponses = try JSONDecoder().decode([WeatherResponse].self, from: await weather)
        return try GeoGridBuilder.build(centre: centre, latitudeSpan: latitudeSpan,
                                        longitudeSpan: longitudeSpan,
                                        elevations: elevationResponse.elevation, weather: weatherResponses)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GeoDataError.invalidResponse
        }
        return data
    }
}
