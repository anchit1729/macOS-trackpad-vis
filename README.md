# macOS Trackpad Visualizations

Three standalone Swift apps explore visual data through a Force Touch trackpad.

| Example | What you see | What you feel |
| --- | --- | --- |
| [Haptic Terrain Atlas](HapticTerrainAtlas/README.md) | A terrain and weather map | Continuous, audio-derived terrain and weather textures |
| [Haptic Fluid Lab](HapticFluidLab/README.md) | A 2D + 3D PIC–FLIP fluid simulation | Local motion or pressure, with layered flow and crest cues |
| [Haptic Compass Hunt](HapticCompassHunt/README.md) | A hidden-point search field | Continuous proximity, plus horizontal and vertical direction accents |

## Build

Use macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Each folder is an independent app.

```sh
cd HapticCompassHunt
xcodegen generate
open HapticCompassHunt.xcodeproj
```

Replace `HapticCompassHunt` with either other example name. Each app has its own build and test steps.

## Trackpad support

The expressive textures use a private macOS `MultitouchSupport` interface. The apps use standard AppKit taps when the motor interface is unavailable. Private calls can change after a macOS update. The apps do not change system trackpad settings. The terrain app synthesizes audio samples to choose motor frequencies; it does not play these samples through speakers.

Each app includes the MIT licence for the [nospeaker](https://github.com/os6/nospeaker) technique used by its motor bridge.
