# macOS Trackpad Visualizations

Seven standalone Swift apps explore visual data through a Force Touch trackpad.

For personal website updates, see the [portfolio website brief](PORTFOLIO_WEBSITE_BRIEF.md).
For agent integration, see the [tactile review queue concept](AGENT_HAPTIC_SIDE_CHANNEL.md).

| Example | What you see | What you feel |
| --- | --- | --- |
| [Haptic Terrain Atlas](HapticTerrainAtlas/README.md) | A terrain and weather map | Continuous, audio-derived terrain and weather textures |
| [Haptic Fluid Lab](HapticFluidLab/README.md) | A 2D + 3D PIC–FLIP fluid simulation | Local motion or pressure, with layered flow and crest cues |
| [Haptic Compass Hunt](HapticCompassHunt/README.md) | A hidden-point search field | Continuous proximity, plus horizontal and vertical direction accents |
| [Vibes on Demand](VibesOnDemandMac/README.md) | A scatterplot with time series details | Trace shape, peaks, and slope changes on press or scrub |
| [Haptic Document Reader](HapticDocumentReader/README.md) | A plain text document with hidden semantic ranges | Distinct patterns for calm, curiosity, uncertainty, urgency, loss, and hope |
| [Haptic Beat Lab](HapticBeatLab/README.md) | A timed circle selection game | Guidance for direction and distance, or rhythm and hit accents |
| [Haptic Code Review](HapticCodeReview/README.md) | An editable code file with agent notes | Line cues for risks, suggestions, questions, test gaps, and tasks |

## Build

Use macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Each folder is an independent app.

```sh
cd HapticCompassHunt
xcodegen generate
open HapticCompassHunt.xcodeproj
```

Replace `HapticCompassHunt` with another example name. Each app has its own build and test steps.

## Trackpad support

The expressive textures use a private macOS `MultitouchSupport` interface. The apps use standard AppKit taps when the motor interface is unavailable. Private calls can change after a macOS update. The apps do not change system trackpad settings. The terrain app synthesizes audio samples to choose motor frequencies; it does not play these samples through speakers.

Each app includes the MIT licence for the [nospeaker](https://github.com/os6/nospeaker) technique used by its motor bridge.
