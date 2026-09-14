import SwiftUI
import AppKit

/// The preferences window, reached with ⌘, or the gear in the status bar.
struct SettingsWindow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            EditorSettings()
                .tabItem { Label("Editor", systemImage: "textformat") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            LibrarySettings()
                .tabItem { Label("Library", systemImage: "folder") }
        }
        .frame(width: 440)
        .environment(\.palette, state.palette)
        .preferredColorScheme(state.resolvedAppearance == .light ? .light : .dark)
    }
}

private struct EditorSettings: View {
    @EnvironmentObject var state: AppState

    /// Every family the system knows, with the system font first. Built once —
    /// the font manager walks the whole font table to answer.
    private static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $state.fontFamily) {
                    Text("System").tag("")
                    Divider()
                    ForEach(Self.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                HStack {
                    Slider(value: $state.fontSize, in: AppState.fontSizeRange, step: 1) {
                        Text("Size")
                    }
                    Text("\(Int(state.fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                Text("The quick brown fox jumps over the lazy dog.")
                    .font(Font(PlainTextView.font(family: state.fontFamily, size: state.fontSize)))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Section("Writing") {
                Picker("New notes", selection: $state.newNoteFormat) {
                    ForEach(NoteFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Hide Markdown syntax", isOn: $state.hideMarkdownSyntax)
                Toggle("Typewriter scrolling", isOn: $state.typewriterMode)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $state.appearance) {
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                    Text("Match System").tag(Appearance.system)
                }
                .pickerStyle(.segmented)
            }
            Section("Chrome") {
                Toggle("Show tabs", isOn: $state.tabsVisible)
                Toggle("Words written today", isOn: $state.showsDailyCount)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LibrarySettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Notes folder") {
                Text(state.library.folder.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack {
                    Button("Change…") { state.chooseFolder() }
                    Button("Reveal in Finder") { state.revealFolder() }
                }
            }
            Section {
                LabeledContent("Version", value: UpdateConfiguration.version)
                if AppDelegate.shared?.updatesAvailable == true {
                    Button("Check for Updates…") { AppDelegate.shared?.checkForUpdates() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
