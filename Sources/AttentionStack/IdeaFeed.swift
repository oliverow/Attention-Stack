import Foundation

struct Idea: Codable {
    let title: String
    let url: URL
}

/// Reddit's JSON API needs OAuth, but the Atom feeds are still open. A feed
/// caps at 25 entries and has no paging, and asking for more than one in a
/// row gets the rest throttled, so a refresh takes a single feed at random
/// and the draw widens across refreshes instead. Both are "top": the default
/// feed is whatever went up today, most of which nobody has voted on yet.
/// All-time top is left out — it is a frozen list of old joke posts.
private let feeds = [
    "https://www.reddit.com/r/SomebodyMakeThis/top/.rss?t=year",
    "https://www.reddit.com/r/SomebodyMakeThis/top/.rss?t=month",
]

/// Reddit starts answering 429 after a handful of quick requests, so the pool
/// is fetched once and reused. A cache hit also makes a repeat click instant.
private let cacheLifetime: TimeInterval = 6 * 60 * 60

private let cacheURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("AttentionStack/ideas.json")

private struct Cache: Codable {
    let fetchedAt: Date
    let ideas: [Idea]
}

/// A random idea from r/SomebodyMakeThis. Ideas already on the stack are
/// passed over, so a second click gives a second thing to look at.
func randomIdea(excluding used: Set<URL>) async -> Idea? {
    let cached = readCache()
    var pool: [Idea] = []
    if let cached, Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
        pool = cached.ideas
    }
    if pool.isEmpty {
        pool = await fetchIdeas()
        if pool.isEmpty {
            // Offline or throttled. An expired pool beats a beep here, since
            // none of these posts go out of date.
            pool = cached?.ideas ?? []
        } else {
            // A failed fetch is never cached, or one click made offline would
            // keep the button dead for the whole lifetime.
            write(pool)
        }
    }
    let unseen = pool.filter { !used.contains($0.url) }
    return (unseen.isEmpty ? pool : unseen).randomElement()
}

private func fetchIdeas() async -> [Idea] {
    guard let feed = feeds.randomElement(), let url = URL(string: feed),
          let (data, _) = try? await URLSession.shared.data(from: url),
          let xml = String(data: data, encoding: .utf8) else { return [] }
    // A throttled reply is an error page with no entries in it, so it comes
    // back empty here without a status check of its own.
    return parse(xml)
}

/// Atom entries, read by hand the way the paper inbox is. Each entry holds one
/// unescaped `link` and `title`, and the post body in `content` is escaped, so
/// searching for those two tags cannot pick up anything the poster wrote.
private func parse(_ xml: String) -> [Idea] {
    xml.components(separatedBy: "<entry>").dropFirst().compactMap { entry in
        guard let href = entry.value(after: "<link href=\"", upTo: "\""),
              let rawTitle = entry.value(after: "<title>", upTo: "</title>"),
              let url = URL(string: href) else { return nil }
        let title = clean(rawTitle)
        // Mod threads and "I made X" posts score well enough to reach the top
        // feeds, but one is housekeeping and the other is someone showing off
        // a finished thing rather than asking for it.
        let opening = title.lowercased()
        guard !title.hasSuffix("Thread"),
              !["i made", "i built", "i created"].contains(where: opening.hasPrefix)
        else { return nil }
        return Idea(title: title, url: url)
    }
}

/// Feed titles arrive XML-escaped, and this sub prefixes many of them with its
/// own initials.
private func clean(_ title: String) -> String {
    var text = title
    // `&amp;` last: undoing it first would turn `&amp;lt;` into a tag.
    for (entity, character) in [("&lt;", "<"), ("&gt;", ">"),
                                ("&quot;", "\""), ("&amp;", "&")] {
        text = text.replacingOccurrences(of: entity, with: character)
    }
    // The sub asks posters to mark requests, and they do it three ways.
    for marker in ["[SMT]", "SMT:", "SMT -"] where text.hasPrefix(marker) {
        text = String(text.dropFirst(marker.count))
    }
    return text.trimmingCharacters(in: .whitespaces)
}

private extension String {
    func value(after opening: String, upTo closing: String) -> String? {
        guard let start = range(of: opening),
              let end = range(of: closing, range: start.upperBound..<endIndex) else { return nil }
        return String(self[start.upperBound..<end.lowerBound])
    }
}

private func readCache() -> Cache? {
    guard let data = try? Data(contentsOf: cacheURL) else { return nil }
    return try? JSONDecoder().decode(Cache.self, from: data)
}

private func write(_ ideas: [Idea]) {
    let dir = cacheURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(Cache(fetchedAt: Date(), ideas: ideas)) else { return }
    try? data.write(to: cacheURL, options: .atomic)
}
