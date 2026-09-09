import AppKit

struct LinkedApp: Codable, Equatable {
    let bundleID: String
    let name: String
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
