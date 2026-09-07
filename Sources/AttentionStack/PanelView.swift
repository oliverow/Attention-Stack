import SwiftUI

private let rowHeight: CGFloat = 28
private let launchDate = Date()

struct PanelView: View {
    @ObservedObject var store: ItemStore
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool
    // Row being dragged and how far the cursor has moved. The list is not
    // reordered until the drag ends; rows only shift visually meanwhile.
    @State private var dragID: UUID?
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What to come back to…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(submit)

            Divider()

            if store.items.isEmpty {
                Text("Nothing waiting")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                // A plain VStack: List and ScrollView get zero height in a
                // MenuBarExtra window, and List's drag-to-reorder never
                // starts there, so rows reorder with their own drag gesture.
                VStack(spacing: 0) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        RowView(
                            item: item,
                            offset: rowOffset(index: index, id: item.id),
                            dragging: item.id == dragID,
                            shifting: dragID != nil,
                            onRemove: { store.remove(item) },
                            onCommit: { text in store.update(item.id, text: text) },
                            onDrag: { translation in
                                dragID = item.id
                                dragTranslation = translation
                            },
                            onDragEnd: {
                                if let target = dragTarget() { store.move(item.id, to: target) }
                                dragID = nil
                                dragTranslation = 0
                            }
                        )
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320)
        // MenuBarExtra never re-fires onAppear, so focus the field each
        // time the panel becomes visible. The short delay lets the window
        // finish becoming key first, or the focus request is dropped.
        // Assumes the panel is the only window in this app.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window.occlusionState.contains(.visible) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                fieldFocused = true
            }
        }
    }

    private func submit() {
        store.add(draft)
        draft = ""
        fieldFocused = true
    }

    /// Index the dragged row would land on if released now.
    private func dragTarget() -> Int? {
        guard let dragID, let from = store.items.firstIndex(where: { $0.id == dragID }) else { return nil }
        let steps = Int((dragTranslation / rowHeight).rounded())
        return min(max(from + steps, 0), store.items.count - 1)
    }

    /// The dragged row follows the cursor; rows between its old and new
    /// slot move one row height out of the way.
    private func rowOffset(index: Int, id: UUID) -> CGFloat {
        guard let dragID, let to = dragTarget(),
              let from = store.items.firstIndex(where: { $0.id == dragID }) else { return 0 }
        if id == dragID { return dragTranslation }
        if from < to, index > from, index <= to { return -rowHeight }
        if from > to, index >= to, index < from { return rowHeight }
        return 0
    }
}

private struct RowView: View {
    let item: StackItem
    let offset: CGFloat
    let dragging: Bool
    let shifting: Bool
    let onRemove: () -> Void
    let onCommit: (String) -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    @State private var draft: String
    @State private var editing = false
    @FocusState private var focused: Bool

    init(item: StackItem, offset: CGFloat, dragging: Bool, shifting: Bool,
         onRemove: @escaping () -> Void, onCommit: @escaping (String) -> Void,
         onDrag: @escaping (CGFloat) -> Void, onDragEnd: @escaping () -> Void) {
        self.item = item
        self.offset = offset
        self.dragging = dragging
        self.shifting = shifting
        self.onRemove = onRemove
        self.onCommit = onCommit
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        _draft = State(initialValue: item.text)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        draft = item.text
                        editing = true
                        focused = true
                    }
            }
            // Refresh the relative times while the panel is open.
            TimelineView(.periodic(from: launchDate, by: 30)) { context in
                Text(relativeLabel(from: item.createdAt, to: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .offset(y: offset)
        .zIndex(dragging ? 1 : 0)
        // Rows sliding out of the way animate; the dragged row and the
        // snap back after release do not, or they would lag the cursor.
        .animation(shifting && !dragging ? .easeOut(duration: 0.15) : nil, value: offset)
        // Disabled while editing so text selection in the field works.
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in onDrag(value.translation.height) }
                .onEnded { _ in onDragEnd() },
            including: editing ? .subviews : .all
        )
        // Commit when the field loses focus, not only on Return.
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft = item.text
        } else {
            onCommit(trimmed)
        }
        editing = false
    }
}

private func relativeLabel(from date: Date, to now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}
