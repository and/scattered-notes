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

    private var cache: [UUID: (updatedAt: Date, vector: [Double]?)] = [:]
    private var running: Task<Void, Never>?

    /// Brings the vectors up to date with `notes`; does nothing when none changed
    func update(with notes: [Note]) {
        #if canImport(NaturalLanguage)
        let stale = notes.filter { cache[$0.id]?.updatedAt != $0.updatedAt }
        guard !stale.isEmpty || cache.count != notes.count else { return }
        let work = stale.map { (id: $0.id, updatedAt: $0.updatedAt, text: SuggestedIndex.text(of: $0)) }
        let live = Set(notes.map(\.id))
        let order = Dictionary(notes.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        running?.cancel()
        running = Task { [weak self] in
            let computed: [(id: UUID, updatedAt: Date, vector: [Double]?)]? = await Task.detached(priority: .utility) {
                guard let words = AppleWordVectors() else { return nil }
                return work.map { ($0.id, $0.updatedAt, SuggestedIndex.vector(for: $0.text, using: words)) }
            }.value
            guard let self, !Task.isCancelled else { return }
            guard let computed else {
                self.isAvailable = false
                return
            }
            for item in computed { self.cache[item.id] = (item.updatedAt, item.vector) }
            self.cache = self.cache.filter { live.contains($0.key) }
            var vectors: [UUID: [Double]] = [:]
            for (id, entry) in self.cache { if let vector = entry.vector { vectors[id] = vector } }
            self.index = SuggestedIndex(vectors: vectors, updated: order)
        }
        #else
        isAvailable = false
        #endif
    }
}
