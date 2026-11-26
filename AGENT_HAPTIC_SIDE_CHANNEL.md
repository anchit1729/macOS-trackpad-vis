# Concept: a tactile review queue for coding agents

Use the trackpad as a quiet second channel between a coding agent and its human partner. The agent sends a short cue when its state changes. The user then moves through the code to locate anchored notes. The note text stays available on screen.

## Example exchange

1. An agent runs tests and finds a failure in a changed function.
2. The harness sends one rough, low cue for **needs review**.
3. The user moves through the file. A three-pulse cue marks the relevant line.
4. The editor shows the agent's exact note when the user reaches that line.
5. The user acknowledges the note. The harness receives that acknowledgement and continues its workflow.

This keeps agent progress perceptible while the user reads another part of the screen. It also gives a location to inspect before the user reads a long log.

## Proposed event contract

The harness sends a small, structured event to a local process. The event carries a category and an optional code anchor.

```json
{
  "id": "review-42",
  "kind": "risk",
  "file": "Sources/Parser.swift",
  "anchor": "try! decode(input)",
  "summary": "This path can crash on malformed input.",
  "requiresAcknowledgement": true
}
```

Use five categories first: **working**, **question**, **risk**, **tests passed**, and **ready for review**. Give each category one recognisable pattern. Increase strength only for a direct request for attention. Keep routine progress silent or very brief.

## Interaction rules

- Play a global cue once when the event state changes.
- Play a local cue only while the pointer explores the event's code line.
- Show the full message in the editor. The vibration carries category and urgency only.
- Let the user mute the channel, set strength, and acknowledge a note.
- Limit repeated cues and expire stale events.
- Keep a visible event log so a missed vibration does not hide information.

## Build path from this repository

The [Haptic Code Review](HapticCodeReview/README.md) example already reads agent notes from a `.haptics.json` sidecar file. That is the first static form of this contract. A next version can watch the sidecar for changes, then add a local Unix socket for live events and acknowledgements. The current example does not stream live agent state or send acknowledgements.
