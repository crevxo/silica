import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let palette = state.palette

        VStack(spacing: 0) {
            if !state.focusMode {
                TabBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            editor

            if !state.focusMode {
                StatusBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if state.searchOpen {
                SearchPanel()
            } else if state.focusMode {
                FocusExitBar()
            }
        }
        .sheet(isPresented: $state.showingHistory) {
            VersionHistorySheet().environmentObject(state)
        }
        .background(palette.background)
        // The tab row has to reach the traffic lights, so the view is allowed under
        // the titlebar instead of stopping at SwiftUI's top safe area.
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.palette, palette)
        .preferredColorScheme(state.resolvedAppearance == .light ? .light : .dark)
        .onReceive(NotificationCenter.default.publisher(for: .silicaEscape)) { _ in
            if state.focusMode { state.toggleFocus() }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let note = state.active {
            Editor(
                noteID: note.id,
                text: note.text,
                fontSize: state.fontSize,
                palette: state.palette,
                typewriter: state.typewriterMode,
                selection: state.pendingSelection,
                onChange: { state.updateText($0, for: note.id) }
            )
            .id(note.id)
        } else {
            Color.clear
        }
    }
}

/// Focus mode hides every control, which leaves no obvious way back out. This
/// puts one there: a hint on the way in, and a bar that comes back whenever the
/// pointer goes looking for it near the top of the window.
private struct FocusExitBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette
    @State private var hovering = false
    @State private var showingHint = true

    private var visible: Bool { hovering || showingHint }

    var body: some View {
        ZStack(alignment: .top) {
            // An invisible strip along the top edge is the hit area, so the bar
            // appears before the pointer has to find anything specific.
            Color.clear
                .frame(height: 56)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.18)) { self.hovering = hovering }
                }

            HStack(spacing: 10) {
                Text(state.active?.title ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)

                Text("esc")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.inkSoft)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.pill))

                Button {
                    state.toggleFocus()
                } label: {
                    Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                }
                .buttonStyle(.plain)
                .help("Leave focus mode")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(palette.pillActive)
                    .overlay(Capsule().strokeBorder(palette.pillBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
            }
            .padding(.top, 12)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -6)
            .allowsHitTesting(visible)
        }
        .animation(.easeOut(duration: 0.18), value: visible)
        .onAppear {
            showingHint = true
            // Long enough to read once, short enough not to be chrome.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation { showingHint = false }
            }
        }
    }
}

// MARK: - Tabs

struct TabBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            // Room for the traffic lights, which the window draws itself.
            Spacer().frame(width: 70)

            if state.tabsVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(state.notes) { note in
                            TabPill(note: note)
                        }
                    }
                }
                addButton
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(state.active?.title ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
                addButton
            }

            OverflowMenu()
        }
        .padding(.horizontal, 12)
        // The traffic lights sit 14pt down from the top of the window and the app
        // does not draw them, so the tab row hangs from the top to meet them
        // instead of centring in a band of its own.
        .padding(.top, 5)
        .padding(.bottom, 18)
        .background(palette.background)
    }

    private var addButton: some View {
        IconButton(systemName: "plus", help: "New tab") { state.newTab() }
    }
}

private struct TabPill: View {
    let note: Note
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var isActive: Bool { state.activeID == note.id }
    private var isRenaming: Bool { state.renamingID == note.id }

    var body: some View {
        HStack(spacing: 6) {
            if isRenaming {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .focused($editing)
                    .frame(width: 96)
                    .onSubmit(commit)
                    .onChange(of: editing) { _, focused in if !focused { commit() } }
                    .onAppear { draft = note.title; editing = true }
            } else {
                // Clamped by character count rather than by a max width, so a pill
                // is only ever as wide as its name instead of reserving the cap.
                Text(note.title.clipped(to: 20))
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? palette.ink : palette.inkSoft)
                    .lineLimit(1)
            }

            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.inkSoft)
                .frame(width: 13, height: 13)
                .background(Circle().fill(palette.pill.opacity(hovering ? 1 : 0)))
                .opacity(hovering || isActive ? 0.65 : 0)
                .onTapGesture { state.close(note.id) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? palette.pillActive : (hovering ? palette.pill : .clear))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? palette.pillBorder : .clear, lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { state.renamingID = note.id }
        .onTapGesture { state.select(note.id) }
        .contextMenu {
            Button("Rename") { state.renamingID = note.id }
            Button("Duplicate") { state.select(note.id); state.duplicateActive() }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([note.url])
            }
            Divider()
            Button("Close Tab") { state.close(note.id) }
            Button("Move to Trash") { state.select(note.id); state.deleteActive() }
        }
    }

    private func commit() {
        guard isRenaming else { return }
        state.rename(note.id, to: draft)
        state.renamingID = nil
    }
}

private struct OverflowMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        Menu {
            Button("Find in All Notes…") { state.openSearch() }
            Button("Version History…") { state.showingHistory = true }
            Divider()
            Button(state.focusMode ? "Leave Focus Mode" : "Focus Mode") { state.toggleFocus() }
            Button(state.tabsVisible ? "Hide Tabs" : "Show Tabs") { state.toggleTabs() }
            Button(state.appearance == .light ? "Dark Appearance" : "Light Appearance") { state.toggleAppearance() }
            Divider()
            Button("Export as Markdown…") { Export.markdown(state.active) }
            Button("Export as PDF…") { Export.pdf(state.active, fontSize: state.fontSize) }
            Divider()
            Button("Reveal Library in Finder") { state.revealFolder() }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.inkSoft)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 24)
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? palette.ink : palette.inkSoft)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? palette.pill : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette
    @State private var showingSettings = false

    var body: some View {
        HStack {
            Text(stats)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.inkSoft)
            Spacer()
            IconButton(systemName: "gearshape", help: "Settings") { showingSettings.toggle() }
                .popover(isPresented: $showingSettings, arrowEdge: .top) {
                    SettingsPopover().environmentObject(state)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(palette.background)
    }

    private var stats: String {
        let text = state.active?.text ?? ""
        let words = AppState.wordCount(text)
        var parts = ["\(words) words"]
        if state.showsDailyCount { parts.append("\(state.wordsToday) today") }
        return parts.joined(separator: " · ")
    }
}

extension String {
    func clipped(to limit: Int) -> String {
        count <= limit ? self : String(prefix(limit - 1)) + "…"
    }
}
