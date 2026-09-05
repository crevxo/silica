import SwiftUI
import AppKit

/// The writing surface. AppKit rather than SwiftUI's TextEditor because this is
/// the whole app — it needs a real caret colour, real insets, real paragraph
/// spacing, Writing Tools, and typewriter scrolling, none of which SwiftUI gives up.
struct Editor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let fontSize: Double
    let palette: Palette
    let typewriter: Bool
    let selection: PendingSelection?
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)

        let textView = PlainTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize.zero
        // Matches the mock's 18px top / 22px side padding.
        textView.textContainerInset = NSSize(width: 17, height: 18)
        textView.drawsBackground = true

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? PlainTextView else { return }
        context.coordinator.parent = self
        textView.applyStyle(fontSize: fontSize, palette: palette)

        if context.coordinator.loadedNoteID != noteID {
            context.coordinator.loadedNoteID = noteID
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
            scroll.contentView.scroll(to: .zero)
        } else if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, text.utf16.count),
                length: 0
            ))
        }

        // A search result hands over a range once; the token stops it being
        // re-applied on every later redraw.
        if let selection, selection.noteID == noteID, context.coordinator.appliedSelection != selection.token {
            context.coordinator.appliedSelection = selection.token
            let textLength = textView.string.utf16.count
            let location = min(selection.location, textLength)
            let clamped = NSRange(
                location: location,
                length: min(selection.length, textLength - location)
            )
            textView.setSelectedRange(clamped)
            textView.scrollRangeToVisible(clamped)
            textView.showFindIndicator(for: clamped)
            textView.window?.makeFirstResponder(textView)
        }

        textView.placeholderColor = palette.nsInkSoft
        textView.typewriter = typewriter
        scroll.drawsBackground = true
        scroll.backgroundColor = palette.nsBackground
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Editor
        var loadedNoteID: UUID?
        var appliedSelection: UUID?

        init(_ parent: Editor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlainTextView else { return }
            parent.onChange(textView.string)
            if textView.typewriter { textView.centerCaret() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? PlainTextView, textView.typewriter else { return }
            textView.centerCaret()
        }
    }
}

/// NSTextView with the app's paper baked in: plain text only, a placeholder, and
/// an optional typewriter scroll that keeps the caret on the same line of glass.
final class PlainTextView: NSTextView {
    var placeholder = "Start writing…"
    var placeholderColor: NSColor = .secondaryLabelColor
    var typewriter = false

    func applyStyle(fontSize: Double, palette: Palette) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        // The caret is AppKit's own, and it is exactly as tall as the line
        // fragment — so line spacing is added below the line rather than by
        // inflating the fragment the caret is measured against.
        paragraph.lineSpacing = fontSize * 0.35
        paragraph.paragraphSpacing = fontSize * 0.75

        self.font = font
        self.defaultParagraphStyle = paragraph
        self.textColor = palette.nsInk
        self.backgroundColor = palette.nsBackground
        self.insertionPointColor = caretBlue
        self.typingAttributes = [
            .font: font,
            .foregroundColor: palette.nsInk,
            .paragraphStyle: paragraph
        ]

        // Re-style text that is already on screen (font size change, theme switch).
        if let storage = textStorage, storage.length > 0 {
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: font,
                .foregroundColor: palette.nsInk,
                .paragraphStyle: paragraph
            ], range: all)
            storage.endEditing()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let box = NSRect(
            x: textContainerInset.width + padding,
            y: textContainerInset.height,
            width: max(0, bounds.width - textContainerInset.width * 2 - padding * 2),
            height: font.ascender - font.descender + font.leading + 8
        )
        // Same paragraph style as real text, so the placeholder sits on the line
        // the first typed character will land on.
        (placeholder as NSString).draw(
            in: box,
            withAttributes: [
                .font: font,
                .foregroundColor: placeholderColor,
                .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default
            ]
        )
    }

    /// Scroll so the caret sits at the vertical middle of the visible area.
    func centerCaret() {
        guard let layoutManager, let container = textContainer, let scroll = enclosingScrollView else { return }
        let range = layoutManager.glyphRange(forCharacterRange: selectedRange(), actualCharacterRange: nil)
        let caret = layoutManager.boundingRect(forGlyphRange: range, in: container)
        let visible = scroll.contentView.bounds.height
        let target = caret.midY + textContainerInset.height - visible / 2
        let maxY = max(0, frame.height - visible)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(target, 0), maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Escape leaves focus mode, so there is always a way out without the menu bar.
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .silicaEscape, object: nil)
    }
}

extension Notification.Name {
    static let silicaEscape = Notification.Name("SilicaEscape")
}
