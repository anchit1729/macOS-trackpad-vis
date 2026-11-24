import Foundation

enum Connotation: String, CaseIterable, Sendable {
    case calm = "Calm"
    case curiosity = "Curiosity"
    case uncertainty = "Uncertainty"
    case urgency = "Urgency"
    case loss = "Loss"
    case hope = "Hope"
}

struct HiddenCue: Equatable, Sendable {
    let phrase: String
    let kind: Connotation
    let range: NSRange
}

struct ReaderDocument: Sendable {
    let title: String
    let subtitle: String
    let text: String
    let cues: [HiddenCue]

    func cue(at characterIndex: Int) -> HiddenCue? {
        cues.first { NSLocationInRange(characterIndex, $0.range) }
    }

    static let example: ReaderDocument = {
        let paragraphs = [
            "At dawn, the lake lay still beneath a pale sky. The water touched the reeds so gently that their reflections held together. From the path, the whole shore seemed to breathe at one slow pace.",
            "Mara followed the familiar route to the old footbridge. A narrow band of ripples crossed the lake against the wind. She stopped to watch it, then checked the empty shore for a boat.",
            "By midday, the water had reached the first stone step. No one could tell whether the level would keep rising. The marks on the wall gave a clear record of yesterday, but little guidance for the next hour.",
            "Mara took a notebook from her bag and wrote down the time. She measured the water again after ten minutes. The second mark stood higher. The warning siren sounded before the lower path flooded, and people moved towards the ridge.",
            "The rain eased in the evening. The old footbridge was gone by morning. Its timber had carried neighbours across the inlet for years; now the two banks faced each other over open water.",
            "A small light appeared in the far window. Someone had reached the other side and was signalling back. Mara answered with her torch. Soon, more lights joined the exchange, one after another.",
            "The path would need repair. For now, the lake settled, the ridge stayed dry, and the lights gave everyone a way to count who had arrived. Mara closed the notebook and watched the first clear patch of sky."
        ]
        let text = paragraphs.joined(separator: "\n\n")
        let markers: [(String, Connotation)] = [
            ("the whole shore seemed to breathe at one slow pace", .calm),
            ("A narrow band of ripples crossed the lake against the wind", .curiosity),
            ("No one could tell whether the level would keep rising", .uncertainty),
            ("The warning siren sounded before the lower path flooded", .urgency),
            ("The old footbridge was gone by morning", .loss),
            ("Soon, more lights joined the exchange, one after another", .hope)
        ]
        let source = text as NSString
        let cues = markers.map { phrase, kind in
            HiddenCue(phrase: phrase, kind: kind, range: source.range(of: phrase))
        }
        return ReaderDocument(title: "Signals by the Water", subtitle: "A short story for haptic reading",
                              text: text, cues: cues)
    }()
}

struct ReaderTone: Hashable, Sendable {
    let hertz: Double
    let weight: Double
}

struct ReaderHapticFrame: Hashable, Sendable {
    let level: Double
    let tones: [ReaderTone]
}

enum ConnotationPattern {
    static func frame(for kind: Connotation, seconds: Double, strength: Double) -> ReaderHapticFrame? {
        guard seconds.isFinite, strength.isFinite else { return nil }
        let time = max(0, seconds)
        let cap = min(0.5, max(0, strength))
        guard cap > 0 else { return nil }
        let wave: Double
        let tones: [ReaderTone]
        switch kind {
        case .calm:
            wave = 0.30 + 0.18 * (1 + sin(2 * .pi * time / 1.35)) / 2
            tones = [.init(hertz: 165, weight: 0.75), .init(hertz: 430, weight: 0.25)]
        case .curiosity:
            let phase = time.truncatingRemainder(dividingBy: 0.72) / 0.72
            wave = 0.25 + 0.38 * sin(.pi * phase)
            tones = [.init(hertz: 230 + 380 * phase, weight: 0.70),
                     .init(hertz: 1_080 + 300 * phase, weight: 0.30)]
        case .uncertainty:
            wave = 0.26 + 0.20 * abs(sin(2 * .pi * time * 2.3))
            tones = [.init(hertz: 205 + 60 * sin(2 * .pi * time * 1.7), weight: 0.65),
                     .init(hertz: 690, weight: 0.35)]
        case .urgency:
            let phase = time.truncatingRemainder(dividingBy: 0.58)
            wave = phase < 0.09 || (phase > 0.18 && phase < 0.27) ? 0.95 : 0.08
            tones = [.init(hertz: 370, weight: 0.35), .init(hertz: 980, weight: 0.45),
                     .init(hertz: 1_510, weight: 0.20)]
        case .loss:
            let phase = time.truncatingRemainder(dividingBy: 1.15)
            wave = 0.17 + 0.54 * exp(-4.2 * phase)
            tones = [.init(hertz: 145, weight: 0.82), .init(hertz: 320, weight: 0.18)]
        case .hope:
            let phase = time.truncatingRemainder(dividingBy: 0.92) / 0.92
            wave = 0.25 + 0.42 * phase
            tones = [.init(hertz: 260 + 300 * phase, weight: 0.62),
                     .init(hertz: 760 + 350 * phase, weight: 0.38)]
        }
        return .init(level: min(cap, cap * wave), tones: tones)
    }
}
