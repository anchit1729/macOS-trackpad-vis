# Portfolio website brief: macOS trackpad visualisations

Use this file to add the trackpad projects to Anchit's personal website. Inspect the website before editing it. Follow its current layout, type, colours, and navigation.

## Goal and order

Show a clear link between interaction design and implementation. Use two full project pages and one optional feature.

1. Feature **Haptic Fluid Lab** first for general software, graphics, and simulation internships.
2. Feature **Vibes on Demand** second for general applications. Put it first for HCI and interaction design roles.
3. Add **Haptic Terrain Atlas** as a third feature when the role values maps, data visualisation, or creative technology.
4. Put **Haptic Document Reader** and **Haptic Compass Hunt** in a compact experiments section.

Do not make five equal cards in the main portfolio grid. The first two projects carry the strongest case studies.

Suggested section intro:

> I explore ways to make data feel as well as look different. These Swift prototypes pair visual interfaces with trackpad cues for motion, shape, place, and meaning.

## Source links

| Project | Repository folder | Project guide |
| --- | --- | --- |
| Haptic Fluid Lab | https://github.com/anchit1729/macOS-trackpad-vis/tree/main/HapticFluidLab | https://github.com/anchit1729/macOS-trackpad-vis/blob/main/HapticFluidLab/README.md |
| Vibes on Demand | https://github.com/anchit1729/macOS-trackpad-vis/tree/main/VibesOnDemandMac | https://github.com/anchit1729/macOS-trackpad-vis/blob/main/VibesOnDemandMac/README.md |
| Haptic Terrain Atlas | https://github.com/anchit1729/macOS-trackpad-vis/tree/main/HapticTerrainAtlas | https://github.com/anchit1729/macOS-trackpad-vis/blob/main/HapticTerrainAtlas/README.md |
| Haptic Document Reader | https://github.com/anchit1729/macOS-trackpad-vis/tree/main/HapticDocumentReader | https://github.com/anchit1729/macOS-trackpad-vis/blob/main/HapticDocumentReader/README.md |
| Haptic Compass Hunt | https://github.com/anchit1729/macOS-trackpad-vis/tree/main/HapticCompassHunt | https://github.com/anchit1729/macOS-trackpad-vis/blob/main/HapticCompassHunt/README.md |

Use the guides for technical facts. Use the source code when a guide leaves a detail unclear.

## Featured card copy

### Haptic Fluid Lab

**One line:** Feel fluid motion and pressure through a macOS trackpad.

**Card copy:** A real-time 2D and 3D PIC–FLIP fluid study. I mapped local motion and pressure to layered trackpad cues, then tuned the solver and rendering for interactive use.

**Tags:** Swift · Simulation · 3D graphics · Haptics

**Show:** A short clip that switches between 2D and 3D, stirs the water, and changes the feel mode. Include the frame rate display if it is stable.

### Vibes on Demand

**One line:** Explore the shape of a time series by touching its point.

**Card copy:** A macOS details on demand prototype for scatterplots. Press a point to reveal its line chart and feel its values. Pin the chart to scrub through the trace.

**Tags:** Swift · Data visualisation · HCI · Haptics

**Show:** A clip of a point press, the visible line chart, its moving playhead, and a scrub. Keep the sample data label visible.

### Haptic Terrain Atlas

**One line:** Feel terrain and weather while exploring a map.

**Card copy:** A macOS atlas that maps elevation and current weather to distinct trackpad textures. It builds short audio sketches and uses their frequency content to drive the motor.

**Tags:** Swift · Maps · Weather data · Haptics

**Show:** A clip with the map, a weather change, and the texture gallery. State that weather values are model estimates.

## Experiments copy

- **Haptic Document Reader:** A plain text story with hidden phrase cues for calm, curiosity, uncertainty, urgency, loss, and hope.
- **Haptic Compass Hunt:** A hidden point game with distance and direction cues that guide a search across the screen.

Link each experiment to its repository folder. A short description is enough unless there is new evaluation evidence.

## Case study structure

Give each featured project a short page or an expanded section. Keep the order below.

1. State the problem and the intended interaction in two or three sentences.
2. Show the app in a short clip or clear images.
3. Explain the haptic mapping with a small diagram or waveform view.
4. Name two important implementation choices and explain why they matter.
5. Report measured results with the machine and method, when available.
6. Link to code and explain the next change you would make.

For Fluid Lab, explain the PIC–FLIP solver, 3D surface mesh, and motion or pressure mapping. The repository reports about 30 fps on the development Mac. Verify that claim before using it as a headline.

For Vibes on Demand, explain press, reveal, pin, and scrub. The macOS app uses synthetic data. Link any separate research paper only after Anchit confirms its public version and his role.

For Terrain Atlas, explain the live data source and the audio to motor mapping. Distinguish map estimates from measurements at a site.

## Media and access

- Capture the current apps. Do not invent screenshots or performance results.
- Show the visual response to an action. A website visitor cannot feel the trackpad through a video.
- Add a short caption that describes the haptic cue in words.
- Provide a still image and useful alt text for every video.
- Keep text and links usable without hover, sound, or a Force Touch trackpad.
- Use the existing website style. Keep motion brief and respect reduced motion settings.
- Link to the relevant GitHub folder from every project card.

## Claims to check before publication

- These apps are research prototypes. They use a private macOS `MultitouchSupport` interface for expressive motor output.
- Standard AppKit taps are the fallback when that interface is unavailable.
- The website must not claim App Store support or universal trackpad support.
- The Vibes on Demand macOS port uses synthetic sample data. Do not present it as a user study result.
- The Document Reader uses authored hidden phrase ranges. Do not claim automatic semantic analysis.
- Claim user study findings, collaborators, and research ownership only from confirmed sources.

## Finish the update

Check the site at desktop and mobile widths. Open each project link. Play each media item. Read the text without media. Confirm that every metric and research claim has a source.
