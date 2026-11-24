# Haptic Document Reader

This macOS app adds hidden haptic cues to a short, original story. The document has no visual highlights. Six phrase ranges carry semantic cues: calm, curiosity, uncertainty, urgency, loss, and hope.

## Use

1. Open the app and turn on **Trackpad haptics**.
2. Move the pointer across the text, or scroll while the pointer rests over it.
3. Feel the cue when the pointer reaches an annotated phrase.
4. Adjust strength if needed.

Each cue plays while you explore its phrase. It stops after 1.6 seconds without pointer or scroll activity. It also stops when you leave the phrase or switch away from the app. The output status appears beside the strength control. The text uses one plain style throughout, so cue locations stay hidden.

## Cue design

| Meaning | Haptic shape |
| --- | --- |
| Calm | Low, slow swell |
| Curiosity | Rising chirp with a light high tone |
| Uncertainty | Uneven, wavering texture |
| Urgency | Two short, bright pulses |
| Loss | Heavy low pulse with a long decay |
| Hope | Steady upward sweep |

The app sends 12 ms tone frames to a Force Touch trackpad through the private `MultitouchSupport` interface. Strength is capped at 50%. If the motor interface is unavailable, the app uses sparse standard AppKit taps. Private calls can change with macOS updates. The app does not alter system trackpad settings. See [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt) for the motor bridge technique.

## Build and test

Use macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd HapticDocumentReader
xcodegen generate
xcodebuild -project HapticDocumentReader.xcodeproj -scheme HapticDocumentReader -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
open HapticDocumentReader.xcodeproj
```

Run the app from Xcode on a Mac with a Force Touch trackpad. A person must check the feel on hardware.

## Add a document

Replace `ReaderDocument.example` with text and its hidden phrase markers. Each marker stores a phrase, a connotation, and a UTF-16 range in the document. Keep those ranges out of text styling. Add a pattern case to `ConnotationPattern.frame` when you add a new connotation.
