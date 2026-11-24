import XCTest
@testable import HapticTerrainAtlas

final class HapticClipTests: XCTestCase {
    private let sample = GeoSample(point: .init(latitude: 51, longitude: -115),
                                   elevationMetres: 2_100, reliefMetres: 150,
                                   slopeMetresPerKilometre: 55, temperatureCelsius: 2,
                                   precipitationMillimetres: 0.5, snowfallCentimetres: 0,
                                   windKilometresPerHour: 30, windGustKilometresPerHour: 38,
                                   cloudCoverPercent: 85, weatherCode: 61)

    func testLayerSelectsMeaningfulCue() {
        XCTAssertEqual(HapticClipLibrary.kind(for: sample, layer: .terrain), .ridge)
        XCTAssertEqual(HapticClipLibrary.kind(for: sample, layer: .weather), .rain)
        XCTAssertEqual(HapticClipLibrary.kind(for: sample, layer: .both), .rain)
    }

    func testEveryTextureIsSeamlessAndBounded() {
        for kind in CueKind.allCases {
            for variation in 0..<3 {
                let clip = HapticClipLibrary.clip(for: kind, variation: variation)
                XCTAssertGreaterThanOrEqual(clip.durationMilliseconds, 400)
                XCTAssertLessThanOrEqual(clip.durationMilliseconds, 1_200)
                XCTAssertFalse(clip.frames.isEmpty)
                for frame in clip.frames {
                    XCTAssertGreaterThanOrEqual(frame.strength, 0.50)
                    XCTAssertLessThanOrEqual(frame.strength, 1)
                    XCTAssertEqual(frame.milliseconds, 10)
                    XCTAssertTrue((1...2).contains(frame.tones.count))
                    XCTAssertTrue(frame.tones.allSatisfy { (100...4_000).contains($0.hertz) })
                    XCTAssertEqual(frame.tones.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.001)
                }
            }
        }
    }

    func testEncoderFindsFrequencyInAudioSamples() {
        let samples = (0..<6_400).map { index in
            Float(sin(2 * Double.pi * 1_200 * Double(index) / 16_000))
        }
        let clip = AudioFrequencyEncoder.encode(PCMTexture(samples: samples), kind: .clear)
        XCTAssertEqual(clip.frames.count, 40)
        XCTAssertTrue(clip.frames.allSatisfy { abs($0.tones[0].hertz - 1_200) <= 50 })
    }

    func testGeneratedRainContainsHighAudioFrequencies() {
        let first = HapticClipLibrary.clip(for: .rain, variation: 0)
        let second = HapticClipLibrary.clip(for: .rain, variation: 1)
        XCTAssertTrue(first.frames.contains { $0.tones.contains { $0.hertz >= 1_000 } })
        XCTAssertNotEqual(first.frames.map(\.tones), second.frames.map(\.tones))
    }

    func testEveryCueHasADistinctFrequencySignature() {
        let signatures = CueKind.allCases.map { kind in
            HapticClipLibrary.clip(for: kind, variation: 0).frames.map {
                "\(Int($0.tones[0].hertz)):\(Int($0.strength * 100))"
            }.joined(separator: ",")
        }
        XCTAssertEqual(Set(signatures).count, CueKind.allCases.count)
    }

    func testWeatherPriorityAndTerrainShape() {
        func sample(code: Int? = 0, precipitation: Double = 0, snow: Double = 0,
                    wind: Double = 0, gust: Double = 0, cloud: Int = 0,
                    temperature: Double = 12, elevation: Double = 500,
                    relief: Double = 0, slope: Double = 0) -> GeoSample {
            GeoSample(point: .init(latitude: 51, longitude: -115), elevationMetres: elevation,
                      reliefMetres: relief, slopeMetresPerKilometre: slope,
                      temperatureCelsius: temperature, precipitationMillimetres: precipitation,
                      snowfallCentimetres: snow, windKilometresPerHour: wind,
                      windGustKilometresPerHour: gust, cloudCoverPercent: cloud,
                      weatherCode: code)
        }
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(code: 95, precipitation: 3)), .thunder)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(code: 65)), .downpour)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(code: 73)), .snow)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(code: 51)), .drizzle)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(code: 45)), .fog)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(wind: 30, gust: 55)), .gust)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(wind: 27)), .wind)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(temperature: -12)), .frost)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(temperature: 34)), .heat)
        XCTAssertEqual(HapticClipLibrary.weatherKind(for: sample(cloud: 85)), .cloudy)
        XCTAssertEqual(HapticClipLibrary.terrainKind(for: sample(slope: 140)), .cliff)
        XCTAssertEqual(HapticClipLibrary.terrainKind(for: sample(relief: -160)), .basin)
        XCTAssertEqual(HapticClipLibrary.terrainKind(for: sample(elevation: 2_000, relief: 120)), .ridge)
        XCTAssertEqual(HapticClipLibrary.terrainKind(for: sample(slope: 50)), .incline)
        XCTAssertEqual(HapticClipLibrary.kind(for: sample(code: 0, slope: 50), layer: .both), .incline)
        let lightRain = sample(code: 61, precipitation: 0.3)
        let heavyRain = sample(code: 61, precipitation: 1.8)
        XCTAssertLessThan(HapticClipLibrary.drive(for: lightRain, kind: .rain),
                          HapticClipLibrary.drive(for: heavyRain, kind: .rain))
        XCTAssertLessThanOrEqual(HapticClipLibrary.drive(for: heavyRain, kind: .rain), 1)
    }

    func testGalleryPreviewHasOneToThreeCycles() {
        XCTAssertEqual(HapticPreviewPlan.cycles(for: 500), 3)
        XCTAssertEqual(HapticPreviewPlan.cycles(for: 700), 2)
        XCTAssertEqual(HapticPreviewPlan.cycles(for: 1_200), 1)
        XCTAssertEqual(HapticPreviewPlan.cycles(for: 0), 0)
    }

    func testIntensityHasAConservativeHardCap() {
        let frame = HapticFrame(milliseconds: 50, strength: 1,
                                tones: [.init(hertz: 180, weight: 1)])
        XCTAssertEqual(HapticIntensity.level(for: frame, intensity: 10), 0.55, accuracy: 0.001)
        XCTAssertEqual(HapticIntensity.level(for: frame, intensity: 0), 0.25, accuracy: 0.001)
        XCTAssertEqual(HapticIntensity.level(for: frame, intensity: HapticIntensity.standard), 0.42, accuracy: 0.001)
    }

    func testTextureStopsAfterSixSecondsWithoutPointerInput() {
        XCTAssertFalse(HapticActivityPolicy.shouldStop(lastInput: 10, now: 15.9))
        XCTAssertTrue(HapticActivityPolicy.shouldStop(lastInput: 10, now: 16))
    }
}
