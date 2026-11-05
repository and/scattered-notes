import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage

/// Apple's built-in English word vectors, which work offline. Nil when the model is not on the device.
struct AppleWordVectors: WordVectors {
    private let embedding: NLEmbedding

    init?() {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        self.embedding = embedding
    }

    func vector(for word: String) -> [Double]? { embedding.vector(for: word) }
}
#endif

/// Keeps a meaning vector for every note, working them out in the background, and answers "which notes are close
/// in meaning". A vector is reused until its note changes. Only used when the person turns suggestions on.
@MainActor
final class SuggestionEngine: ObservableObject {
    static let shared = SuggestionEngine()

    /// Bumped each time new suggestions are ready, so a view that reads `index` redraws
    @Published private(set) var index = SuggestedIndex(vectors: [:])
    /// False when this device has no word model, so the feature has nothing to offer
    private(set) var isAvailable = true

    private var signature = ""
    private var running: Task<Void, Never>?

    /// Brings the vectors up to date with `notes`; does nothing when no note changed. All vectors are worked out
    /// again when one note changes, because how much a word says depends on all the notes.
    func update(with notes: [Note]) {
        #if canImport(NaturalLanguage)
        let newest = notes.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let now = "\(notes.count)-\(newest)"
        guard now != signature else { return }
        signature = now
        let work = notes.map { (id: $0.id, title: $0.displayTitle, body: SuggestedIndex.body(of: $0), marks: SuggestedIndex.marks(of: $0),
                                project: $0.categoryType == .project ? $0.targetName?.lowercased() : nil, updated: $0.updatedAt) }
        running?.cancel()
        running = Task { [weak self] in
            let built: SuggestedIndex? = await Task.detached(priority: .utility) {
                guard let words = AppleWordVectors() else { return nil }
                var documentFrequency: [String: Int] = [:]
                for note in work {
                    for word in Set(SuggestedIndex.meaningfulWords(in: note.title + "\n" + note.body)) { documentFrequency[word, default: 0] += 1 }
                }
                let weight = { SuggestedIndex.weight(of: $0, documentFrequency: documentFrequency, count: work.count) }
                var sums: [UUID: [Double]] = [:]
                var marks: [UUID: Set<String>] = [:]
                var projects: [UUID: String] = [:]
                var updated: [UUID: Date] = [:]
                for note in work {
                    if Task.isCancelled { return nil }
                    if let total = SuggestedIndex.sum(title: note.title, body: note.body, using: words, weight: weight) { sums[note.id] = total }
                    marks[note.id] = note.marks
                    if let project = note.project { projects[note.id] = project }
                    updated[note.id] = note.updated
                }
                return SuggestedIndex(sums: sums, marks: marks, projects: projects, updated: updated)
            }.value
            guard let self, !Task.isCancelled else { return }
            if let built { self.index = built } else if AppleWordVectors() == nil { self.isAvailable = false }
        }
        #else
        isAvailable = false
        #endif
    }
}
