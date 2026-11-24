# Haptic Terrain Atlas

A small macOS map that pairs terrain and current weather with continuous, audio-derived Force Touch trackpad textures. It is a separate project from Juicy Haptic UI.

## Run

1. Install Xcode 27 and XcodeGen.
2. Run `xcodegen generate` in this folder.
3. Open `HapticTerrainAtlas.xcodeproj` and run the `HapticTerrainAtlas` scheme.
4. Move the map to a place of interest. Select **Load this view**.
5. Turn on **Trackpad haptics**. Move across the map or select a marker.
6. Open **Texture gallery** to try each texture, including rare weather.

The app opens near Banff. It loads nine points for each view. Select **Terrain**, **Weather**, or **Both**. The sidebar shows the nearest sample and its cue. **Load this view** fetches fresh data for the current map area. The app keeps the last grid visible if a later request fails.

## Feedback catalogue

The atlas selects one texture from the current map layer. In **Both** mode, active weather takes priority. Clear and cloudy conditions leave room for the terrain texture.

| Terrain rule | Texture | Feel |
| --- | --- | --- |
| Gentle sampled terrain | Lowland | Rounded, low resonance |
| Grid gradient at least 35 m/km | Incline | Two rising voices |
| High ground above nearby samples | Ridge | Rough, narrow crest |
| Grid gradient at least 120 m/km | Cliff | Sharp edge and falling thud |
| At least 140 m below nearby samples | Basin | Deep, hollow resonance |

| Weather rule | Texture | Feel |
| --- | --- | --- |
| Clear sky | Clear sky | Open harmonics |
| Cloud cover at least 70% | Cloud cover | Muted, low blanket |
| Fog code | Fog | Diffuse, slow pulses |
| Drizzle code or trace precipitation | Drizzle | Sparse, fine drops |
| Rain code or precipitation at least 0.3 mm | Rain | Steady drops |
| Heavy rain code or precipitation at least 2 mm | Downpour | Dense splatter and broad wash |
| Snow code or snowfall at least 0.1 cm | Snow | Fine, dry grains |
| Wind at least 25 km/h | Wind | Smooth sweep |
| Gust at least 45 km/h and 15 km/h above wind | Gusts | Irregular surges |
| Thunderstorm code | Thunder | Crack and rolling rumble |
| Temperature at most −8 °C | Frost | Brittle, icy ticks |
| Temperature at least 30 °C | Heat | Wavering shimmer |

The app generates a 16 kHz audio sketch for each texture. It analyses every 10 ms of audio and sends two frequency peaks to the motor, between 100 and 4,000 Hz. It chooses one of three variants when each texture starts. Precipitation, wind, temperature, and sampled terrain gradient adjust the force within each cue. Gallery previews play for about 1.2–1.5 seconds. Feedback continues while you move across the loaded map. It stops when you leave the map, turn it off, change focus, or pause for six seconds. The strength slider starts at 0.42 and has a hard limit of 0.55 on the motor's 0–1 level scale.

The expressive mode loads Apple's private `MultitouchSupport` framework only after you enable haptics. If the framework or Force Touch motor is unavailable, the app uses a standard macOS haptic tap. Private framework calls can change after a macOS update. The generated audio is an input to frequency analysis. The app does not send PCM audio to the speakers.

## Data and credit

Elevation comes from the Copernicus DEM GLO-90 through the [Open-Meteo Elevation API](https://open-meteo.com/en/docs/elevation-api). Current weather comes from the [Open-Meteo Forecast API](https://open-meteo.com/en/docs). Weather values are model estimates for nearby grid points. They are not on-site measurements. Open-Meteo may return a nearby model coordinate for each request.

The atlas samples a 3 × 3 grid. Its **grid gradient** and **local relief** compare those nine points. They are broad terrain hints, not a trail-grade measurement. The gallery previews every texture without claiming that it is occurring on the map.

The private motor bridge follows the technique in [nospeaker](https://github.com/os6/nospeaker) by Cody Collier. Its MIT licence is included in [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt).

## Verify

Run:

```sh
xcodebuild -project HapticTerrainAtlas.xcodeproj -scheme HapticTerrainAtlas \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

The tests check grid shape, response decoding, terrain and weather rules, distinct frequency signatures, texture frames, and strength limits. Live API calls and physical trackpad feel require a network connection and a Force Touch trackpad.
