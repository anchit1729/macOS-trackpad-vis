import AppKit
import SwiftUI

@MainActor
final class ReaderTextView: NSTextView {
    var onHover: (Int?) -> Void = { _ in }
    private var hoverTracking: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        hoverTracking = NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(hoverTracking!)
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
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs else { onHover(nil); return }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                              in: textContainer)
        guard rect.insetBy(dx: -2, dy: -2).contains(containerPoint) else {
            onHover(nil)
            return
        }
        onHover(layoutManager.characterIndexForGlyph(at: glyph))
    }
}

struct ReaderPageView: NSViewRepresentable {
    @ObservedObject var model: ReaderModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true

        let text = ReaderTextView(frame: CGRect(x: 0, y: 0, width: 650, height: 800))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isRichText = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 30, height: 28)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 16
        text.textStorage?.setAttributedString(NSAttributedString(string: model.document.text,
            attributes: [.font: NSFont.systemFont(ofSize: 17),
                         .foregroundColor: NSColor.textColor,
                         .paragraphStyle: paragraph]))
        text.onHover = { model.hover(characterIndex: $0) }
        scroll.documentView = text
        context.coordinator.textView = text
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.viewportChanged(_:)),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        (view.documentView as? ReaderTextView)?.onHover = { model.hover(characterIndex: $0) }
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var textView: ReaderTextView?

        @objc func viewportChanged(_ notification: Notification) {
            textView?.refreshHoverAfterScroll()
        }
    }
}
