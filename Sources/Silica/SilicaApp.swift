import SwiftUI
import AppKit
import Combine
import Sparkle

@main
struct SilicaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(state)
                .frame(minWidth: 420, minHeight: 300)
                .onAppear { delegate.adopt(state) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 660, height: 520)
        .commands { SilicaCommands(state: state) }
    }
}

// MARK: - Menus

struct SilicaCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { state.newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Close Tab") { if let id = state.activeID { state.close(id) } }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Quick Note") { AppDelegate.shared?.quickNote.toggle() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in All Notes…") { state.openSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Now") { state.flushAll() }
                .keyboardShortcut("s", modifiers: .command)
            Divider()
            Button("Export as Markdown…") { Export.markdown(state.active) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export as PDF…") { Export.pdf(state.active, fontSize: state.fontSize) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Button("Reveal Library in Finder") { state.revealFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Change Library Folder…") { state.chooseFolder() }
            if AppDelegate.shared?.updatesAvailable == true {
                Divider()
                Button("Check for Updates…") { AppDelegate.shared?.checkForUpdates() }
            }
        }

        // Folded into the system View menu rather than a second one beside it.
        CommandGroup(replacing: .toolbar) {
            Button(state.focusMode ? "Leave Focus Mode" : "Enter Focus Mode") { state.toggleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button(state.tabsVisible ? "Hide Tabs" : "Show Tabs") { state.toggleTabs() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Picker("Appearance", selection: $state.appearance) {
                Text("Light").tag(Appearance.light)
                Text("Dark").tag(Appearance.dark)
                Text("Match System").tag(Appearance.system)
            }
            Button("Switch Light / Dark") { state.toggleAppearance() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Toggle("Typewriter Scrolling", isOn: $state.typewriterMode)
            Divider()
            Button("Bigger Text") { state.nudgeFontSize(1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { state.nudgeFontSize(-1) }
                .keyboardShortcut("-", modifiers: .command)
        }

        CommandMenu("Item") {
            Button("Rename…") { state.renamingID = state.activeID }
                .keyboardShortcut("r", modifiers: .command)
            Button("Duplicate") { state.duplicateActive() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Version History…") { state.showingHistory = true }
                .keyboardShortcut("y", modifiers: .command)
            Button("Show in Finder") {
                if let url = state.active?.url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Divider()
            Button("Next Tab") { state.cycleTab(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { state.cycleTab(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("Move to Trash") { state.deleteActive() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}

// MARK: - Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    let quickNote = QuickNote()
    private var state: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var configured = false
    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard UpdateConfiguration.isConfigured else { return nil }
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    var updatesAvailable: Bool { UpdateConfiguration.isConfigured }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
    }

    func adopt(_ state: AppState) {
        guard !configured else { return }
        configured = true
        self.state = state
        quickNote.install(state: state)

        // Re-skin the window chrome whenever the theme flips, so the titlebar and
        // the paper are never two different whites for a frame.
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak state] _ in
                guard let state else { return }
                self?.style(for: state.appearance, resolved: state.resolvedAppearance)
            }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in
            self?.style(for: state.appearance, resolved: state.resolvedAppearance)
        }
    }

    private func style(for appearance: Appearance, resolved: Appearance) {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        window.appearance = appearance.nsAppearance
        window.backgroundColor = Palette.of(resolved).nsBackground
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.flushAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil) }
        return true
    }
}
