import Foundation

struct ReadingCache {
    let source: URL

    func load() -> [String] {
        let data = try! Data(contentsOf: source)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
        return lines
    }

    func firstMatch(in lines: [String], query: String) -> String? {
        return lines.first { $0.contains(query) }
    }

    // TODO: Add a test for an empty file.
}
