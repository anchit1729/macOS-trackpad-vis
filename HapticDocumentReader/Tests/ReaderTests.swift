import XCTest
@testable import HapticDocumentReader

final class ReaderTests: XCTestCase {
    func testHiddenCuesMatchUniqueDocumentPhrases() {
        let document = ReaderDocument.example
        XCTAssertEqual(document.cues.count, Connotation.allCases.count)
        XCTAssertEqual(Set(document.cues.map(\.kind)).count, Connotation.allCases.count)
        let source = document.text as NSString
        for cue in document.cues {
            XCTAssertNotEqual(cue.range.location, NSNotFound)
            XCTAssertEqual(source.substring(with: cue.range), cue.phrase)
            XCTAssertEqual(document.cue(at: cue.range.location)?.kind, cue.kind)
        }
        XCTAssertNil(document.cue(at: 0))
    }

    func testPatternsStayWithinMotorCapAndDiffer() {
        let frames = Connotation.allCases.compactMap {
            ConnotationPattern.frame(for: $0, seconds: 0.2, strength: 0.5)
        }
        XCTAssertEqual(frames.count, Connotation.allCases.count)
        XCTAssertTrue(frames.allSatisfy { frame in
            (0...0.5).contains(frame.level) &&
            frame.tones.allSatisfy { (120...1_600).contains($0.hertz) } &&
            abs(frame.tones.reduce(0) { $0 + $1.weight } - 1) < 0.0001
        })
        XCTAssertEqual(Set(frames).count, frames.count)
        XCTAssertNil(ConnotationPattern.frame(for: .calm, seconds: .nan, strength: 0.5))
    }

    func testUrgencyHasTwoShortPulses() {
        let first = ConnotationPattern.frame(for: .urgency, seconds: 0.04, strength: 0.5)!
        let gap = ConnotationPattern.frame(for: .urgency, seconds: 0.13, strength: 0.5)!
        let second = ConnotationPattern.frame(for: .urgency, seconds: 0.22, strength: 0.5)!
        XCTAssertGreaterThan(first.level, gap.level * 5)
        XCTAssertEqual(first.level, second.level)
    }
}
