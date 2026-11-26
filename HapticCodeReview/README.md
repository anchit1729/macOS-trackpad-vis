# Haptic Code Review

A small macOS code editor that gives agent notes and code markers distinct trackpad textures. Move down the code, use the caret, or scroll beneath the pointer. The note text appears in a panel after you reach its line.

## Use

1. Open the app to inspect the built-in Swift sample.
2. Turn on trackpad haptics and adjust strength.
3. Move through the file. Edit the sample or open another UTF-8 code file.
4. Select **Export copy** to save the edited code and its agent note file.

The editor colours Swift keywords, strings, and comments. Haptic notes attach to logical lines. They move when their anchor text moves in an edited file. A missing anchor leaves its note inactive. The app also detects `TODO`, `FIXME`, and `try!` markers in any opened file. Those markers are simple text checks, not compiler findings.

## Agent note file

Place a JSON file beside a code file. Append `.haptics.json` to the full file name. For `Example.swift`, use `Example.swift.haptics.json`.

```json
{
  "notes": [
    {
      "anchor": "try! Data(contentsOf: source)",
      "kind": "risk",
      "message": "A missing file can crash this path. Return an error instead."
    }
  ]
}
```

The supported kinds are `risk`, `suggestion`, `question`, `testGap`, and `todo`. The app matches the first exact occurrence of each anchor. Use a unique anchor. Open [Example.swift](Examples/Example.swift) to try its matching [note file](Examples/Example.swift.haptics.json).

## Haptic mapping

| Kind | Feel |
| --- | --- |
| Risk | Three rough pulses |
| Suggestion | Rising sweep |
| Question | Wavering tone |
| Test gap | Hollow regular ticks |
| To do | Soft slow tick |

Cues stop when the pointer leaves an annotated line, the app loses focus, or movement stops for 1.5 seconds. The motor level is capped at 50%. The expressive mode uses the private macOS `MultitouchSupport` interface. Standard AppKit taps provide a fallback. The interface can change after a macOS update. See [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt).

## Build and test

Use macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd HapticCodeReview
xcodegen generate
xcodebuild -project HapticCodeReview.xcodeproj -scheme HapticCodeReview -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
open HapticCodeReview.xcodeproj
```

The app reads files up to 1 MB. The tests check note anchoring after edits, automatic markers, and distinct, capped patterns. Trackpad feel needs a hardware check.

The [tactile review queue concept](../AGENT_HAPTIC_SIDE_CHANNEL.md) extends the sidecar format towards live agent communication.
