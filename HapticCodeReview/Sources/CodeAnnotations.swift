import Foundation

enum CodeNoteKind: String, Codable, CaseIterable, Sendable {
    case risk
    case suggestion
    case question
    case testGap
    case todo

    var title: String {
        switch self {
        case .risk: "Risk"
        case .suggestion: "Suggestion"
        case .question: "Question"
        case .testGap: "Test gap"
        case .todo: "To do"
        }
    }
}

struct AgentNote: Codable, Equatable, Sendable {
    let anchor: String
    let kind: CodeNoteKind
    let message: String
}

struct AgentNoteFile: Codable, Sendable {
    let notes: [AgentNote]
}

struct CodeAnnotation: Equatable, Sendable {
    let line: Int
    let range: NSRange
    let kind: CodeNoteKind
    let message: String
}

struct CodeAnnotationIndex: Sendable {
    let annotations: [CodeAnnotation]
    private let lineStarts: [Int]
    private let byLine: [Int: CodeAnnotation]

    init(text: String, notes: [AgentNote]) {
        let source = text as NSString
        var starts = [0]
        for index in 0..<source.length where source.character(at: index) == 10 {
            starts.append(index + 1)
        }
        lineStarts = starts
        var found: [CodeAnnotation] = []
        for note in notes where !note.anchor.isEmpty {
            let match = source.range(of: note.anchor)
            guard match.location != NSNotFound else { continue }
            let line = Self.line(for: match.location, starts: starts)
            let lineRange = source.lineRange(for: match)
            found.append(.init(line: line, range: lineRange,
                               kind: note.kind, message: note.message))
        }
        for lineNumber in starts.indices {
            let start = starts[lineNumber]
            let end = lineNumber + 1 < starts.count ? starts[lineNumber + 1] : source.length
            let range = NSRange(location: start, length: end - start)
            let lineText = source.substring(with: range)
            if lineText.contains("FIXME") || lineText.contains("try!") {
                if !found.contains(where: { $0.line == lineNumber + 1 && $0.kind == .risk }) {
                    found.append(.init(line: lineNumber + 1, range: range, kind: .risk,
                                       message: "Review this risky operation."))
                }
            } else if lineText.contains("TODO") {
                if !found.contains(where: { $0.line == lineNumber + 1 && $0.kind == .todo }) {
                    found.append(.init(line: lineNumber + 1, range: range, kind: .todo,
                                       message: "This task is still open."))
                }
            }
        }
        annotations = found.sorted { $0.line < $1.line }
        byLine = Dictionary(annotations.map { ($0.line, $0) },
                            uniquingKeysWith: { first, _ in first })
    }

    func line(at characterIndex: Int) -> Int {
        Self.line(for: characterIndex, starts: lineStarts)
    }

    func annotation(at characterIndex: Int) -> CodeAnnotation? {
        byLine[line(at: characterIndex)]
    }

    private static func line(for index: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= index { low = middle + 1 }
            else { high = middle }
        }
        return max(1, low)
    }
}

enum SampleCode {
    static let text = """
    import Foundation

    struct ReadingCache {
        let source: URL

        func load() -> [String] {
            let data = try! Data(contentsOf: source)
            let lines = String(decoding: data, as: UTF8.self)
                .split(separator: "\\n")
                .map(String.init)
            return lines
        }

        func firstMatch(in lines: [String], query: String) -> String? {
            return lines.first { $0.contains(query) }
        }

        // TODO: Add a test for an empty file.
    }
    """

    static let notes: [AgentNote] = [
        .init(anchor: "try! Data(contentsOf: source)", kind: .risk,
              message: "Agent review: a missing file will crash this path. Return an error instead."),
        .init(anchor: "String(decoding: data, as: UTF8.self)", kind: .question,
              message: "Agent question: should malformed UTF-8 be rejected or replaced?"),
        .init(anchor: "return lines\n", kind: .suggestion,
              message: "Agent suggestion: trim blank lines before returning the result."),
        .init(anchor: "func firstMatch", kind: .testGap,
              message: "Agent review: add tests for a missing query and repeated matches."),
        .init(anchor: "// TODO: Add a test", kind: .todo,
              message: "Open task: cover an empty input file.")
    ]
}

struct CodeTone: Equatable, Sendable {
    let hertz: Double
    let weight: Double
}

struct CodeFrame: Equatable, Sendable {
    let level: Double
    let tones: [CodeTone]
}

enum CodeHapticPattern {
    static func frame(kind: CodeNoteKind, seconds: Double, strength: Double) -> CodeFrame? {
        guard seconds.isFinite, strength.isFinite else { return nil }
        let time = max(0, seconds)
        let cap = min(0.50, max(0, strength))
        guard cap > 0 else { return nil }
        let level: Double
        let tones: [CodeTone]
        switch kind {
        case .risk:
            let phase = time.truncatingRemainder(dividingBy: 0.65)
            level = phase < 0.08 || (phase > 0.16 && phase < 0.24) ||
                (phase > 0.32 && phase < 0.40) ? 0.88 : 0.08
            tones = [.init(hertz: 180, weight: 0.52), .init(hertz: 980, weight: 0.48)]
        case .suggestion:
            let phase = time.truncatingRemainder(dividingBy: 0.76) / 0.76
            level = 0.18 + 0.55 * sin(.pi * phase)
            tones = [.init(hertz: 290 + 350 * phase, weight: 0.70),
                     .init(hertz: 1_080, weight: 0.30)]
        case .question:
            level = 0.24 + 0.25 * abs(sin(2 * .pi * time * 2.1))
            tones = [.init(hertz: 260 + 120 * sin(2 * .pi * time * 1.4), weight: 0.62),
                     .init(hertz: 720, weight: 0.38)]
        case .testGap:
            let phase = time.truncatingRemainder(dividingBy: 0.42)
            level = phase < 0.075 ? 0.63 : 0.08
            tones = [.init(hertz: 210, weight: 0.78), .init(hertz: 580, weight: 0.22)]
        case .todo:
            let phase = time.truncatingRemainder(dividingBy: 0.90)
            level = phase < 0.12 ? 0.46 : 0.07
            tones = [.init(hertz: 345, weight: 0.64), .init(hertz: 760, weight: 0.36)]
        }
        return .init(level: cap * level, tones: tones)
    }
}
