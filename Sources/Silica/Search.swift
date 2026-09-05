import SwiftUI

struct SearchHit: Identifiable, Hashable {
    /// Derived rather than fresh: a hit at the same place in the same note is the
    /// same row, so the results list stops rebuilding itself on every keystroke.
    var id: String { "\(noteID)@\(offset)" }
    let noteID: UUID
    let noteTitle: String
    let line: String
    /// Character offset of the match in the whole note, for scrolling to it.
    let offset: Int
    let length: Int
}

/// Every note is already in memory, so search is a plain scan — no index to build,
/// nothing to keep in sync, and results appear as fast as you type.
enum SearchEngine {
    static func run(_ query: String, over notes: [Note], preferring activeID: UUID?) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }

        var hits: [SearchHit] = []
        noteLoop: for note in notes {
            let text = note.text
            var cursor = text.startIndex
            while let found = text.range(of: needle, options: .caseInsensitive, range: cursor..<text.endIndex) {
                let lineStart = text[..<found.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                let lineEnd = text[found.upperBound...].firstIndex(of: "\n") ?? text.endIndex
                hits.append(SearchHit(
                    noteID: note.id,
                    noteTitle: note.title,
                    line: String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces),
                    offset: text.utf16.distance(from: text.startIndex, to: found.lowerBound),
                    length: needle.utf16.count
                ))
                cursor = found.upperBound
                if hits.count == 200 { break noteLoop }
            }
        }

        // Matches in the note you are looking at come first; everything else keeps
        // the tab order, so results stay where you expect them between keystrokes.
        return hits.sorted { a, b in
            let aActive = a.noteID == activeID, bActive = b.noteID == activeID
            if aActive != bActive { return aActive }
            return false
        }
    }
}

struct SearchPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool
    @State private var selection = 0

    private var hits: [SearchHit] {
        SearchEngine.run(state.searchQuery, over: state.notes, preferring: state.activeID)
    }

    var body: some View {
        let results = hits

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkSoft)

                TextField("Search all notes", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink)
                    .focused($focused)
                    .onSubmit { open(results.indices.contains(selection) ? results[selection] : results.first) }

                if !results.isEmpty {
                    Text("\(results.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                }

                Button {
                    state.closeSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if !results.isEmpty {
                Divider().overlay(palette.line)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                            row(hit, selected: index == selection)
                                .onTapGesture { open(hit) }
                                .onHover { if $0 { selection = index } }
                        }
                    }
                }
                // Sized to the results rather than to the cap, so two matches
                // don't open a panel built for ten.
                .frame(height: min(CGFloat(results.count) * 46, 260))
            } else if state.searchQuery.count >= 2 {
                Divider().overlay(palette.line)
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkSoft)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 420)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.pillActive)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.pillBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        }
        .padding(.top, state.focusMode ? 14 : 8)
        .onAppear { focused = true }
        .onExitCommand { state.closeSearch() }
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            if direction == .down { selection = min(selection + 1, results.count - 1) }
            if direction == .up { selection = max(selection - 1, 0) }
        }
        .onChange(of: state.searchQuery) { _, _ in selection = 0 }
    }

    private func row(_ hit: SearchHit, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.noteTitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.inkSoft)
            Text(hit.line.clipped(to: 90))
                .font(.system(size: 12))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? palette.pill : .clear)
        .contentShape(Rectangle())
    }

    private func open(_ hit: SearchHit?) {
        guard let hit else { return }
        state.reveal(hit)
    }
}
