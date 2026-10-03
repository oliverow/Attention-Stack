import AppKit

struct LinkedSession: Codable, Equatable {
    let id: String
    let title: String
}

struct LinkedApp: Codable, Equatable {
    let bundleID: String
    let name: String
    /// Only set when the linked app is Claude; identifies the Claude Code
    /// session that was on screen. Optional so items saved before this field
    /// existed still decode.
    var session: LinkedSession?

    /// The app name, plus the session title when one is attached.
    var displayName: String {
        session.map { "\(name) · \($0.title)" } ?? name
    }
}

let claudeBundleID = "com.anthropic.claudefordesktop"

/// Returns `app` unchanged unless it is Claude, in which case it attaches the
/// Claude Code session that was most recently focused (nil if none is found).
func attachingCurrentSession(_ app: LinkedApp) -> LinkedApp {
    guard app.bundleID == claudeBundleID else { return app }
    var app = app
    app.session = currentClaudeSession()
    return app
}

/// The Claude Code session with the largest `lastFocusedAt`.
private func currentClaudeSession() -> LinkedSession? {
    var best: (session: LinkedSession, focusedAt: Double)?
    for url in recentDesktopSessionFiles() {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["sessionId"] as? String,
              let focusedAt = json["lastFocusedAt"] as? Double else { continue }
        // A brand-new session has no title yet; it must still win over older ones.
        let title = json["title"] as? String ?? "Untitled session"
        if focusedAt > (best?.focusedAt ?? -.infinity) {
            best = (LinkedSession(id: id, title: title), focusedAt)
        }
    }
    return best?.session
}

/// The Claude desktop session whose `cliSessionId` is `cliSessionID`, the
/// id Claude Code hooks report; the desktop app keys its sessions by its own
/// `sessionId`. The title is empty until the desktop app has named the
/// session.
func desktopSession(cliSessionID: String) -> LinkedSession? {
    let needle = Data(cliSessionID.utf8)
    for url in recentDesktopSessionFiles() {
        // A cheap byte search first, so only the matching file is parsed.
        guard let data = try? Data(contentsOf: url),
              data.range(of: needle) != nil,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["cliSessionId"] as? String == cliSessionID,
              let id = json["sessionId"] as? String else { continue }
        return LinkedSession(id: id, title: json["title"] as? String ?? "")
    }
    return nil
}

/// The most recently written Claude desktop session files.
///
/// Each session file is ~540 KB and there are a couple hundred of them, so we
/// sort by modification date and keep only the newest few: the session we
/// want is one of the recently written files, and parsing all of them would
/// be needlessly slow.
private func recentDesktopSessionFiles() -> ArraySlice<URL> {
    let base = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)

    // Sessions live under <org>/<account>; the name filter below is what
    // keeps the walk correct, not the depth.
    let enumerator = FileManager.default.enumerator(
        at: base,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    )
    let files = (enumerator?.allObjects as? [URL] ?? []).filter {
        $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json"
    }
    return files.sorted {
        let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return lhs > rhs
    }.prefix(8)
}

/// The last app that was frontmost other than this one. Opening the panel
/// makes Attention Stack frontmost, so `NSWorkspace.frontmostApplication`
/// would only ever report ourselves by the time the user clicks Link.
@MainActor
final class FrontmostAppTracker: ObservableObject {
    @Published private(set) var app: LinkedApp?

    init() {
        record(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.record(running) }
        }
    }

    private func record(_ running: NSRunningApplication?) {
        guard let running,
              running.processIdentifier != NSRunningApplication.current.processIdentifier,
              let bundleID = running.bundleIdentifier,
              let name = running.localizedName else { return }
        app = LinkedApp(bundleID: bundleID, name: name)
    }
}

/// Bring the linked app forward, launching it if it is no longer running.
func bringToFront(_ app: LinkedApp) {
    // A remembered Claude session reopens via the same deep link the Claude
    // tray menu uses for "Continue last session"; it activates Claude and
    // switches to that session. (The claude.ai/code/<id> route only takes
    // cloud ids.) If that fails, fall through to at least bringing Claude
    // forward.
    if let session = app.session,
       let url = URL(string: "claude://code/continue?session=\(session.id)"),
       NSWorkspace.shared.open(url) {
        return
    }
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
        running.activate()
        return
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

/// Cached because this is read from `body`, which runs every frame during a drag,
/// and each miss is a LaunchServices lookup. Misses are cached as nil too.
@MainActor
private enum IconCache {
    static var byBundleID: [String: NSImage?] = [:]
}

@MainActor
func appIcon(_ app: LinkedApp) -> NSImage? {
    if let cached = IconCache.byBundleID[app.bundleID] { return cached }
    let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        .map { NSWorkspace.shared.icon(forFile: $0.path) }
    IconCache.byBundleID[app.bundleID] = icon
    return icon
}
