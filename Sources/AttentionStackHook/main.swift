import Foundation

// Claude Code runs this on the hooked events with the event as JSON on
// stdin (hooks are set up from the app's "Track Claude" button). It only
// drops a trimmed copy into the spool folder; Attention Stack picks it up
// from there, so nothing is lost while the app is not running.

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      event["session_id"] is String else { exit(0) }

// Keep only what the app reads. Tool events carry whole tool results and
// prompts can be long; none of that needs to sit on disk again.
var kept: [String: Any] = [:]
for key in ["session_id", "hook_event_name", "cwd", "notification_type"] {
    kept[key] = event[key]
}
// The docs show the prompt as `prompt_text`; older builds sent `prompt`.
if let prompt = (event["prompt_text"] ?? event["prompt"]) as? String {
    kept["prompt"] = String(prompt.prefix(200))
}
let now = Date().timeIntervalSince1970
kept["received_at"] = now
// macOS sets this for processes started from an app, and children inherit
// it, so it names the app the session runs in: Terminal, iTerm, Claude…
if let host = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] {
    kept["host_bundle_id"] = host
}

let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("AttentionStack/events", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
guard let data = try? JSONSerialization.data(withJSONObject: kept) else { exit(0) }

// Zero-padded milliseconds first, so name order is arrival order; the pid
// keeps two events from the same millisecond apart.
let name = String(format: "%015.0f-%d.json", now * 1000, getpid())
// Written under a dot name and renamed, so the app never reads half a file.
let tmp = dir.appendingPathComponent("." + name)
do {
    try data.write(to: tmp)
    try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(name))
} catch {
    try? FileManager.default.removeItem(at: tmp)
}
