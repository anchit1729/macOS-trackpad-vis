import XCTest
@testable import HapticCodeReview

final class CodeReviewTests: XCTestCase {
    func testSampleNotesAnchorToLines() {
        let index = CodeAnnotationIndex(text: SampleCode.text, notes: SampleCode.notes)
        XCTAssertEqual(index.annotations.count, 5)
        XCTAssertEqual(Set(index.annotations.map(\.kind)).count, 5)
        let source = SampleCode.text as NSString
        for note in SampleCode.notes {
            let location = source.range(of: note.anchor).location
            XCTAssertNotEqual(location, NSNotFound)
            XCTAssertEqual(index.annotation(at: location)?.kind, note.kind)
        }
    }

    func testNotesMoveWithEditedTextAndAutomaticMarkers() {
        let changed = "// new line\n" + SampleCode.text
        let index = CodeAnnotationIndex(text: changed, notes: SampleCode.notes)
        let source = changed as NSString
        let location = source.range(of: "try! Data(contentsOf: source)").location
        XCTAssertEqual(index.annotation(at: location)?.line, 8)
        let automatic = CodeAnnotationIndex(text: "// FIXME: review\n// TODO: test", notes: [])
        XCTAssertEqual(automatic.annotations.map(\.kind), [.risk, .todo])
    }

    func testCuePatternsAreDistinctAndCapped() {
        let frames = CodeNoteKind.allCases.compactMap {
            CodeHapticPattern.frame(kind: $0, seconds: 0.03, strength: 0.5)
        }
        XCTAssertEqual(frames.count, CodeNoteKind.allCases.count)
        XCTAssertTrue(frames.allSatisfy { $0.level <= 0.5 && $0.level >= 0 })
        XCTAssertEqual(Set(frames.map { $0.tones[0].hertz }).count, frames.count)
        XCTAssertNil(CodeHapticPattern.frame(kind: .risk, seconds: .nan, strength: 0.5))
    }

    func testSidecarLoadsAndExportsWithCode() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Example.swift")
        try SampleCode.text.write(to: source, atomically: true, encoding: .utf8)
        let notes = AgentNoteFile(notes: SampleCode.notes)
        try JSONEncoder().encode(notes).write(to: source.appendingPathExtension("haptics.json"))
        let copy = folder.appendingPathComponent("Copy.swift")
        await MainActor.run {
            let model = CodeReviewModel()
            model.loadFile(source)
            XCTAssertEqual(model.annotationCount, 5)
            let index = (model.code as NSString).range(of: "try! Data").location
            model.hover(characterIndex: index)
            XCTAssertEqual(model.activeAnnotation?.kind, .risk)
            model.updateCode("// added\n" + model.code)
            model.writeCopy(to: copy)
            XCTAssertEqual(model.documentTitle, "Copy.swift")
        }
        let saved = try String(contentsOf: copy, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("// added\n"))
        let exported = try JSONDecoder().decode(AgentNoteFile.self,
            from: Data(contentsOf: copy.appendingPathExtension("haptics.json")))
        XCTAssertEqual(exported.notes, SampleCode.notes)
    }
}
