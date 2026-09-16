import SwiftUI

private let rowHeight: CGFloat = 28
// Fixed anchor for the timestamp timer: `.now` would restart the schedule
// on every body pass, and body runs every frame during a drag.
private let launchDate = Date()

struct PanelView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var frontmost: FrontmostAppTracker
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool
    // Row being dragged and how far the cursor has moved. The list is not
    // reordered until the drag ends; rows only shift visually meanwhile.
    @State private var dragID: UUID?
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("What to come back to…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                Button("Capture", action: capture)
                    .disabled(frontmost.app == nil)
                    .help(frontmost.app.map { "Add an item for \($0.name)" } ?? "No app to capture")
            }

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
                            frontmostName: frontmost.app?.name,
                            offset: rowOffset(index: index, id: item.id),
                            dragging: item.id == dragID,
                            shifting: dragID != nil,
                            onRemove: { store.remove(item) },
                            onCommit: { text in store.update(item.id, text: text) },
                            onToggleLink: {
                                if item.app != nil {
                                    store.setApp(item.id, app: nil)
                                } else if let app = frontmost.app {
                                    store.setApp(item.id, app: attachingCurrentSession(app))
                                }
                            },
                            onJump: {
                                if let url = item.url {
                                    NSWorkspace.shared.open(url)
                                } else if let app = item.app {
                                    bringToFront(app)
                                }
                            },
                            onDrag: { translation in
                                dragID = item.id
                                dragTranslation = translation
                            },
                            onDragEnd: {
                                // A cancelled drag can end late, after another row started.
                                guard dragID == item.id else { return }
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
                Button("🧻", action: openNextPaper)
                    .help("Open the next paper from the reading list")
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
            // A drag interrupted by the panel closing never gets onEnded.
            dragID = nil
            dragTranslation = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                fieldFocused = true
            }
        }
    }

    private func submit() {
        store.add(draft, app: frontmost.app.map(attachingCurrentSession))
        draft = ""
        fieldFocused = true
    }

    /// Adds an item named after the front app. For Claude, the item takes
    /// the title of the Claude Code session on screen instead, which is
    /// already a short summary of what that session is about.
    private func capture() {
        guard let app = frontmost.app.map(attachingCurrentSession) else { return }
        store.add(app.session?.title ?? app.name, app: app)
    }

    /// Opens the paper the reading list has at the top of its queue and
    /// stacks it, so it is one click away again once the tab is buried.
    private func openNextPaper() {
        guard let paper = nextPaper() else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(paper.url)
        store.add(paper.title, app: nil, url: paper.url)
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
        if id == dragID {
            // Keep the dragged row inside the list.
            return min(max(dragTranslation, CGFloat(-from) * rowHeight),
                       CGFloat(store.items.count - 1 - from) * rowHeight)
        }
        if from < to, index > from, index <= to { return -rowHeight }
        if from > to, index >= to, index < from { return rowHeight }
        return 0
    }
}

private struct RowView: View {
    let item: StackItem
    /// Name of the app the link button would attach, nil if there is none.
    let frontmostName: String?
    let offset: CGFloat
    let dragging: Bool
    let shifting: Bool
    let onRemove: () -> Void
    let onCommit: (String) -> Void
    let onToggleLink: () -> Void
    let onJump: () -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    @State private var draft: String
    @State private var editing = false
    // A reorder drag can end inside the tap gesture's slop, which would
    // jump to the app on top of reordering. Swallow that one tap.
    @State private var justDragged = false
    @FocusState private var focused: Bool

    init(item: StackItem, frontmostName: String?, offset: CGFloat, dragging: Bool, shifting: Bool,
         onRemove: @escaping () -> Void, onCommit: @escaping (String) -> Void,
         onToggleLink: @escaping () -> Void, onJump: @escaping () -> Void,
         onDrag: @escaping (CGFloat) -> Void, onDragEnd: @escaping () -> Void) {
        self.item = item
        self.frontmostName = frontmostName
        self.offset = offset
        self.dragging = dragging
        self.shifting = shifting
        self.onRemove = onRemove
        self.onCommit = onCommit
        self.onToggleLink = onToggleLink
        self.onJump = onJump
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
                    .help(helpText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        draft = item.text
                        editing = true
                        focused = true
                    }
                    .onTapGesture {
                        guard !justDragged else { return }
                        if item.url != nil || item.app != nil { onJump() }
                    }
            }
            linkButton
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
                .onChanged { value in
                    justDragged = true
                    onDrag(value.translation.height)
                }
                .onEnded { _ in
                    onDragEnd()
                    // Outlive the tap that may follow the release, but clear
                    // in time for the next real click.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        justDragged = false
                    }
                },
            including: editing ? .subviews : .all
        )
        // Commit when the field loses focus, not only on Return.
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private var helpText: String {
        if item.url != nil { return "\(item.text) — click to open the paper" }
        if let app = item.app { return "\(item.text) — click to open \(app.displayName)" }
        return item.text
    }

    /// Shows the linked app's icon; a plain link glyph when nothing is linked.
    private var linkButton: some View {
        Button(action: onToggleLink) {
            if let icon = item.app.flatMap(appIcon) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                // Still marked linked when the app is gone from disk.
                Image(systemName: item.app == nil ? "link" : "link.circle.fill")
                    .font(.caption)
                    .foregroundStyle(item.app == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
        }
        .buttonStyle(.borderless)
        // A paper row opens its page, so an app linked there would do nothing.
        .disabled(item.url != nil || (item.app == nil && frontmostName == nil))
        .help(item.app.map { "Unlink \($0.displayName)" } ?? frontmostName.map { "Link \($0)" } ?? "No app to link")
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
