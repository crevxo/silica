import AppKit

enum LibraryError: LocalizedError {
    case conflictingFile(String)

    var errorDescription: String? {
        switch self {
        case .conflictingFile(let name):
            return "The destination already contains a different note named ‘\(name)’. No files were replaced."
        }
    }
}

/// One open note. `url` is the real file on disk — the note *is* the file, so a
/// rename here is a rename in Finder and nothing lives in a database.
struct Note: Identifiable, Equatable {
    let id: UUID
    var title: String
    /// Always the plain words, whatever the file format — search, word counts and
    /// version history all read this and never have to know about styling.
    var text: String
    /// Set only for a rich-text note: the styling its file carries.
    var rich: NSAttributedString?
    var url: URL

    var format: NoteFormat { NoteFormat.of(url) }

    /// Compared by what is shown, not just identity: SwiftUI skips redrawing
    /// a tab whose note it considers "equal", so a rename must count as a change.
    static func == (a: Note, b: Note) -> Bool {
        a.id == b.id && a.title == b.title && a.url == b.url && a.text == b.text
    }
}

/// A plain folder of .md files. No index of contents, no cache of the text —
/// re-reading the folder is the source of truth, which is what makes the folder
/// safe to edit from Finder, a git repo, or another editor.
final class Library {
    /// Only tab order and which tab was active are ours to remember; that goes in
    /// a dotfile so it never shows up as a note.
    private struct Index: Codable {
        /// Library notes by filename; files opened from elsewhere by full path.
        var order: [String] = []
        var active: String?
    }

    /// True if `url` lives directly in the library folder.
    func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL
    }

    /// How a note is written into the index: a bare filename for library notes,
    /// a full path for anything opened from outside.
    private func key(for url: URL) -> String {
        contains(url) ? url.lastPathComponent : url.standardizedFileURL.path
    }

    private(set) var folder: URL

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private var indexURL: URL { folder.appendingPathComponent(".silica-tabs.json") }

    /// Libraries written before the app was renamed keep their tab order in a
    /// differently-named dotfile. Move it across once, quietly.
    private func adoptLegacyIndex() {
        let legacy = folder.appendingPathComponent(".manila-tabs.json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: indexURL.path) else { return }
        try? fm.moveItem(at: legacy, to: indexURL)
    }

    func move(to newFolder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: newFolder, withIntermediateDirectories: true)
        for file in noteFiles(in: folder) {
            let dest = newFolder.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                guard try Data(contentsOf: file) == Data(contentsOf: dest) else {
                    throw LibraryError.conflictingFile(file.lastPathComponent)
                }
            } else {
                try fm.copyItem(at: file, to: dest)
            }
        }
        if fm.fileExists(atPath: indexURL.path) {
            let dest = newFolder.appendingPathComponent(indexURL.lastPathComponent)
            // Atomic replacement leaves an existing destination index intact if
            // writing the copied index fails.
            try Data(contentsOf: indexURL).write(to: dest, options: .atomic)
        }
        folder = newFolder
    }

    private func noteFiles(in dir: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { ["md", "txt", "markdown", "rtf"].contains($0.pathExtension.lowercased()) }
    }

    // MARK: - Loading

    func load() -> (notes: [Note], activeID: UUID?) {
        adoptLegacyIndex()
        let index = (try? JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))) ?? Index()

        var loaded: [Note] = []
        for url in noteFiles(in: folder) {
            var text = ""
            var rich: NSAttributedString?
            if NoteFormat.of(url) == .richText {
                rich = (try? Data(contentsOf: url)).flatMap {
                    NSAttributedString(rtf: $0, documentAttributes: nil)
                }
                text = rich?.string ?? ""
            } else {
                text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            loaded.append(Note(
                id: UUID(),
                title: url.deletingPathExtension().lastPathComponent,
                text: text,
                rich: rich,
                url: url
            ))
        }

        // Tabs opened from outside the library come back too, if still there.
        for entry in index.order where entry.hasPrefix("/") {
            let url = URL(fileURLWithPath: entry)
            if !contains(url), let note = read(url) { loaded.append(note) }
        }

        // Remembered order first, anything new (dropped in from Finder) after it.
        // A repeated key (a bad index, or a hand edit) must not be fatal.
        let position = Dictionary(index.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        loaded.sort { a, b in
            let pa = position[key(for: a.url)] ?? Int.max
            let pb = position[key(for: b.url)] ?? Int.max
            if pa != pb { return pa < pb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }

        if loaded.isEmpty {
            let note = create(titled: "Untitled")
            return ([note], note.id)
        }

        let active = loaded.first { key(for: $0.url) == index.active } ?? loaded.first
        return (loaded, active?.id)
    }

    /// One file, from anywhere on disk. Nil if it cannot be read as text.
    func read(_ url: URL) -> Note? {
        var rich: NSAttributedString?
        let text: String
        if NoteFormat.of(url) == .richText {
            guard let data = try? Data(contentsOf: url),
                  let parsed = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil }
            rich = parsed
            text = parsed.string
        } else {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            text = contents
        }
        return Note(
            id: UUID(),
            title: url.deletingPathExtension().lastPathComponent,
            text: text,
            rich: rich,
            url: url
        )
    }

    func saveIndex(notes: [Note], activeID: UUID?) {
        let index = Index(
            order: notes.map { key(for: $0.url) },
            active: notes.first { $0.id == activeID }.map { key(for: $0.url) }
        )
        try? JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    // MARK: - Mutating

    /// Nothing is written until there is something to write. A tab you open and
    /// never type in leaves no file behind, so the folder only ever holds writing.
    func create(titled desired: String, format: NoteFormat = .markdown, avoiding inMemory: Set<String> = []) -> Note {
        let title = uniqueTitle(from: desired, excluding: nil, alsoTaken: inMemory)
        let url = folder.appendingPathComponent(title).appendingPathExtension(format.fileExtension)
        return Note(id: UUID(), title: title, text: "", rich: nil, url: url)
    }

    func write(_ note: Note) {
        let exists = FileManager.default.fileExists(atPath: note.url.path)
        guard exists || !note.text.isEmpty else { return }
        if note.format == .richText, let rich = note.rich {
            let range = NSRange(location: 0, length: rich.length)
            guard let data = rich.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return }
            try? data.write(to: note.url, options: .atomic)
        } else {
            try? note.text.write(to: note.url, atomically: true, encoding: .utf8)
        }
    }

    /// Returns the new URL, or nil if the rename was refused (empty or unchanged).
    func rename(_ note: Note, to desired: String, avoiding inMemory: Set<String> = []) -> URL? {
        let cleaned = desired.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != note.title else { return nil }
        // Unsaved tabs have no file yet, so the folder alone cannot say their
        // names are taken; the caller passes what is open.
        // Collisions are checked where the file actually is, which for a note
        // opened from Finder may not be the library.
        let title = uniqueTitle(from: cleaned, in: note.url.deletingLastPathComponent(), excluding: note.url, alsoTaken: inMemory)
        let dest = note.url.deletingLastPathComponent()
            .appendingPathComponent(title)
            .appendingPathExtension(note.url.pathExtension.isEmpty ? "md" : note.url.pathExtension)
        // An unsaved tab has no file yet; renaming it just picks a different name
        // for the file it will eventually get.
        guard FileManager.default.fileExists(atPath: note.url.path) else { return dest }
        do {
            try FileManager.default.moveItem(at: note.url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// Deleting goes to the Trash, never to /dev/null — a closed tab should always
    /// be recoverable by the person who closed it.
    func trash(_ note: Note) {
        guard FileManager.default.fileExists(atPath: note.url.path) else { return }
        try? FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
    }

    private func uniqueTitle(from desired: String, in dir: URL? = nil, excluding: URL?, alsoTaken: Set<String>) -> String {
        let illegal = CharacterSet(charactersIn: "/:")
        let base = desired
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = base.isEmpty ? "Untitled" : base

        var taken = Set(noteFiles(in: dir ?? folder)
            .filter { $0 != excluding }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        taken.formUnion(alsoTaken.map { $0.lowercased() })

        if !taken.contains(stem.lowercased()) { return stem }
        var n = 2
        while taken.contains("\(stem) \(n)".lowercased()) { n += 1 }
        return "\(stem) \(n)"
    }
}
