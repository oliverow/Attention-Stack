import Foundation

struct StackItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    /// At most one app, brought forward when the item is clicked.
    var app: LinkedApp?
    /// A page the item opens instead of an app, set for papers added by 🧻.
    var url: URL?

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
    }
}

/// An item that fails to decode drops on its own instead of taking the rest of
/// the saved stack with it, so a future field change costs at most the items
/// that changed shape.
private struct LenientItem: Decodable {
    let item: StackItem?

    init(from decoder: Decoder) throws {
        item = try? StackItem(from: decoder)
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

    func add(_ rawText: String, app: LinkedApp?, url: URL? = nil) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var item = StackItem(text: text)
        item.app = app
        item.url = url
        items.insert(item, at: 0)
        save()
    }

    func remove(_ item: StackItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = items.firstIndex(where: { $0.id == id }),
              items[index].text != trimmed else { return }
        items[index].text = trimmed
        save()
    }

    func setApp(_ id: UUID, app: LinkedApp?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].app = app
        save()
    }

    func move(_ id: UUID, to index: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }), index != from else { return }
        items.insert(items.remove(at: from), at: index)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        let decoded = try? JSONDecoder().decode([LenientItem].self, from: data)
        items = decoded?.compactMap { $0.item } ?? []
        // Anything dropped is data no save from this run will carry forward,
        // and this file is the only copy: move it aside before the first save
        // overwrites it.
        if items.count != decoded?.count {
            let backup = fileURL.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
