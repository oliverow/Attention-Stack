import Foundation

struct Paper {
    let title: String
    let url: URL
}

private let inboxPath = "~/agent_brain/04-research/papers/_inbox.md"

/// One row of the inbox table, split on `|`. A row has ten columns, so the
/// pipes around them yield twelve fields with an empty one at each end.
private struct InboxRow {
    let added: String
    let title: String
    let arxiv: String
    let score: Int
    let status: String
    let link: URL?

    init?(line: String) {
        let cells = line.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard cells.count == 12 else { return nil }
        let parsed = parseMarkdownLink(cells[2])
        added = cells[1]
        title = parsed?.title ?? cells[2]
        arxiv = cells[3]
        score = Int(cells[6]) ?? 0
        status = cells[9]
        link = parsed?.url
    }

    /// arXiv gives a cleaner page than the HF mirror some rows link to.
    /// Rows without an id hold an em dash in that column.
    var url: URL? {
        if arxiv.first?.isNumber == true, let url = URL(string: "https://arxiv.org/abs/\(arxiv)") {
            return url
        }
        return link
    }
}

/// The paper `/next-paper` would pick: among rows still queued, the highest
/// score wins, and the one waiting longest breaks a tie.
func nextPaper() -> Paper? {
    let url = URL(fileURLWithPath: NSString(string: inboxPath).expandingTildeInPath)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let queued = text.components(separatedBy: .newlines)
        .compactMap(InboxRow.init(line:))
        .filter { $0.status == "queued" && $0.url != nil }
    // Rows tied on both score and date fall to whichever comes first in the
    // file, so the same click keeps opening the same paper.
    var best: InboxRow?
    for row in queued {
        guard let current = best else { best = row; continue }
        if row.score > current.score || (row.score == current.score && row.added < current.added) {
            best = row
        }
    }
    guard let best, let link = best.url else { return nil }
    return Paper(title: best.title, url: link)
}

private func parseMarkdownLink(_ cell: String) -> (title: String, url: URL)? {
    guard cell.hasPrefix("["), cell.hasSuffix(")"),
          let divider = cell.range(of: "](") else { return nil }
    let title = String(cell[cell.index(after: cell.startIndex)..<divider.lowerBound])
    let link = String(cell[divider.upperBound..<cell.index(before: cell.endIndex)])
    guard let url = URL(string: link) else { return nil }
    return (title, url)
}
