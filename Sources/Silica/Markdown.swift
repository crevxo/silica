import AppKit

/// How a note stores its formatting. It is a property of the file, not of the
/// app: a `.md` note is markdown wherever you open it, a `.rtf` note carries its
/// styling with it. Nothing converts behind your back.
enum NoteFormat: String, Codable, CaseIterable, Identifiable {
    case markdown, richText

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown: "Markdown"
        case .richText: "Rich text"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .richText: "rtf"
        }
    }

    static func of(_ url: URL) -> NoteFormat {
        url.pathExtension.lowercased() == "rtf" ? .richText : .markdown
    }
}

/// Draws markdown as what it means while leaving it as what it is. The asterisks
/// stay in the file, but on screen they are hidden everywhere except the line the
/// caret is on, where they show dimmed so they can still be edited.
enum MarkdownStyler {
    /// Past this the whole-document restyle on every keystroke stops being free.
    private static let sizeLimit = 200_000

    private struct Rule {
        let regex: NSRegularExpression
        /// Applied to the text between the marks.
        let style: (NSMutableAttributedString, NSRange, NSFont) -> Void
        /// The syntax this match owns, as sub-ranges of the match. Only marks a
        /// rule actually paired are ever hidden; a stray `*` or a bullet stays.
        let marks: (NSTextCheckingResult) -> [NSRange]
    }

    private static func edges(_ opening: Int, _ closing: Int) -> (NSTextCheckingResult) -> [NSRange] {
        { match in
            let r = match.range
            return [
                NSRange(location: r.location, length: opening),
                NSRange(location: NSMaxRange(r) - closing, length: closing)
            ]
        }
    }

    private static func regex(_ pattern: String, multiline: Bool = false) -> NSRegularExpression {
        // Every pattern here is a literal written below; a bad one is a bug, not
        // a runtime condition.
        try! NSRegularExpression(pattern: pattern, options: multiline ? [.anchorsMatchLines] : [])
    }

    private static let manager = NSFontManager.shared
    private static var traitCache: [String: NSFont] = [:]

    /// `convert(_:toHaveTrait:)` walks the font table every time it is asked; the
    /// same few answers recur thousands of times while typing.
    private static func withTrait(_ font: NSFont, _ trait: NSFontTraitMask) -> NSFont {
        let key = "\(font.fontName)|\(font.pointSize)|\(trait.rawValue)"
        if let cached = traitCache[key] { return cached }
        let converted = manager.convert(font, toHaveTrait: trait)
        traitCache[key] = converted
        return converted
    }

    private static func inner(of range: NSRange, opening: Int, closing: Int) -> NSRange {
        NSRange(location: range.location + opening, length: max(0, range.length - opening - closing))
    }

    private static func addTrait(_ trait: NSFontTraitMask, _ storage: NSMutableAttributedString, _ range: NSRange, _ base: NSFont) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? base
            storage.addAttribute(.font, value: withTrait(font, trait), range: subrange)
        }
    }

    private static let rules: [Rule] = [
        // Headings: the whole line, hashes included, grows and goes bold.
        Rule(regex: regex("^(#{1,6}[ \\t]+)(\\S.*)$", multiline: true), style: { storage, range, base in
            let level = min(3, max(1, storage.attributedSubstring(from: range).string.prefix { $0 == "#" }.count))
            let scale = [1.55, 1.32, 1.15][level - 1]
            let sized = NSFont(descriptor: base.fontDescriptor, size: base.pointSize * scale) ?? base
            let font = withTrait(sized, .boldFontMask)
            storage.addAttribute(.font, value: font, range: range)
        }, marks: { [$0.range(at: 1)] }),
        Rule(regex: regex("\\*\\*(?:(?!\\*\\*).)+\\*\\*"), style: { storage, range, base in
            addTrait(.boldFontMask, storage, range, base)
        }, marks: edges(2, 2)),
        Rule(regex: regex("(?<![\\*\\w])\\*(?!\\*)[^\\*\\n]+(?<!\\*)\\*(?!\\*)"), style: { storage, range, base in
            addTrait(.italicFontMask, storage, range, base)
        }, marks: edges(1, 1)),
        // The line goes through the words, not through the marks that ask for it.
        Rule(regex: regex("~~(?:(?!~~).)+~~"), style: { storage, range, _ in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner(of: range, opening: 2, closing: 2))
        }, marks: edges(2, 2)),
        Rule(regex: regex("<u>(?:(?!</u>).)+</u>"), style: { storage, range, _ in
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: inner(of: range, opening: 3, closing: 4))
        }, marks: edges(3, 4)),
        Rule(regex: regex("`[^`\\n]+`"), style: { storage, range, base in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.94, weight: .regular), range: range)
        }, marks: edges(1, 1))
    ]

    /// The marks themselves — everything that is syntax rather than writing.
    private static let markPattern = regex(
        [
            "^#{1,6}[ \\t]+",         // heading hashes and the gap after them
            "\\*\\*",                 // bold
            "(?<![\\*\\w])\\*(?!\\*)|(?<!\\*)\\*(?![\\*\\w])", // italic
            "~~",                     // strikethrough
            "</?u>",                  // underline
            "`"                       // code
        ].joined(separator: "|"),
        multiline: true
    )

    /// Restyles `range`, which the caller widens to whole lines. Every pattern
    /// here lives inside one line, so a line is all that ever needs re-reading —
    /// typing in a long note does not re-scan the note.
    /// Fonts this small are the closest TextKit gets to a hidden character: the
    /// mark keeps its place in the string but takes up no visible room.
    private static let hiddenFont = NSFont.systemFont(ofSize: 0.1)

    /// `reveal` is the paragraph range the caret is in; marks there are dimmed
    /// rather than hidden. Pass nil to hide none (`hideMarks` false) or all.
    static func style(
        _ storage: NSTextStorage,
        baseFont: NSFont,
        ink: NSColor,
        hideMarks: Bool = false,
        reveal: NSRange? = nil,
        in range: NSRange? = nil
    ) {
        let document = NSRange(location: 0, length: storage.length)
        guard document.length > 0, document.length < sizeLimit else { return }
        let scope = range.map { NSIntersectionRange($0, document) } ?? document
        guard scope.length > 0 else { return }
        let text = storage.string

        // Start from a clean slate so deleting a mark takes its styling with it.
        storage.removeAttribute(.strikethroughStyle, range: scope)
        storage.removeAttribute(.underlineStyle, range: scope)
        storage.addAttribute(.font, value: baseFont, range: scope)
        storage.addAttribute(.foregroundColor, value: ink, range: scope)

        var owned: [NSRange] = []
        for rule in rules {
            for match in rule.regex.matches(in: text, range: scope) {
                rule.style(storage as NSMutableAttributedString, match.range, baseFont)
                owned.append(contentsOf: rule.marks(match))
            }
        }

        // Dim the syntax last, so it fades no matter which rule claimed the span.
        let dimmed = ink.withAlphaComponent(0.28)
        for match in markPattern.matches(in: text, range: scope) {
            storage.addAttribute(.foregroundColor, value: dimmed, range: match.range)
        }

        // Then fold away the marks a rule paired, except on the caret's line. An
        // unpaired mark (a bullet, `2 * 3`, a lone backtick) is writing, not
        // syntax, and stays put.
        guard hideMarks else { return }
        for mark in owned where mark.length > 0 {
            let onCaretLine = reveal.map { NSIntersectionRange($0, mark).length > 0 || NSLocationInRange(mark.location, $0) } ?? false
            if !onCaretLine {
                storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: mark)
            }
        }
    }
}
