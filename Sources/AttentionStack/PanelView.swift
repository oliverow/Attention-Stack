import SwiftUI

private let rowHeight: CGFloat = 28

struct PanelView: View {
    @ObservedObject var store: ItemStore
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

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
                // A List with only maxHeight collapses to zero height in
                // a MenuBarExtra window, so rows have a fixed height and
                // the List gets a definite frame (11 rows, then scrolls).
                List {
                    ForEach(store.items) { item in
                        RowView(item: item) {
                            store.remove(item)
                        } onCommit: { text in
                            store.update(item.id, text: text)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in store.move(from: from, to: to) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, rowHeight)
                .frame(height: min(CGFloat(store.items.count) * rowHeight, rowHeight * 11))
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
}

private struct RowView: View {
    let item: StackItem
    let onRemove: () -> Void
    let onCommit: (String) -> Void

    @State private var draft: String
    @State private var editing = false
    @FocusState private var focused: Bool

    init(item: StackItem, onRemove: @escaping () -> Void, onCommit: @escaping (String) -> Void) {
        self.item = item
        self.onRemove = onRemove
        self.onCommit = onCommit
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
            TimelineView(.periodic(from: .now, by: 30)) { context in
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
