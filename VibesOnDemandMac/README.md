# Vibes on Demand for macOS

This native Swift app ports the core details on demand interaction to a Force Touch trackpad. A scatterplot holds 36 deterministic, synthetic time series. Press a point to see and feel its trace. A moving playhead shows the part of the trace being played.

## Use

- Press and hold a point to reveal and play its trace. Release to close it.
- Click a point to pin its trace. Move over the chart to scrub its values.
- Click the same point, or click outside the card, to close a pinned trace.
- Turn off **Show line chart** to explore the trace through haptics and the playhead.
- Change strength, trace duration, and smoothing in the side panel.

The app uses a short repeating trace while you hold or pin a point. A scrub starts when you move over a pinned chart. It stops when the pointer rests. The haptic output stops when the app loses focus.

## Haptic mapping

The trace value controls force and a low motor tone. Force rises from 25% to 100% of the selected strength. The selected strength has a 50% motor cap. A middle tone adds body. A high tone marks steep changes and peaks. The app sends 12 ms frames to the trackpad motor. A standard AppKit tap plays at a lower rate when the private motor interface is unavailable.

This bridge uses the private `MultitouchSupport` interface demonstrated by [nospeaker](https://github.com/os6/nospeaker). Apple can change this interface. The app does not change system trackpad settings. See [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt).

## Build and test

Use macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd VibesOnDemandMac
xcodegen generate
xcodebuild -project VibesOnDemandMac.xcodeproj -scheme VibesOnDemandMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
open VibesOnDemandMac.xcodeproj
```

Run the app from Xcode on a Mac with a Force Touch trackpad. Turn on **Trackpad haptics** in the side panel. The current output mode appears below the controls. Feel and strength require a manual hardware check.

## Data and scope

The six included shapes are rising, falling, peak, trough, waves, and plateau. Data stays local. This prototype does not import the original study data or its study server. Replace `TraceLibrary.series` with your own data to connect a new dataset.
