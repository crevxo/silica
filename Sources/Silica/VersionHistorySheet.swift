import SwiftUI

/// Every saved snapshot of the current note, newest first, with the text beside
/// the list so you can read a version before deciding to bring it back.
struct VersionHistorySheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Version?

    private var palette: Palette { state.palette }

    private var versions: [Version] {
        guard let note = state.active else { return [] }
        return state.versions.versions(for: note)
    }

    var body: some View {
        let list = versions

        VStack(spacing: 0) {
            HStack {
                Text(state.active?.title ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(list.count) saved versions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(palette.line)

            if list.isEmpty {
                VStack(spacing: 6) {
                    Text("No history yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.ink)
                    Text("Silica saves a version every few minutes while you write.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkSoft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(list) { version in
                                row(version, isSelected: selected == version)
                                    .onTapGesture { selected = version }
                            }
                        }
                    }
                    .frame(width: 190)

                    Divider().overlay(palette.line)

                    ScrollView {
                        Text(selected.map { state.versions.text(of: $0) } ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }

            Divider().overlay(palette.line)

            HStack {
                Text("Restoring keeps a copy of what's on screen now.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.inkSoft)
                Spacer()
                Button("Done") { dismiss() }
                Button("Restore") {
                    if let selected { state.restore(selected) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 620, height: 420)
        .background(palette.background)
        .preferredColorScheme(state.resolvedAppearance == .light ? .light : .dark)
        .onAppear { selected = list.first }
    }

    private func row(_ version: Version, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(version.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.ink)
            Text(version.date.formatted(.relative(presentation: .named)))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? palette.pill : .clear)
        .contentShape(Rectangle())
    }
}
