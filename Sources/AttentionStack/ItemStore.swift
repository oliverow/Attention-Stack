import Foundation

struct StackItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
    }
}

@MainActor
final class ItemStore: ObservableObject {
    @Published private(set) var items: [StackItem] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AttentionStack", isDirectory: true)
        self.fileURL = base.appendingPathComponent("items.json")
        load()
    }

    func add(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items.insert(StackItem(text: text), at: 0)
        save()
    }

    func remove(_ item: StackItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func pop() {
        guard !items.isEmpty else { return }
        items.removeFirst()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StackItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
