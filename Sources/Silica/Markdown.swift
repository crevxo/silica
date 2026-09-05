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
/// stay in the file — and stay on screen, dimmed — but the text between them is
/// bold, italic, struck through or underlined as you type.
enum MarkdownStyler {
    /// Past this the whole-document restyle on every keystroke stops being free.
    private static let sizeLimit = 200_000

    private struct Rule {
        let regex: NSRegularExpression
        /// Applied to the text between the marks.
        let style: (NSMutableAttributedString, NSRange, NSFont) -> Void
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
        Rule(regex: regex("^(#{1,6})[ \\t]+(.+)$", multiline: true)) { storage, range, base in
            let level = min(3, max(1, storage.attributedSubstring(from: range).string.prefix { $0 == "#" }.count))
            let scale = [1.55, 1.32, 1.15][level - 1]
            let font = withTrait(NSFont.systemFont(ofSize: base.pointSize * scale), .boldFontMask)
            storage.addAttribute(.font, value: font, range: range)
        },
        Rule(regex: regex("\\*\\*(?:(?!\\*\\*).)+\\*\\*")) { storage, range, base in
            addTrait(.boldFontMask, storage, range, base)
        },
        Rule(regex: regex("(?<![\\*\\w])\\*(?!\\*)[^\\*\\n]+(?<!\\*)\\*(?!\\*)")) { storage, range, base in
            addTrait(.italicFontMask, storage, range, base)
        },
        // The line goes through the words, not through the marks that ask for it.
        Rule(regex: regex("~~(?:(?!~~).)+~~")) { storage, range, _ in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner(of: range, opening: 2, closing: 2))
        },
        Rule(regex: regex("<u>(?:(?!</u>).)+</u>")) { storage, range, _ in
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: inner(of: range, opening: 3, closing: 4))
        },
        Rule(regex: regex("`[^`\\n]+`")) { storage, range, base in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.94, weight: .regular), range: range)
        }
    ]

    /// The marks themselves — everything that is syntax rather than writing.
    private static let markPattern = regex(
        [
            "^#{1,6}(?=[ \\t])",     // heading hashes
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
    static func style(_ storage: NSTextStorage, baseFont: NSFont, ink: NSColor, in range: NSRange? = nil) {
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

        for rule in rules {
            for match in rule.regex.matches(in: text, range: scope) {
                rule.style(storage as NSMutableAttributedString, match.range, baseFont)
            }
        }

        // Dim the syntax last, so it fades no matter which rule claimed the span.
        let dimmed = ink.withAlphaComponent(0.28)
        for match in markPattern.matches(in: text, range: scope) {
            storage.addAttribute(.foregroundColor, value: dimmed, range: match.range)
        }
    }
}
