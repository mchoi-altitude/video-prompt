import Foundation

public enum JSON {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Write to a temp file beside `url`, then rename, so readers never see a half-written file.
public func writeAtomically(_ data: Data, to url: URL) throws {
    let tmp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    try data.write(to: tmp)
    do {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    } catch {
        try? FileManager.default.removeItem(at: tmp)
        throw error
    }
}

public func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try writeAtomically(JSON.encoder.encode(value), to: url)
}

public func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSON.decoder.decode(type, from: Data(contentsOf: url))
}
