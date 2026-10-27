import SwiftUI

/// Spotlight style search over every note. Arrow keys move, Return opens, Esc closes.
struct SearchPaletteView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    /// Called with the note and the search words that found it
    let onOpen: (Note, [String]) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var fieldFocused: Bool

    private var results: [SearchResult] {
        NoteSearch.search(query, in: storageManager.notes)
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                TextField("Search all notes, or #tag", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($fieldFocused)
                    .onSubmit { openSelected(in: results) }
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                hint("Type to search titles, text, tags and projects.")
            } else if results.isEmpty {
                hint("No notes match “\(query)”.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { result in
                                SearchResultRow(result: result, terms: NoteSearch.terms(in: query), isSelected: result.id == selectedID)
                                    .id(result.id)
                                    .onTapGesture { onOpen(result.note, NoteSearch.terms(in: query)) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(width: 620, height: 420)
        .background(.regularMaterial)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selectedID = results.first?.id }
        .onKeyPress(.downArrow) { move(1, in: results); return .handled }
        .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(_ step: Int, in results: [SearchResult]) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (step > 0 ? -1 : 0)
        selectedID = results[min(max(current + step, 0), results.count - 1)].id
    }

    private func openSelected(in results: [SearchResult]) {
        if let result = results.first(where: { $0.id == selectedID }) ?? results.first {
            onOpen(result.note, NoteSearch.terms(in: query))
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let terms: [String]
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.note.categoryType.iconName)
                .frame(width: 18)
                .foregroundColor(isSelected ? .white : .wcagSecondaryText)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(result.note.displayTitle, weight: .semibold))
                    .font(.system(size: 14))
                    .lineLimit(1)
                if let snippet = result.snippet {
                    Text(highlighted(snippet, weight: .semibold))
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white.opacity(0.92) : .wcagSecondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.note.destinationDisplay)
                    .font(.caption.weight(.medium))
                Text(result.note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .white.opacity(0.92) : .wcagSecondaryText)
        }
        .foregroundColor(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
    }

    /// Bolds every occurrence of a search term.
    private func highlighted(_ text: String, weight: Font.Weight) -> AttributedString {
        var attributed = AttributedString(text)
        for term in terms where !term.hasPrefix("#") {
            var from = attributed.startIndex
            while from < attributed.endIndex,
                  let range = attributed[from...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].font = .system(size: 14, weight: weight)
                attributed[range].backgroundColor = isSelected ? Color.white.opacity(0.28) : Color.yellow.opacity(0.3)
                from = range.upperBound
            }
        }
        return attributed
    }
}
