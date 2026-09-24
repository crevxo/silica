import Foundation

struct Version: Identifiable, Hashable {
    let id: URL
    let date: Date

    var url: URL { id }
}

/// Point-in-time copies of every note, kept in a hidden folder beside the notes
/// themselves. Autosave overwrites the file constantly, so without this there is
/// nothing to go back to when a paragraph is deleted by accident.
final class VersionStore {
    /// A snapshot is taken at most this often, and only when the text changed.
    private let interval: TimeInterval = 5 * 60
    /// Enough history to cover a few days of writing without growing forever.
    private let keep = 30

    private var folder: URL
    private var libraryFolder: URL
    /// When each note was last snapshotted, so the common case needs no disk read.
    private var lastSnapshot: [URL: Date] = [:]

    init(libraryFolder: URL) {
        self.libraryFolder = libraryFolder
        folder = VersionStore.folder(in: libraryFolder)
    }

    func relocate(to libraryFolder: URL) {
        self.libraryFolder = libraryFolder
        folder = VersionStore.folder(in: libraryFolder)
        lastSnapshot.removeAll()
    }

    /// History written before the app was renamed lives under the old name; it is
    /// moved across the first time a library is opened.
    private static func folder(in libraryFolder: URL) -> URL {
        let current = libraryFolder.appendingPathComponent(".silica-versions")
        let legacy = libraryFolder.appendingPathComponent(".manila-versions")
        let fm = FileManager.default
        if fm.fileExists(atPath: legacy.path) && !fm.fileExists(atPath: current.path) {
            try? fm.moveItem(at: legacy, to: current)
        }
        return current
    }

    /// Copy history into a prospective library folder without changing the active
    /// location. This lets the caller keep using the original library on failure.
    func copy(to libraryFolder: URL) throws {
        let destination = VersionStore.folder(in: libraryFolder)
        guard destination.standardizedFileURL != folder.standardizedFileURL else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for sourceNoteFolder in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) {
            guard (try sourceNoteFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let destinationNoteFolder = destination.appendingPathComponent(sourceNoteFolder.lastPathComponent)
            try fm.createDirectory(at: destinationNoteFolder, withIntermediateDirectories: true)

            for version in try fm.contentsOfDirectory(at: sourceNoteFolder, includingPropertiesForKeys: nil) {
                let destinationVersion = destinationNoteFolder.appendingPathComponent(version.lastPathComponent)
                if !fm.fileExists(atPath: destinationVersion.path) {
                    try fm.copyItem(at: version, to: destinationVersion)
                }
            }
        }
    }

    private func folder(for note: Note) -> URL {
        folder.appendingPathComponent(pile(for: note.url))
    }

    /// Keyed by filename so a note's history follows it, and edits made in
    /// another editor still land in the same pile. A file opened from outside
    /// the library carries its folder in the key so it never shares a pile
    /// with a library note of the same name.
    private func pile(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        // Compared and hashed in one canonical form, so the same note cannot be
        // handed two piles depending on which spelling of its path it carries.
        let parent = Library.canonical(url.deletingLastPathComponent())
        guard parent != Library.canonical(libraryFolder) else { return stem }
        // A stable hash: Swift's hashValue is re-seeded on every launch, which
        // would give the file a fresh history folder each time it is opened.
        var h: UInt32 = 5381
        for byte in parent.utf8 { h = (h &* 33) &+ UInt32(byte) }
        return "\(stem)@\(String(format: "%08x", h))"
    }

    func versions(for note: Note) -> [Version] {
        let dir = folder(for: note)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "txt" }
            .compactMap { url in
                guard let stamp = TimeInterval(url.deletingPathExtension().lastPathComponent) else { return nil }
                return Version(id: url, date: Date(timeIntervalSince1970: stamp))
            }
            .sorted { $0.date > $1.date }
    }

    func text(of version: Version) -> String {
        (try? String(contentsOf: version.url, encoding: .utf8)) ?? ""
    }

    /// Called on every save. Writes only when the interval has passed and the text
    /// differs from the newest snapshot, so an idle app writes nothing.
    func snapshotIfNeeded(_ note: Note, force: Bool = false) {
        guard !note.text.isEmpty else { return }

        // Saves land every 600ms of typing; snapshots are five minutes apart. Most
        // calls can be answered from memory without touching the disk at all.
        if !force, let last = lastSnapshot[note.url], Date().timeIntervalSince(last) < interval { return }

        let existing = versions(for: note)
        if let newest = existing.first {
            // Cheapest test first: the interval is a date, the comparison is a file.
            if !force, Date().timeIntervalSince(newest.date) < interval {
                lastSnapshot[note.url] = newest.date
                return
            }
            if text(of: newest) == note.text { return }
        }

        let dir = folder(for: note)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var timestamp = Date().timeIntervalSince1970
        var url = dir.appendingPathComponent(String(timestamp)).appendingPathExtension("txt")
        while FileManager.default.fileExists(atPath: url.path) {
            timestamp += 0.001
            url = dir.appendingPathComponent(String(timestamp)).appendingPathExtension("txt")
        }
        try? note.text.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        lastSnapshot[note.url] = Date(timeIntervalSince1970: timestamp)

        for old in existing.dropFirst(keep - 1) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    /// Renaming a note moves its history with it, so history is never orphaned.
    func rename(from old: URL, to new: URL) {
        let source = folder.appendingPathComponent(pile(for: old))
        let dest = folder.appendingPathComponent(pile(for: new))
        lastSnapshot[new] = lastSnapshot.removeValue(forKey: old)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.moveItem(at: source, to: dest)
    }
}
