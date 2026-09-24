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
            // Borderless: no titlebar and no traffic lights, just a card that
            // hangs from the menu bar like a menu would. The card draws its own
            // corners and shadow.
            let panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: QuickNotePanel.width, height: QuickNotePanel.height),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.onEscape = { [weak self] in self?.close() }
            let hosting = NSHostingView(rootView: QuickNotePanel(quickNote: self).environmentObject(state))
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = .clear
            panel.contentView = hosting
            self.panel = panel
        }

        position()
        // A non-activating panel takes the keyboard without bringing the rest
        // of the app forward, so the editor window stays wherever it was.
        panel?.makeKeyAndOrderFront(nil)
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
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: frame.minY - 4))
    }

    /// Push the scratch buffer into the library as its own note and clear it.
    func promoteToNote() {
        guard let state, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "Quick Note"
        var note = state.library.create(
            titled: String(firstLine.prefix(48)),
            format: state.newNoteFormat,
            avoiding: Set(state.notes.map(\.title))
        )
        note.text = text
        if note.format == .richText { note.rich = NSAttributedString(string: text, attributes: [.font: state.editorFont]) }
        state.library.write(note)
        state.notes.append(note)
        state.select(note.id)
        text = ""
        close()
        AppDelegate.shared?.showEditor()
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

/// A borderless panel refuses key status by default, which would make it
/// impossible to type into. Escape closes it, as it would a menu.
private final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// The panel takes keys without making Silica the active app, so the Edit
    /// menu is not there to turn ⌘V into a paste. Do it here instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
              let responder = firstResponder else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()

        // Undo is not one of these: a text view has no `undo:` of its own, it
        // only keeps an undo manager, so asking it directly does nothing.
        if key == "z" {
            guard let manager = (responder as? NSTextView)?.undoManager ?? undoManager else { return false }
            if event.modifierFlags.contains(.shift) {
                guard manager.canRedo else { return false }
                manager.redo()
            } else {
                guard manager.canUndo else { return false }
                manager.undo()
            }
            return true
        }

        let selector: Selector? = switch key {
        case "v": #selector(NSText.paste(_:))
        case "c": #selector(NSText.copy(_:))
        case "x": #selector(NSText.cut(_:))
        case "a": #selector(NSText.selectAll(_:))
        default: nil
        }
        guard let selector else { return false }
        return NSApp.sendAction(selector, to: responder, from: self)
    }
}

private struct QuickNotePanel: View {
    static let width: CGFloat = 250
    static let height: CGFloat = 330

    let quickNote: QuickNote
    @EnvironmentObject var state: AppState
    @State private var text = ""

    var body: some View {
        let palette = state.palette

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Quick Note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.ink)
                Spacer()
                Button {
                    quickNote.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)

            Divider().overlay(palette.line)

            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundStyle(palette.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type a quick note…")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.inkSoft)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            // Off screen but still wired: ⌘⏎ files the note in the library.
            Button("Save to Silica") { quickNote.promoteToNote() }
                .keyboardShortcut(.return, modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .frame(width: Self.width, height: Self.height)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.pillBorder, lineWidth: 0.5)
        }
        .preferredColorScheme(state.resolvedAppearance == .light ? .light : .dark)
        .onAppear { text = quickNote.text }
        .onChange(of: text) { _, new in quickNote.text = new }
    }
}
