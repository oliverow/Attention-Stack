import AppKit

/// A Claude Code session the stack follows on its own, from the events
/// Claude Code hooks report. Nothing about it is typed in by hand.
struct TrackedSession: Codable, Equatable {
    enum State: String, Codable {
        /// A turn is running.
        case working
        /// Waiting on a permission prompt or a question.
        case needsYou
        /// The turn is over and its result is there to read.
        case finished
    }

    /// The id Claude Code hooks report, not the Claude desktop app's own id.
    let id: String
    let cwd: String
    var state: State
    /// False from the moment the session wants you until you click its row
    /// or prompt it again.
    var seen: Bool
    var ended: Bool
    /// True while the row text is the stand-in made from the folder and the
    /// first prompt, so the desktop app's title may replace it.
    var autoTitle: Bool
    var updatedAt: Date

    var wantsYou: Bool { state == .needsYou || (state == .finished && !seen) }
}

/// One hook event as AttentionStackHook leaves it in the spool folder.
private struct SessionEvent: Decodable {
    let sessionID: String
    let name: String?
    let cwd: String?
    let notificationType: String?
    let prompt: String?
    let receivedAt: Double
    let hostBundleID: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name = "hook_event_name"
        case cwd
        case notificationType = "notification_type"
        case prompt
        case receivedAt = "received_at"
        case hostBundleID = "host_bundle_id"
    }
}

/// Notification types that mean the session is stuck until you answer.
/// `idle_prompt` is left out: it only repeats that a finished turn is
/// waiting for the next prompt, which `Stop` already reported.
private let needsYouNotifications: Set<String> = [
    "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
]

private let eventsDirectory = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("AttentionStack/events", isDirectory: true)

/// Turns the events in the spool folder into stack items. A session joins
/// the stack at its first prompt, follows its state from then on, and
/// leaves once it has ended and you have looked at it.
@MainActor
final class SessionTracker {
    private weak var store: ItemStore?
    private var watcher: DispatchSourceFileSystemObject?

    init(store: ItemStore) {
        self.store = store
        try? FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        // Events from while the app was not running are waiting already.
        drain()

        // The folder changes whenever the helper renames a new event into it.
        let fd = open(eventsDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        watcher.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
        watcher.setCancelHandler { close(fd) }
        watcher.resume()
        self.watcher = watcher
    }

    private func drain() {
        let fm = FileManager.default
        guard let store,
              let names = try? fm.contentsOfDirectory(atPath: eventsDirectory.path) else { return }
        // Dot names are the helper's files still being written.
        let files = names.filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }.sorted()
        guard !files.isEmpty else { return }

        var events: [SessionEvent] = []
        for name in files {
            let url = eventsDirectory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let event = try? JSONDecoder().decode(SessionEvent.self, from: data) {
                events.append(event)
            }
            // Unreadable ones go too, or every drain would trip over them.
            try? fm.removeItem(at: url)
        }
        store.modify { items in
            for event in events { apply(event, to: &items) }
        }
    }

    private func apply(_ event: SessionEvent, to items: inout [StackItem]) {
        let at = Date(timeIntervalSince1970: event.receivedAt)
        guard let index = items.firstIndex(where: { $0.session?.id == event.sessionID }),
              var session = items[index].session else {
            // Only a prompt adds a session. A session opened and closed
            // without one was never work, and an event for a session you
            // removed should not bring it back; a new prompt does.
            if event.name == "UserPromptSubmit" { items.insert(newItem(for: event, at: at), at: 0) }
            return
        }

        switch event.name {
        case "UserPromptSubmit":
            session.state = .working
            session.seen = true
            session.ended = false
        case "SessionStart":
            // Resumed: the same session is open again.
            session.ended = false
        case "PostToolUse":
            // A tool ran, so whatever permission was pending got answered.
            guard session.state == .needsYou else { return }
            session.state = .working
        case "Notification":
            guard let type = event.notificationType, needsYouNotifications.contains(type) else { return }
            session.state = .needsYou
            session.seen = false
        case "Stop":
            session.state = .finished
            session.seen = false
            if session.autoTitle { refreshDesktopTitle(of: &items[index]) }
        case "SessionEnd":
            session.ended = true
        default:
            return
        }
        session.updatedAt = at
        items[index].session = session
        // Ended and nothing left unread: done with it.
        if session.ended && !session.wantsYou { items.remove(at: index) }
    }

    private func newItem(for event: SessionEvent, at: Date) -> StackItem {
        let cwd = event.cwd ?? ""
        var item = StackItem(text: standInTitle(cwd: cwd, prompt: event.prompt))
        item.app = hostApp(event.hostBundleID)
        item.session = TrackedSession(
            id: event.sessionID, cwd: cwd, state: .working, seen: true,
            ended: false, autoTitle: true, updatedAt: at
        )
        refreshDesktopTitle(of: &item)
        return item
    }

    /// For a session in the Claude desktop app, links the desktop session so
    /// a click reopens it, and takes its title once the app has named it.
    /// Every session is looked up, not only ones whose host reads as Claude:
    /// what the desktop app passes on as the host is not documented.
    private func refreshDesktopTitle(of item: inout StackItem) {
        guard let id = item.session?.id,
              let desktop = desktopSession(mentioning: id) else { return }
        if item.app?.bundleID != claudeBundleID {
            item.app = LinkedApp(bundleID: claudeBundleID, name: "Claude")
        }
        item.app?.session = desktop
        let title = desktop.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { item.text = title }
    }
}

/// "folder: first line of the prompt", until something better comes along.
private func standInTitle(cwd: String, prompt: String?) -> String {
    let folder = cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent
    let line = prompt?
        .split(whereSeparator: \.isNewline).first
        .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    guard !line.isEmpty else { return folder }
    return "\(folder): \(line.count > 60 ? String(line.prefix(60)) + "…" : line)"
}

/// The app the session runs in, so a click brings it forward.
private func hostApp(_ bundleID: String?) -> LinkedApp? {
    guard let bundleID,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? url.deletingPathExtension().lastPathComponent
    return LinkedApp(bundleID: bundleID, name: name)
}

/// Sets up the user-level Claude Code hooks that feed `SessionTracker`.
enum ClaudeHooks {
    private static let events = ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionStart", "SessionEnd"]
    private static let helperName = "AttentionStackHook"

    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The helper inside this copy of the app, nil when running unbundled.
    private static var helperPath: String? {
        guard let path = Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent(helperName).path,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// Whether the hooks point at this copy of the app. Moving the app
    /// breaks the old path, which then reads as not installed.
    static var isInstalled: Bool {
        guard let helperPath, let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return false }
        return text.contains(helperPath) || text.contains(helperPath.replacingOccurrences(of: "/", with: "\\/"))
    }

    enum InstallError: LocalizedError {
        case noHelper, unreadableSettings

        var errorDescription: String? {
            switch self {
            case .noHelper: "The hook helper is missing; build the app with ./build.sh."
            case .unreadableSettings: "~/.claude/settings.json is not a JSON object, so it was left alone."
            }
        }
    }

    /// Adds one async command hook per event to ~/.claude/settings.json and
    /// leaves every other setting and hook as it was. Async, so a session
    /// never waits on the stack. Earlier Attention Stack hooks are replaced,
    /// so this also repairs them after the app moves.
    static func install() throws {
        guard let helperPath else { throw InstallError.noHelper }
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.unreadableSettings
            }
            settings = object
            // Rewriting the file drops its formatting, so keep the original.
            let backup = settingsURL.appendingPathExtension("attention-stack-backup")
            if !fm.fileExists(atPath: backup.path) { try data.write(to: backup) }
        }

        let command = "'" + helperPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            // Take out only our own hook; a group left empty goes with it.
            var groups: [[String: Any]] = (hooks[event] as? [[String: Any]] ?? []).compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { ($0["command"] as? String)?.contains(helperName) != true }
                if kept.isEmpty { return nil }
                var group = group
                group["hooks"] = kept
                return group
            }
            groups.append(["hooks": [["type": "command", "command": command, "async": true]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
