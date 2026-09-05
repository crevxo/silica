import AppKit
import SwiftUI
import Carbon.HIToolbox

/// A scratch pad that lives in the menu bar and is reachable from any app with
/// ⌥⌘N. It is deliberately one buffer, not a list — if a thought is worth
/// keeping it gets pushed into the library as a real note.
@MainActor
final class QuickNote: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private weak var state: AppState?

    private static let storageKey = "quickNoteText"

    var text: String {
        get { UserDefaults.standard.string(forKey: Self.storageKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.storageKey) }
    }

    func install(state: AppState) {
        self.state = state

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.append", accessibilityDescription: "Quick Note")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item

        registerHotKey()
    }

    // MARK: - Panel

    @objc func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard let state else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 220),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: QuickNotePanel(quickNote: self).environmentObject(state))
            self.panel = panel
        }

        position()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Drop the panel just under the menu bar item, the way a real menu would fall.
    private func position() {
        guard let panel, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let frame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = frame.midX - size.width / 2
        if let screen = NSScreen.main {
            x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        }
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: frame.minY - 6))
    }

    /// Push the scratch buffer into the library as its own note and clear it.
    func promoteToNote() {
        guard let state, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "Quick Note"
        var note = state.library.create(titled: String(firstLine.prefix(48)), avoiding: Set(state.notes.map(\.title)))
        note.text = text
        state.library.write(note)
        state.notes.append(note)
        state.select(note.id)
        text = ""
        close()
        NSApp.windows.first { !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Global hotkey (⌥⌘N)

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.quickNote.toggle()
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4D4E4C41), id: 1) // 'MNLA'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(optionKey | cmdKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

private struct QuickNotePanel: View {
    let quickNote: QuickNote
    @EnvironmentObject var state: AppState
    @State private var text = ""

    var body: some View {
        let palette = state.palette

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Quick Note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Button {
                    quickNote.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().overlay(palette.line)

            TextEditor(text: $text)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type a quick note…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.inkSoft)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

            Divider().overlay(palette.line)

            HStack {
                Text("⌘⏎ to keep")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
                Spacer()
                Button("Save to Silica") { quickNote.promoteToNote() }
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 280, height: 220)
        .background(palette.background)
        .preferredColorScheme(state.resolvedAppearance == .light ? .light : .dark)
        .onAppear { text = quickNote.text }
        .onChange(of: text) { _, new in quickNote.text = new }
    }
}
