import SwiftUI
import AppKit

/// The writing surface. AppKit rather than SwiftUI's TextEditor because this is
/// the whole app — it needs a real caret colour, real insets, real paragraph
/// spacing, Writing Tools, and typewriter scrolling, none of which SwiftUI gives up.
struct Editor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    /// Set for a rich-text note; the styling the file itself carries.
    let rich: NSAttributedString?
    let format: NoteFormat
    let fontSize: Double
    let fontFamily: String
    let hideMarks: Bool
    let palette: Palette
    let typewriter: Bool
    let selection: PendingSelection?
    let onChange: (String, NSAttributedString?) -> Void

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
        storage.delegate = textView
        textView.isEditable = true
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
        textView.format = format
        textView.isRichText = format == .richText

        let loadingNote = context.coordinator.loadedNoteID != noteID
        if loadingNote {
            context.coordinator.loadedNoteID = noteID
            // `applyStyle` below restyles the whole note once; the storage
            // delegate must not do it a second time on the way in.
            textView.loading = true
            if let rich, format == .richText {
                textView.textStorage?.setAttributedString(rich)
            } else {
                textView.string = text
            }
            textView.loading = false
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

        // SwiftUI re-runs this on every keystroke, and re-styling the document is
        // far too expensive to repeat when none of its inputs moved.
        let style = StyleInputs(fontSize: fontSize, fontFamily: fontFamily, hideMarks: hideMarks, palette: palette, format: format)
        if loadingNote || context.coordinator.style != style {
            context.coordinator.style = style
            textView.hideMarks = hideMarks
            textView.applyStyle(fontSize: fontSize, fontFamily: fontFamily, palette: palette)
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

    /// Everything `applyStyle` reads. Unchanged inputs mean nothing to redo.
    struct StyleInputs: Equatable {
        let fontSize: Double
        let fontFamily: String
        let hideMarks: Bool
        let palette: Palette
        let format: NoteFormat
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Editor
        var loadedNoteID: UUID?
        var appliedSelection: UUID?
        var style: StyleInputs?

        init(_ parent: Editor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlainTextView else { return }
            parent.onChange(textView.string, textView.richSnapshot())
            if textView.typewriter { textView.centerCaret() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? PlainTextView else { return }
            textView.caretMoved()
            if textView.typewriter { textView.centerCaret() }
        }
    }
}

/// NSTextView with the app's paper baked in: plain text only, a placeholder, and
/// an optional typewriter scroll that keeps the caret on the same line of glass.
final class PlainTextView: NSTextView, NSTextStorageDelegate {
    var placeholder = "Start writing…"
    var placeholderColor: NSColor = .secondaryLabelColor
    var typewriter = false
    var format: NoteFormat = .markdown
    /// Markdown syntax is hidden except on the line the caret is on.
    var hideMarks = false
    /// Set while a note is being swapped in, so the per-edit restyle stays out
    /// of the way of the full one that follows.
    var loading = false
    private var baseFont = NSFont.systemFont(ofSize: 14)
    private var ink = NSColor.textColor
    /// The paragraph whose marks are currently shown, so moving the caret only
    /// has to repaint the line it left and the line it landed on.
    private var revealed = NSRange(location: 0, length: 0)

    /// The paragraph range the caret sits in — what the styler is told to reveal.
    private var caretParagraph: NSRange {
        guard hideMarks, format == .markdown else { return NSRange(location: NSNotFound, length: 0) }
        return (string as NSString).paragraphRange(for: selectedRange())
    }

    private var revealArgument: NSRange? {
        let range = caretParagraph
        return range.location == NSNotFound ? nil : range
    }

    static func font(family: String, size: Double) -> NSFont {
        guard !family.isEmpty, let font = NSFont(name: family, size: size) else {
            return NSFont.systemFont(ofSize: size)
        }
        return font
    }

    func applyStyle(fontSize: Double, fontFamily: String, palette: Palette) {
        let font = PlainTextView.font(family: fontFamily, size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        // The caret is AppKit's own, and it is exactly as tall as the line
        // fragment — so line spacing is added below the line rather than by
        // inflating the fragment the caret is measured against.
        paragraph.lineSpacing = fontSize * 0.35
        paragraph.paragraphSpacing = fontSize * 0.75

        self.baseFont = font
        self.ink = palette.nsInk
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
        guard let storage = textStorage, storage.length > 0 else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        if format == .richText {
            // A rich note's bold and italics are its own; only the things the
            // whole app controls — size, colour, spacing — are re-applied.
            storage.enumerateAttribute(.font, in: all) { value, range, _ in
                let existing = (value as? NSFont) ?? font
                let resized = NSFont(descriptor: existing.fontDescriptor, size: fontSize) ?? font
                storage.addAttribute(.font, value: resized, range: range)
            }
            storage.addAttribute(.foregroundColor, value: palette.nsInk, range: all)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: all)
        } else {
            storage.setAttributes([
                .font: font,
                .foregroundColor: palette.nsInk,
                .paragraphStyle: paragraph
            ], range: all)
        }
        storage.endEditing()
        if format == .markdown { restyleIfMarkdown() }
    }

    /// Repaint the whole note. Used when the font size or theme changes; ordinary
    /// typing goes through the far cheaper per-line path below.
    func restyleIfMarkdown() {
        guard format == .markdown, let storage = textStorage else { return }
        revealed = caretParagraph
        storage.beginEditing()
        MarkdownStyler.style(storage, baseFont: baseFont, ink: ink, hideMarks: hideMarks, reveal: revealArgument)
        storage.endEditing()
    }

    /// Repaint the line the caret left and the one it arrived on, so marks fold
    /// away behind it and unfold ahead of it.
    func caretMoved() {
        guard hideMarks, format == .markdown, let storage = textStorage, storage.length > 0 else { return }
        let now = caretParagraph
        guard now != revealed else { return }
        let before = revealed
        revealed = now
        storage.beginEditing()
        for range in [before, now] where range.location != NSNotFound && range.length > 0 {
            MarkdownStyler.style(storage, baseFont: baseFont, ink: ink, hideMarks: hideMarks, reveal: now, in: range)
        }
        storage.endEditing()
    }

    /// The text storage reports exactly what changed, so only the lines that were
    /// touched are re-read — typing in a long note costs the same as typing in a
    /// short one.
    func textStorage(
        _ storage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard format == .markdown, !loading, editedMask.contains(.editedCharacters) else { return }
        let lines = (storage.string as NSString).paragraphRange(for: editedRange)
        // The selection has not caught up with the edit yet; the edited line is
        // where the caret is about to be, so it is the line to reveal.
        let reveal = hideMarks ? lines : nil
        revealed = reveal ?? NSRange(location: NSNotFound, length: 0)
        MarkdownStyler.style(storage, baseFont: baseFont, ink: ink, hideMarks: hideMarks, reveal: reveal, in: lines)
    }

    /// The styled text to save, for a rich note only.
    func richSnapshot() -> NSAttributedString? {
        guard format == .richText, let storage = textStorage else { return nil }
        return NSAttributedString(attributedString: storage)
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

    // MARK: Formatting

    /// Reached from the Format menu, so the shortcuts are discoverable and route
    /// through the responder chain like every other command on the Mac. In a
    /// markdown note these write the marks; in a rich note they set the styling.
    /// Either way, running one again undoes it.
    ///
    /// The names are prefixed because `underline(_:)` is already NSTextView's.
    @objc func silicaToggleBold(_ sender: Any?) {
        format == .richText ? toggleTrait(.boldFontMask) : wrapSelection(in: "**")
    }

    @objc func silicaToggleItalic(_ sender: Any?) {
        format == .richText ? toggleTrait(.italicFontMask) : wrapSelection(in: "*")
    }

    /// Markdown has no underline of its own; the HTML tag is what every markdown
    /// renderer understands.
    @objc func silicaToggleUnderline(_ sender: Any?) {
        format == .richText ? toggleLine(.underlineStyle) : wrapSelection(in: "<u>", closing: "</u>")
    }

    @objc func silicaToggleStrikethrough(_ sender: Any?) {
        format == .richText ? toggleLine(.strikethroughStyle) : wrapSelection(in: "~~")
    }

    // MARK: Rich text

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let range = selectedRange()
        let current = (typingAttributes[.font] as? NSFont) ?? baseFont
        let reference = (range.length > 0
            ? textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            : current) ?? current
        let isOn = manager.traits(of: reference).contains(trait)

        applyToSelection(range) { storage in
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? self.baseFont
                let updated = isOn
                    ? manager.convert(font, toNotHaveTrait: trait)
                    : manager.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: updated, range: subrange)
            }
        } typing: { attributes in
            attributes[.font] = isOn
                ? manager.convert(current, toNotHaveTrait: trait)
                : manager.convert(current, toHaveTrait: trait)
        }
    }

    private func toggleLine(_ attribute: NSAttributedString.Key) {
        let range = selectedRange()
        let existing = range.length > 0
            ? textStorage?.attribute(attribute, at: range.location, effectiveRange: nil)
            : typingAttributes[attribute]
        let isOn = (existing as? Int ?? 0) != 0

        applyToSelection(range) { storage in
            if isOn {
                storage.removeAttribute(attribute, range: range)
            } else {
                storage.addAttribute(attribute, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        } typing: { attributes in
            if isOn { attributes.removeValue(forKey: attribute) }
            else { attributes[attribute] = NSUnderlineStyle.single.rawValue }
        }
    }

    /// With a selection the styling lands on it; with none it arms what you type
    /// next, the way every other Mac editor behaves.
    private func applyToSelection(
        _ range: NSRange,
        storage apply: (NSTextStorage) -> Void,
        typing arm: (inout [NSAttributedString.Key: Any]) -> Void
    ) {
        var attributes = typingAttributes
        arm(&attributes)
        typingAttributes = attributes

        guard range.length > 0, let storage = textStorage else { return }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        apply(storage)
        storage.endEditing()
        didChangeText()
    }

    // MARK: Markdown

    private func wrapSelection(in opening: String, closing: String? = nil) {
        let close = closing ?? opening
        let text = string as NSString
        let range = selectedRange()
        let openLength = (opening as NSString).length
        let closeLength = (close as NSString).length

        // Marks inside the selection — take them off.
        if range.length >= openLength + closeLength {
            let selected = text.substring(with: range)
            if selected.hasPrefix(opening) && selected.hasSuffix(close) {
                let inner = (selected as NSString).substring(
                    with: NSRange(location: openLength, length: (selected as NSString).length - openLength - closeLength)
                )
                replaceCharacters(
                    in: range,
                    with: inner,
                    selecting: NSRange(location: range.location, length: (inner as NSString).length)
                )
                return
            }
        }

        // Marks hugging the selection — take those off too, so double-tapping the
        // shortcut undoes itself whether or not the marks got selected.
        let before = NSRange(location: range.location - openLength, length: openLength)
        let after = NSRange(location: NSMaxRange(range), length: closeLength)
        if before.location >= 0, NSMaxRange(after) <= text.length,
           text.substring(with: before) == opening, text.substring(with: after) == close {
            let outer = NSRange(location: before.location, length: openLength + range.length + closeLength)
            replaceCharacters(
                in: outer,
                with: text.substring(with: range),
                selecting: NSRange(location: before.location, length: range.length)
            )
            return
        }

        // Otherwise wrap. With nothing selected the caret lands between the marks,
        // ready to type into them.
        replaceCharacters(
            in: range,
            with: opening + text.substring(with: range) + close,
            selecting: NSRange(location: range.location + openLength, length: range.length)
        )
    }

    private func replaceCharacters(in range: NSRange, with replacement: String, selecting: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selecting)
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
