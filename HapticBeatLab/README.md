# Haptic Beat Lab

An original macOS target selection game with shrinking approach rings. Click a numbered circle when its outer ring reaches the circle border. The [osu! wiki](https://osu.ppy.sh/wiki/en/Gameplay/Hit_object/Approach_circle) describes this timing cue. This example uses no osu! assets, beatmaps, or music.

## Play

1. Run the app and select **Guide** or **Augment**.
2. Turn on trackpad haptics and adjust strength.
3. Press **Start round**. Click each circle as its ring closes.

The round has 16 targets. A hit within 70 ms earns **Perfect**; a hit within 180 ms earns **Good**. The pointer must be within 38 screen points of the circle centre. Missed targets break the combo. The app pauses when it loses focus.

## Haptic modes

- **Guide:** A continuous texture strengthens near the target. Two alternating tones encode left/right and down/up direction. A pulse strengthens as the beat nears.
- **Augment:** The texture ignores pointer position. Bright pulses mark the approach, and distinct impacts mark Perfect, Good, and Miss.

The motor bridge sends 12 ms tone frames through the private macOS `MultitouchSupport` interface. Strength is capped at 50%. Sparse AppKit taps play when the expressive motor is unavailable. See [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt). Physical feel needs a Force Touch trackpad check.

## Build and test

Use macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd HapticBeatLab
xcodegen generate
xcodebuild -project HapticBeatLab.xcodeproj -scheme HapticBeatLab -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
open HapticBeatLab.xcodeproj
```

The tests cover target order, spatial and timing judgement, mode differences, direction tones, and motor limits.
