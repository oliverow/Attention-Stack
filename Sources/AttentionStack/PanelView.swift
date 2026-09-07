import SwiftUI

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
                // Refresh the relative times while the panel is open.
                // A plain VStack: a ScrollView gets zero height in a
                // MenuBarExtra window.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        ForEach(store.items) { item in
                            RowView(item: item, now: context.date) {
                                store.remove(item)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Pop") { store.pop() }
                    .disabled(store.items.isEmpty)
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
    let now: Date
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(relativeLabel(from: item.createdAt, to: now))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
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
