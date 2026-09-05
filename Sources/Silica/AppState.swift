import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var notes: [Note] = []
    @Published var activeID: UUID?

    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    /// The format new notes are created in. Existing notes keep their own.
    @Published var newNoteFormat: NoteFormat { didSet { defaults.set(newNoteFormat.rawValue, forKey: "newNoteFormat") } }
    @Published var tabsVisible: Bool { didSet { defaults.set(tabsVisible, forKey: "tabsVisible") } }
    @Published var focusMode: Bool { didSet { defaults.set(focusMode, forKey: "focusMode") } }
    @Published var typewriterMode: Bool { didSet { defaults.set(typewriterMode, forKey: "typewriterMode") } }
    @Published var showsDailyCount: Bool { didSet { defaults.set(showsDailyCount, forKey: "showsDailyCount") } }

    // MARK: Search
    @Published var searchOpen = false
    @Published var searchQuery = ""
    /// Set when a search result is picked; the editor consumes it once and scrolls.
    @Published var pendingSelection: PendingSelection?

    // MARK: Version history
    @Published var showingHistory = false

    /// Words written today, counted as they are typed rather than measured against
    /// yesterday's files, so edits in other apps never inflate it.
    @Published private(set) var wordsToday: Int = 0

    /// Tab currently being renamed inline, if any.
    @Published var renamingID: UUID?

    /// Mirrors the macOS setting so the `system` appearance can repaint live.
    @Published private var systemIsDark = Appearance.systemIsDark

    private let defaults = UserDefaults.standard
    private(set) var library: Library
    private(set) var versions: VersionStore
    private var saveWork: [UUID: DispatchWorkItem] = [:]

    static let fontSizeRange: ClosedRange<Double> = 10...28

    /// What `appearance` actually means right now — `system` follows macOS.
    var resolvedAppearance: Appearance {
        appearance == .system ? (systemIsDark ? .dark : .light) : appearance
    }

    var palette: Palette { Palette.of(resolvedAppearance) }

    var active: Note? {
        get { notes.first { $0.id == activeID } }
        set {
            guard let newValue, let i = notes.firstIndex(where: { $0.id == newValue.id }) else { return }
            notes[i] = newValue
        }
    }

    init() {
        defaults.register(defaults: [
            "appearance": Appearance.light.rawValue,
            "fontSize": 14.0,
            "newNoteFormat": NoteFormat.markdown.rawValue,
            "tabsVisible": true,
            "focusMode": false,
            "typewriterMode": false,
            "showsDailyCount": true
        ])
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .light
        fontSize = defaults.double(forKey: "fontSize")
        newNoteFormat = NoteFormat(rawValue: defaults.string(forKey: "newNoteFormat") ?? "") ?? .markdown
        tabsVisible = defaults.bool(forKey: "tabsVisible")
        focusMode = defaults.bool(forKey: "focusMode")
        typewriterMode = defaults.bool(forKey: "typewriterMode")
        showsDailyCount = defaults.bool(forKey: "showsDailyCount")

        let folder = AppState.storedFolder(defaults) ?? AppState.defaultFolder
        library = Library(folder: folder)
        versions = VersionStore(libraryFolder: folder)

        let loaded = library.load()
        notes = loaded.notes
        activeID = loaded.activeID
        wordsToday = AppState.readWordsToday(defaults)

        // macOS posts this when the user flips Light/Dark in System Settings.
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification lands a beat before the app's effective appearance
            // updates, so the read is deferred by a runloop turn.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.systemIsDark = Appearance.systemIsDark }
            }
        }

    }

    static var defaultFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let silica = documents.appendingPathComponent("Silica")
        let legacyManila = documents.appendingPathComponent("Manila")
        // Keep existing users on their current library after the app rename.
        return FileManager.default.fileExists(atPath: silica.path) || !FileManager.default.fileExists(atPath: legacyManila.path)
            ? silica
            : legacyManila
    }

    private static func storedFolder(_ defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: "libraryPath") else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Tabs

    func newTab() {
        let note = library.create(titled: "Untitled", format: newNoteFormat, avoiding: Set(notes.map(\.title)))
        notes.append(note)
        activeID = note.id
        persistIndex()
    }

    func select(_ id: UUID) {
        activeID = id
        persistIndex()
    }

    func close(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        flush(id)

        // Empty, never-written tabs have no file for `flush` to create, so there
        // is nothing to clean up here. In particular, do not trash an existing
        // note merely because its current text is empty.
        notes.remove(at: i)

        if notes.isEmpty {
            newTab()
        } else if activeID == id {
            activeID = notes[min(i, notes.count - 1)].id
        }
        persistIndex()
    }

    func deleteActive() {
        guard let note = active else { return }
        saveWork[note.id]?.cancel()
        library.trash(note)
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes.remove(at: i)
        if notes.isEmpty { newTab() } else if activeID == note.id { activeID = notes[min(i, notes.count - 1)].id }
        persistIndex()
    }

    func duplicateActive() {
        guard let note = active else { return }
        var copy = library.create(titled: "\(note.title) copy", format: note.format, avoiding: Set(notes.map(\.title)))
        copy.text = note.text
        copy.rich = note.rich
        library.write(copy)
        notes.append(copy)
        activeID = copy.id
        persistIndex()
    }

    func cycleTab(by step: Int) {
        guard notes.count > 1, let i = notes.firstIndex(where: { $0.id == activeID }) else { return }
        let next = (i + step + notes.count) % notes.count
        select(notes[next].id)
    }

    // MARK: - Editing

    func updateText(_ text: String, rich: NSAttributedString? = nil, for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let styleChanged = notes[i].format == .richText && rich != nil
        guard notes[i].text != text || styleChanged else { return }
        let before = AppState.wordCount(notes[i].text)
        notes[i].text = text
        if notes[i].format == .richText { notes[i].rich = rich }
        // Only growth counts. Deleting a paragraph shouldn't put the day's total
        // into reverse, and rewriting a sentence shouldn't count it twice.
        let added = AppState.wordCount(text) - before
        if added > 0 { addWordsToday(added) }
        scheduleSave(id)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func addWordsToday(_ count: Int) {
        let today = AppState.todayKey
        if defaults.string(forKey: "wordsTodayDate") != today {
            defaults.set(today, forKey: "wordsTodayDate")
            wordsToday = 0
        }
        wordsToday += count
        defaults.set(wordsToday, forKey: "wordsTodayCount")
    }

    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func readWordsToday(_ defaults: UserDefaults) -> Int {
        // A count from yesterday is simply not today's count.
        defaults.string(forKey: "wordsTodayDate") == todayKey
            ? defaults.integer(forKey: "wordsTodayCount")
            : 0
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if let url = library.rename(notes[i], to: title) {
            versions.rename(from: notes[i].url, to: url)
            notes[i].url = url
            notes[i].title = url.deletingPathExtension().lastPathComponent
            persistIndex()
        }
    }

    /// Text is written 600ms after the last keystroke. Fast enough that a crash
    /// costs a sentence, slow enough that it isn't one disk write per character.
    private func scheduleSave(_ id: UUID) {
        saveWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.flush(id) }
        }
        saveWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func flush(_ id: UUID) {
        saveWork[id]?.cancel()
        saveWork[id] = nil
        guard let note = notes.first(where: { $0.id == id }) else { return }
        library.write(note)
        versions.snapshotIfNeeded(note)
    }

    func flushAll() {
        for note in notes { flush(note.id) }
        persistIndex()
    }

    private func persistIndex() {
        library.saveIndex(notes: notes, activeID: activeID)
    }

    // MARK: - Library folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Pick the folder Silica keeps your notes in."
        panel.directoryURL = library.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard url.standardizedFileURL != library.folder.standardizedFileURL else { return }

        flushAll()
        do {
            // Copy history first. If either transfer fails, the active library and
            // its saved location remain unchanged.
            try versions.copy(to: url)
            try library.move(to: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        versions.relocate(to: url)
        defaults.set(url.path, forKey: "libraryPath")
        let loaded = library.load()
        notes = loaded.notes
        activeID = loaded.activeID
    }

    func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([library.folder])
    }

    // MARK: - Search

    func openSearch() {
        searchOpen = true
    }

    func closeSearch() {
        searchOpen = false
        searchQuery = ""
    }

    /// Jump to a search result: switch tabs if needed, then hand the editor a
    /// range to select so the match is on screen and already highlighted.
    func reveal(_ hit: SearchHit) {
        if activeID != hit.noteID { select(hit.noteID) }
        pendingSelection = PendingSelection(noteID: hit.noteID, location: hit.offset, length: hit.length)
        closeSearch()
    }

    // MARK: - Version history

    func restore(_ version: Version) {
        guard let note = active, let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        // Snapshot what is on screen first, so restoring is itself undoable.
        versions.snapshotIfNeeded(note, force: true)
        notes[i].text = versions.text(of: version)
        library.write(notes[i])
        showingHistory = false
    }

    // MARK: - View toggles

    func toggleFocus() { withAnimation(.easeOut(duration: 0.25)) { focusMode.toggle() } }
    func toggleTabs() { withAnimation(.easeOut(duration: 0.25)) { tabsVisible.toggle() } }
    func toggleAppearance() {
        withAnimation(.easeInOut(duration: 0.2)) {
            appearance = resolvedAppearance == .light ? .dark : .light
        }
    }

    func nudgeFontSize(_ delta: Double) {
        fontSize = min(max(fontSize + delta, AppState.fontSizeRange.lowerBound), AppState.fontSizeRange.upperBound)
    }
}

/// A range the editor should select and scroll to, once.
struct PendingSelection: Equatable {
    let token = UUID()
    let noteID: UUID
    let location: Int
    let length: Int
}
