import AppKit

// Stand-ins for the two app types Editor.swift refers to but that live in files
// pulling in Sparkle / SwiftUI views.
struct PendingSelection: Equatable {
    let token = UUID()
    let noteID: UUID
    let location: Int
    let length: Int
}

var failures = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: @autoclosure () -> String = "") {
    if condition() {
        print("  ok   \(name)")
    } else {
        failures += 1
        let d = detail()
        print("  FAIL \(name)\(d.isEmpty ? "" : " — \(d)")")
    }
}

func makeView(_ format: NoteFormat, _ text: String) -> PlainTextView {
    let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    let layout = NSLayoutManager()
    layout.addTextContainer(container)
    let storage = NSTextStorage()
    storage.addLayoutManager(layout)
    let view = PlainTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
    storage.delegate = view
    view.format = format
    view.isRichText = format == .richText
    view.allowsUndo = true
    view.string = text
    view.applyStyle(fontSize: 14, fontFamily: "", palette: Palette.light)
    return view
}

/// Invoke the command the way the Format menu does: by selector, down the
/// responder chain. `key` is the shortcut it is bound to, so the test reads the
/// way the menu does.
func press(_ view: PlainTextView, _ key: String, shift: Bool = false) {
    let selector: Selector
    switch (key, shift) {
    case ("b", false): selector = #selector(PlainTextView.silicaToggleBold(_:))
    case ("i", false): selector = #selector(PlainTextView.silicaToggleItalic(_:))
    case ("u", false): selector = #selector(PlainTextView.silicaToggleUnderline(_:))
    case ("x", true): selector = #selector(PlainTextView.silicaToggleStrikethrough(_:))
    default: fatalError("no command bound to that shortcut")
    }
    guard view.responds(to: selector) else { fatalError("the editor does not answer \(selector)") }
    view.perform(selector, with: nil)
}

func trait(_ view: PlainTextView, _ location: Int, _ mask: NSFontTraitMask) -> Bool {
    guard let font = view.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont else { return false }
    return NSFontManager.shared.traits(of: font).contains(mask)
}

func attr(_ view: PlainTextView, _ key: NSAttributedString.Key, _ location: Int) -> Any? {
    view.textStorage?.attribute(key, at: location, effectiveRange: nil)
}

_ = NSApplication.shared

print("\nMarkdown notes — shortcuts write the marks")
for (name, key, shift, opening, closing) in [
    ("bold", "b", false, "**", "**"),
    ("italic", "i", false, "*", "*"),
    ("underline", "u", false, "<u>", "</u>"),
    ("strikethrough", "x", true, "~~", "~~")
] as [(String, String, Bool, String, String)] {
    let view = makeView(.markdown, "make me loud")
    view.setSelectedRange(NSRange(location: 5, length: 2))   // "me"
    press(view, key, shift: shift)
    check("\(name) wraps the selection", view.string == "make \(opening)me\(closing) loud", view.string)
    check("\(name) keeps the words selected",
          (view.string as NSString).substring(with: view.selectedRange()) == "me",
          (view.string as NSString).substring(with: view.selectedRange()))
    press(view, key, shift: shift)
    check("\(name) pressed again takes it back off", view.string == "make me loud", view.string)
}

do {
    let view = makeView(.markdown, "")
    press(view, "b")
    check("bold with nothing selected leaves the marks", view.string == "****", view.string)
    check("...and parks the caret between them", view.selectedRange().location == 2, "\(view.selectedRange())")
    view.insertText("typed", replacementRange: view.selectedRange())
    check("...ready to type into", view.string == "**typed**", view.string)
}

do {
    let view = makeView(.markdown, "**already bold**")
    view.setSelectedRange(NSRange(location: 2, length: 12))  // inside the marks
    press(view, "b")
    check("bold un-bolds when only the words are selected", view.string == "already bold", view.string)
}

print("\nMarkdown notes — what you see")
do {
    let view = makeView(.markdown, "plain **loud** and *lean* and ~~gone~~ and <u>under</u>")
    let s = view.string as NSString
    check("bold renders bold", trait(view, s.range(of: "loud").location, .boldFontMask))
    check("italic renders italic", trait(view, s.range(of: "lean").location, .italicFontMask))
    check("plain text stays plain", !trait(view, 0, .boldFontMask) && !trait(view, 0, .italicFontMask))
    check("strikethrough strikes the word",
          (attr(view, .strikethroughStyle, s.range(of: "gone").location) as? Int ?? 0) != 0)
    check("...but not the marks it is written with",
          (attr(view, .strikethroughStyle, s.range(of: "~~").location) as? Int ?? 0) == 0)
    check("underline underlines the word",
          (attr(view, .underlineStyle, s.range(of: "under").location) as? Int ?? 0) != 0)
    let markColor = attr(view, .foregroundColor, s.range(of: "**").location) as? NSColor
    let wordColor = attr(view, .foregroundColor, 0) as? NSColor
    check("the marks themselves are dimmed",
          (markColor?.alphaComponent ?? 1) < (wordColor?.alphaComponent ?? 1))
}

do {
    let view = makeView(.markdown, "# Title\nbody")
    let body = (view.string as NSString).range(of: "body").location
    let titleFont = attr(view, .font, 2) as? NSFont
    let bodyFont = attr(view, .font, body) as? NSFont
    check("a heading is bigger than the body", (titleFont?.pointSize ?? 0) > (bodyFont?.pointSize ?? 99))
    check("a heading is bold", trait(view, 2, .boldFontMask))
    view.setSelectedRange(NSRange(location: 0, length: 1))
    view.insertText("", replacementRange: NSRange(location: 0, length: 2))
    view.restyleIfMarkdown()
    check("deleting the hash takes the heading styling with it",
          ((attr(view, .font, 0) as? NSFont)?.pointSize ?? 0) == (bodyFont?.pointSize ?? 0))
}

print("\nMarkdown notes — restyling as you type")
do {
    // The expensive path is re-reading the whole note on every keystroke, so the
    // editor only re-reads the lines that changed. These check it still keeps up.
    let view = makeView(.markdown, "one\ntwo\nthree")
    view.setSelectedRange(NSRange(location: 7, length: 0))     // end of "two"
    view.insertText(" **loud**", replacementRange: view.selectedRange())
    let s = view.string as NSString
    check("typing markdown styles it without a full restyle",
          trait(view, s.range(of: "loud").location, .boldFontMask))
    check("...and leaves the other lines alone", !trait(view, 0, .boldFontMask))

    view.setSelectedRange(s.range(of: "**"))
    view.insertText("", replacementRange: s.range(of: "**"))
    check("deleting a mark takes its styling off the line",
          !trait(view, (view.string as NSString).range(of: "loud").location, .boldFontMask),
          view.string)

    let pasted = makeView(.markdown, "")
    pasted.insertText("**a**\n*b*\n~~c~~", replacementRange: NSRange(location: 0, length: 0))
    let p = pasted.string as NSString
    check("pasting several lines at once styles all of them",
          trait(pasted, p.range(of: "a").location, .boldFontMask)
          && trait(pasted, p.range(of: "b").location, .italicFontMask)
          && (attr(pasted, .strikethroughStyle, p.range(of: "c").location) as? Int ?? 0) != 0)
}

print("\nRich text notes — shortcuts set the styling, not marks")
do {
    let view = makeView(.richText, "make me loud")
    view.setSelectedRange(NSRange(location: 5, length: 2))
    press(view, "b")
    check("bold writes no marks into the text", view.string == "make me loud", view.string)
    check("bold bolds the selection", trait(view, 5, .boldFontMask))
    check("...and only the selection", !trait(view, 0, .boldFontMask))
    press(view, "b")
    check("bold pressed again unbolds", !trait(view, 5, .boldFontMask))

    view.setSelectedRange(NSRange(location: 0, length: 4))
    press(view, "i")
    check("italic italicises", trait(view, 0, .italicFontMask))
    press(view, "u")
    check("underline underlines", (attr(view, .underlineStyle, 0) as? Int ?? 0) != 0)
    press(view, "x", shift: true)
    check("strikethrough strikes", (attr(view, .strikethroughStyle, 0) as? Int ?? 0) != 0)
    check("the four stack on one another", trait(view, 0, .italicFontMask)
          && (attr(view, .underlineStyle, 0) as? Int ?? 0) != 0
          && (attr(view, .strikethroughStyle, 0) as? Int ?? 0) != 0)
    press(view, "u")
    check("...and come off one at a time", (attr(view, .underlineStyle, 0) as? Int ?? 0) == 0
          && (attr(view, .strikethroughStyle, 0) as? Int ?? 0) != 0)
}

do {
    let view = makeView(.richText, "abc")
    view.setSelectedRange(NSRange(location: 3, length: 0))
    press(view, "b")
    let armed = view.typingAttributes[.font] as? NSFont
    check("bold with no selection arms what you type next",
          NSFontManager.shared.traits(of: armed ?? NSFont.systemFont(ofSize: 14)).contains(.boldFontMask))
}

print("\nFiles on disk")
do {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("silica-test-\(UUID().uuidString)")
    let library = Library(folder: folder)

    var markdown = library.create(titled: "Plain", format: .markdown)
    markdown.text = "**loud**"
    library.write(markdown)
    check("a markdown note is a .md file", markdown.url.pathExtension == "md", markdown.url.lastPathComponent)
    check("...holding exactly what you typed",
          (try? String(contentsOf: markdown.url, encoding: .utf8)) == "**loud**")

    var rich = library.create(titled: "Styled", format: .richText)
    let styled = NSMutableAttributedString(string: "make me loud", attributes: [.font: NSFont.systemFont(ofSize: 14)])
    styled.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: .boldFontMask),
                        range: NSRange(location: 5, length: 2))
    rich.text = styled.string
    rich.rich = styled
    library.write(rich)
    check("a rich note is a .rtf file", rich.url.pathExtension == "rtf", rich.url.lastPathComponent)

    let reloaded = library.load().notes
    let reloadedRich = reloaded.first { $0.title == "Styled" }
    let reloadedPlain = reloaded.first { $0.title == "Plain" }
    check("both notes come back", reloadedRich != nil && reloadedPlain != nil)
    check("the rich note keeps its words", reloadedRich?.text == "make me loud", reloadedRich?.text ?? "nil")
    check("the rich note keeps its bold across a save and reload", {
        guard let font = reloadedRich?.rich?.attribute(.font, at: 5, effectiveRange: nil) as? NSFont else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }())
    check("the words are searchable, not the styling",
          !(reloadedRich?.text.contains("rtf") ?? true) && !(reloadedRich?.text.contains("\\\\b") ?? true))
    check("format is read off the file", reloadedRich?.format == .richText && reloadedPlain?.format == .markdown)

    try? FileManager.default.removeItem(at: folder)
}

print("\nA library reached through a shortcut")
do {
    // One file can arrive as several different URLs. When the library folder is
    // a symlink, the note created in memory and the same note read back off disk
    // spell their paths differently — which used to open a second tab for it on
    // every launch, and file its history under two names.
    let home = FileManager.default.homeDirectoryForCurrentUser
    let real = home.appendingPathComponent("Developer/.silica-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: real.appendingPathComponent("Notes"), withIntermediateDirectories: true)
    let link = home.appendingPathComponent("Developer/.silica-test-link-\(UUID().uuidString)")
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let folder = link.appendingPathComponent("Notes")
    let library = Library(folder: folder)

    var note = library.create(titled: "Alpha")
    note.text = "first"
    library.write(note)
    check("a note in it counts as a library note", library.contains(note.url))

    var tabs = [note]
    for pass in 1...3 {
        library.saveIndex(notes: tabs, activeID: tabs.first?.id)
        tabs = library.load().notes
        check("still one tab after reload \(pass)", tabs.count == 1, "\(tabs.count) tabs")
    }

    let store = VersionStore(libraryFolder: folder)
    store.snapshotIfNeeded(note, force: true)
    var reloaded = tabs[0]
    reloaded.text = "second"
    store.snapshotIfNeeded(reloaded, force: true)
    let piles = (try? FileManager.default.contentsOfDirectory(
        atPath: folder.appendingPathComponent(".silica-versions").path))?.sorted() ?? []
    check("its history lives in one folder", piles == ["Alpha"], "\(piles)")
    check("and the open tab can see all of it", store.versions(for: reloaded).count == 2,
          "\(store.versions(for: reloaded).count) versions")

    let outside = real.appendingPathComponent("Outside.md")
    try? "away".write(to: outside, atomically: true, encoding: .utf8)
    let opened = library.read(outside)
    check("a file from outside is still treated as outside", opened.map { !library.contains($0.url) } ?? false)
    library.saveIndex(notes: [reloaded, opened].compactMap { $0 }, activeID: opened?.id)
    check("both tabs come back, once each", library.load().notes.count == 2,
          "\(library.load().notes.map(\.title))")

    try? FileManager.default.removeItem(at: link)
    try? FileManager.default.removeItem(at: real)
}

print(failures == 0 ? "\nall checks passed\n" : "\n\(failures) FAILED\n")
exit(failures == 0 ? 0 : 1)
