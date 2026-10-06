import Foundation

public struct Word: Codable, Sendable, Equatable {
    public var start, end: Double
    public var text: String
    public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text }
}

/// Groups words into sentences, splitting after `.`, `?` or `!`, so narration can interleave
/// with the frames it describes.
public func sentences(from words: [Word]) -> [Sentence] {
    var out: [Sentence] = [], cur: [Word] = []
    func flush() {
        let text = cur.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let first = cur.first, let last = cur.last {
            out.append(Sentence(start: (first.start * 100).rounded() / 100, end: (last.end * 100).rounded() / 100, text: text))
        }
        cur.removeAll()
    }
    for w in words {
        cur.append(w)
        if let c = w.text.trimmingCharacters(in: .whitespaces).last, ".?!".contains(c) { flush() }
    }
    flush()
    return out
}

/// The first sentence, without its final punctuation, cut to 60 characters at a word boundary.
/// No narration → "Recording HH:mm".
public func title(for sentences: [Sentence], createdAt: Date, calendar: Calendar = .current) -> String {
    guard var t = sentences.first?.text.trimmingCharacters(in: .whitespaces), !t.isEmpty else {
        let c = calendar.dateComponents([.hour, .minute], from: createdAt)
        return String(format: "Recording %02d:%02d", c.hour!, c.minute!)
    }
    while let last = t.last, ".?!".contains(last) { t.removeLast() }
    guard t.count > 60 else { return t }
    let cut = String(t.prefix(60))
    let atSpace = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
    return atSpace + "…"
}
