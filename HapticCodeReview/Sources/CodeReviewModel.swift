import AppKit
import SwiftUI

@MainActor
final class CodeReviewModel: ObservableObject {
    @Published private(set) var code = SampleCode.text
    @Published private(set) var documentTitle = "ReadingCache.swift · sample"
    @Published private(set) var activeAnnotation: CodeAnnotation?
    @Published private(set) var outputStatus = "Off"
    @Published private(set) var fileStatus = "Sample file · edit freely or open a UTF-8 code file"
    @Published var strength = 0.40
    @Published var hapticsEnabled = false {
        didSet {
            if hapticsEnabled { output.enable(); startPlayback() }
            else { stopPlayback(); output.disable() }
            outputStatus = output.status
        }
    }

    private var notes = SampleCode.notes
    private var index = CodeAnnotationIndex(text: SampleCode.text, notes: SampleCode.notes)
    private let output = CodeTrackpadOutput()
    private var playbackTask: Task<Void, Never>?
    private var activityAt = 0.0
    private var generation = 0
    private var appActive = true

    var annotationCount: Int { index.annotations.count }

    func updateCode(_ newCode: String) {
        guard newCode != code else { return }
        code = newCode
        index = CodeAnnotationIndex(text: newCode, notes: notes)
        activeAnnotation = nil
        stopPlayback()
        fileStatus = "Unsaved edits · export a copy to keep them"
    }

    func hover(characterIndex: Int?) {
        let found = characterIndex.flatMap { index.annotation(at: $0) }
        if found != activeAnnotation {
            activeAnnotation = found
            activityAt = ProcessInfo.processInfo.systemUptime
            stopPlayback()
            startPlayback()
        } else if found != nil {
            activityAt = ProcessInfo.processInfo.systemUptime
            if playbackTask == nil { startPlayback() }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a UTF-8 source file. A matching .haptics.json file adds agent notes."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.loadFile(url) }
        }
    }

    func saveCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = documentTitle.replacingOccurrences(of: " · sample", with: "")
        panel.message = "Save the edited code and a matching agent note file."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.writeCopy(to: url) }
        }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if !active {
            activeAnnotation = nil
            stopPlayback()
        }
    }

    func stopOutput() {
        stopPlayback()
        output.disable()
    }

    func loadFile(_ url: URL) {
        do {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= 1_000_000 else {
                fileStatus = "File is over the 1 MB demo limit"
                return
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let sidecar = url.appendingPathExtension("haptics.json")
            let newNotes: [AgentNote]
            if FileManager.default.fileExists(atPath: sidecar.path) {
                let data = try Data(contentsOf: sidecar)
                newNotes = try JSONDecoder().decode(AgentNoteFile.self, from: data).notes
            } else { newNotes = [] }
            notes = newNotes
            code = text
            documentTitle = url.lastPathComponent
            index = CodeAnnotationIndex(text: text, notes: notes)
            activeAnnotation = nil
            stopPlayback()
            fileStatus = "\(annotationCount) cues · hover or scroll through the code"
        } catch {
            fileStatus = "Could not open the code or its note file: \(error.localizedDescription)"
        }
    }

    func writeCopy(to url: URL) {
        do {
            try code.write(to: url, atomically: true, encoding: .utf8)
            let sidecar = url.appendingPathExtension("haptics.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(AgentNoteFile(notes: notes)).write(to: sidecar, options: .atomic)
            documentTitle = url.lastPathComponent
            fileStatus = "Saved a copy with \(annotationCount) cues"
        } catch {
            fileStatus = "Could not save the copy: \(error.localizedDescription)"
        }
    }

    private func startPlayback() {
        guard hapticsEnabled, appActive, let activeAnnotation else { return }
        let token = generation
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var next = clock.now
            let start = ProcessInfo.processInfo.systemUptime
            var lastTap = -1.0
            while !Task.isCancelled, generation == token, self.activeAnnotation == activeAnnotation {
                let now = ProcessInfo.processInfo.systemUptime
                if now - activityAt > 1.5 { break }
                let elapsed = now - start
                if let frame = CodeHapticPattern.frame(kind: activeAnnotation.kind,
                                                       seconds: elapsed, strength: strength) {
                    let interval = activeAnnotation.kind == .risk ? 0.20 : 0.42
                    let fallbackTap = elapsed - lastTap > interval && frame.level > strength * 0.30
                    if fallbackTap { lastTap = elapsed }
                    output.play(frame, fallbackTap: fallbackTap)
                }
                next = next.advanced(by: .milliseconds(12))
                if clock.now > next.advanced(by: .milliseconds(30)) { next = clock.now }
                try? await clock.sleep(until: next)
            }
            if generation == token { playbackTask = nil }
        }
    }

    private func stopPlayback() {
        generation += 1
        playbackTask?.cancel()
        playbackTask = nil
    }
}
