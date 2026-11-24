# Haptic Compass Hunt

Find a hidden point in a macOS window by following trackpad cues.

## Run

1. Install Xcode and XcodeGen.
2. Run `xcodegen generate` in this folder.
3. Open `HapticCompassHunt.xcodeproj` and run the app.
4. Move the pointer through the dark field. Follow both direction accents.
5. Press Command-N to place a new hidden point.

Command-line check:

```sh
xcodegen generate
xcodebuild -project HapticCompassHunt.xcodeproj -scheme HapticCompassHunt \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## Feel the search

A continuous low texture grows stronger and higher as you near the point. A high accent marks right or up. A low accent marks left or down. The horizontal accent comes first. The vertical accent follows. Each accent grows with the remaining distance on its axis. The cycle speeds up near the point. A fine high layer adds detail nearby. Finding the point plays a three-step rising chord.

The app makes 12 ms frames with three frequency layers. The strength control has a 0.50 motor cap. The target stays hidden until the pointer enters its small capture area. Cues stop when you leave the field, switch apps, or turn them off.

The expressive mode uses Apple's private `MultitouchSupport` interface. It follows the MIT-licensed [nospeaker example](https://github.com/os6/nospeaker); see [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt). If the motor interface is unavailable, standard macOS taps encode direction by count. Private calls can change with macOS updates. The app does not change the system trackpad settings.
