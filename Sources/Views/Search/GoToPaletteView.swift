import SwiftUI

/// Jump to a project, person or tag by typing part of its name. Arrow keys move, Return goes there, Esc closes.
struct GoToPaletteView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    let onGo: (SidebarSelection) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selected: SidebarSelection?
    @FocusState private var fieldFocused: Bool

    private var results: [GoToTarget] {
        GoToTargets.matching(query, in: GoToTargets.all(projects: storageManager.projects, notes: storageManager.notes))
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                TextField("Go to a project, @person or #tag", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($fieldFocused)
                    .accessibilityIdentifier("goToField")
                    .onSubmit { go(in: results) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if results.isEmpty {
                Text("Nothing is called “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { target in
                                GoToRow(target: target, isSelected: target.selection == selected)
                                    .id(target.selection)
                                    .onTapGesture { onGo(target.selection) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selected) { _, selection in
                        if let selection { proxy.scrollTo(selection) }
                    }
                }
            }
        }
        .frame(width: 460, height: 380)
        .background(.regularMaterial)
        .onAppear {
            fieldFocused = true
            selected = results.first?.selection
        }
        .onChange(of: query) { _, _ in selected = results.first?.selection }
        .onKeyPress(.downArrow) { move(1, in: results); return .handled }
        .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func move(_ step: Int, in results: [GoToTarget]) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.selection == selected } ?? (step > 0 ? -1 : 0)
        selected = results[min(max(current + step, 0), results.count - 1)].selection
    }

    private func go(in results: [GoToTarget]) {
        if let target = results.first(where: { $0.selection == selected }) ?? results.first {
            onGo(target.selection)
        }
    }
}

private struct GoToRow: View {
    let target: GoToTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: target.icon)
                .frame(width: 20)
                .foregroundColor(isSelected ? .white : .wcagSecondaryText)
            Text(target.title)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count = target.count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .wcagSecondaryText)
            }
        }
        .foregroundColor(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.wcagSelection : .clear)
        )
        .contentShape(Rectangle())
    }
}
