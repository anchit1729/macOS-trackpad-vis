import AppKit
import SwiftUI

@MainActor
final class CodeTextView: NSTextView {
    var onHover: (Int?) -> Void = { _ in }
    private var tracking: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover(nil)
    }

    func refreshHoverAfterScroll() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        reportHover(at: point)
    }

    private func reportHover(at point: CGPoint) {
        guard visibleRect.contains(point), let layoutManager, let textContainer else {
            onHover(nil)
            return
        }
        let origin = textContainerOrigin
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs else { onHover(nil); return }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                              in: textContainer)
        guard rect.insetBy(dx: -3, dy: -2).contains(local) else { onHover(nil); return }
        onHover(layoutManager.characterIndexForGlyph(at: glyph))
    }
}

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var model: CodeReviewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .init(calibratedRed: 0.055, green: 0.067, blue: 0.095, alpha: 1)
        scroll.contentView.postsBoundsChangedNotifications = true

        let text = CodeTextView(frame: CGRect(x: 0, y: 0, width: 700, height: 1000))
        text.isEditable = true
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 28, height: 28)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.string = model.code
        text.onHover = { model.hover(characterIndex: $0) }
        text.delegate = context.coordinator
        context.coordinator.textView = text
        context.coordinator.applyStyle(to: text)
        scroll.documentView = text
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.viewportChanged(_:)),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let text = view.documentView as? CodeTextView else { return }
        text.onHover = { model.hover(characterIndex: $0) }
        if text.string != model.code {
            text.string = model.code
            context.coordinator.applyStyle(to: text)
            text.scrollToBeginningOfDocument(nil)
        }
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: CodeTextView?
        weak var model: CodeReviewModel?
        private var styling = false

        init(model: CodeReviewModel) { self.model = model }

        @objc func viewportChanged(_ notification: Notification) {
            textView?.refreshHoverAfterScroll()
        }

        func textDidChange(_ notification: Notification) {
            guard !styling, let textView else { return }
            applyStyle(to: textView)
            model?.updateCode(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            model?.hover(characterIndex: textView.selectedRange().location)
        }

        func applyStyle(to text: CodeTextView) {
            guard let storage = text.textStorage else { return }
            styling = true
            defer { styling = false }
            let full = NSRange(location: 0, length: storage.length)
            let selection = text.selectedRange()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.94, alpha: 1),
                .paragraphStyle: paragraph
            ], range: full)
            let source = storage.string
            colour(#"\b(import|struct|func|let|var|return|if|guard|else|try|in)\b"#,
                   in: source, storage: storage,
                   colour: NSColor(calibratedRed: 0.70, green: 0.54, blue: 1, alpha: 1))
            colour(#""(?:\\.|[^"\\])*""#, in: source, storage: storage,
                   colour: NSColor(calibratedRed: 0.55, green: 0.84, blue: 0.74, alpha: 1))
            colour(#"//[^\n]*"#, in: source, storage: storage,
                   colour: NSColor(calibratedRed: 0.56, green: 0.62, blue: 0.70, alpha: 1))
            storage.endEditing()
            text.setSelectedRange(NSRange(location: min(selection.location, storage.length),
                                          length: min(selection.length,
                                                      storage.length - min(selection.location, storage.length))))
        }

        private func colour(_ pattern: String, in source: String,
                            storage: NSTextStorage, colour: NSColor) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            for match in expression.matches(in: source,
                                            range: NSRange(location: 0, length: (source as NSString).length)) {
                storage.addAttribute(.foregroundColor, value: colour, range: match.range)
            }
        }
    }
}
