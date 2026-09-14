import SwiftUI
import AppKit
import Combine
import Sparkle

@main
struct SilicaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        // One editor window, ever. A `WindowGroup` would also open a second
        // window of its own for every file Finder hands us, on top of the tab
        // the delegate makes for it.
        Window("Silica", id: "main") {
            MainWindow()
                .environmentObject(state)
                .frame(minWidth: 420, minHeight: 300)
                .onAppear { delegate.adopt(state) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 660, height: 520)
        .commands { SilicaCommands(state: state) }

        Settings {
            SettingsWindow().environmentObject(state)
        }
    }
}

// MARK: - Menus

struct SilicaCommands: Commands {
    @ObservedObject var state: AppState

    /// Hand the command to whatever is focused — the editor, if the caret is in it.
    static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

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
            Button("Export as PDF…") { Export.pdf(state.active, fontSize: state.fontSize, fontFamily: state.fontFamily) }
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

        CommandMenu("Format") {
            Button("Bold") { SilicaCommands.send(#selector(PlainTextView.silicaToggleBold(_:))) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { SilicaCommands.send(#selector(PlainTextView.silicaToggleItalic(_:))) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Underline") { SilicaCommands.send(#selector(PlainTextView.silicaToggleUnderline(_:))) }
                .keyboardShortcut("u", modifiers: .command)
            Button("Strikethrough") { SilicaCommands.send(#selector(PlainTextView.silicaToggleStrikethrough(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
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
    /// The editor window, as told to us by the view inside it. Found this way
    /// rather than as "the first non-panel window" because the Settings window
    /// is also a plain window and must not be restyled as the editor.
    weak var mainWindow: NSWindow? {
        didSet { if let state { style(for: state.appearance, resolved: state.resolvedAppearance) } }
    }
    private var state: AppState?
    /// Files Finder asked us to open before the state existed to open them in.
    private var pendingOpens: [URL] = []
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

    private var termSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)

        // A plain SIGTERM (Activity Monitor, `kill`, logout) would skip
        // applicationWillTerminate and drop the last 600 ms of typing; turn it
        // into an ordinary quit so everything is flushed.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSignal = source
    }

    func adopt(_ state: AppState) {
        guard !configured else { return }
        configured = true
        self.state = state
        quickNote.install(state: state)
        if !pendingOpens.isEmpty {
            state.open(pendingOpens)
            pendingOpens = []
        }
        // Constructing the controller starts Sparkle's scheduled update cycle.
        // It remains nil in development builds without a public signing key.
        _ = updaterController

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

    /// Finder: double-click, Open With, or a drop on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let state {
            state.open(urls)
            showEditor()
        } else {
            pendingOpens.append(contentsOf: urls)
        }
    }

    /// Show the editor window. If the user closed it (the app keeps running
    /// without one), ask SwiftUI to make it again the same way a Dock click
    /// does: a reopen event sent to ourselves.
    func showEditor() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: [.noReply], timeout: 1)
    }

    private func style(for appearance: Appearance, resolved: Appearance) {
        guard let window = mainWindow else { return }
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
        if !flag { mainWindow?.makeKeyAndOrderFront(nil) }
        return true
    }
}
