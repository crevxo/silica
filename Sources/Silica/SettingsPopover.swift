import SwiftUI

/// Everything the app can be configured to do, in one popover. There is no
/// preferences window because there isn't enough to fill one.
struct SettingsPopover: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Text size") {
                HStack(spacing: 8) {
                    Slider(value: $state.fontSize, in: AppState.fontSizeRange, step: 1)
                        .frame(width: 130)
                    Text("\(Int(state.fontSize)) pt")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.inkSoft)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            row("Appearance") {
                Picker("", selection: $state.appearance) {
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                    Text("Auto").tag(Appearance.system)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            Toggle("Words written today", isOn: $state.showsDailyCount)
                .font(.system(size: 12))
            Toggle("Typewriter scrolling", isOn: $state.typewriterMode)
                .font(.system(size: 12))
            Toggle("Show tabs", isOn: $state.tabsVisible)
                .font(.system(size: 12))

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(.system(size: 12, weight: .medium))
                Text(state.library.folder.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.inkSoft)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Button("Change…") { state.chooseFolder() }
                    Button("Reveal") { state.revealFolder() }
                }
                .font(.system(size: 11))
                .padding(.top, 2)
            }

            Text("Silica \(UpdateConfiguration.version)")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            content()
        }
    }
}
