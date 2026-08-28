import Foundation

/// Reads JSONL files incrementally: whole on the first pass, then only the bytes
/// appended since. Without this, every refresh would re-read hundreds of
/// megabytes of transcripts.
final class JSONLTailReader {

    /// Bytes already consumed, per file.
    private var offsets: [String: UInt64] = [:]

    /// Returns only the lines that appeared since the last read. A partial
    /// trailing line — a write still in flight — is left for the next pass.
    func newLines(at url: URL) -> [Data] {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var start = offsets[path] ?? 0
        if start > size { start = 0 } // truncated or rotated
        guard size > start else { return [] }

        do { try handle.seek(toOffset: start) } catch { return [] }
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return [] }

        guard let lastNewline = chunk.lastIndex(of: 0x0A) else {
            return [] // no complete line yet; try again next round
        }
        let complete = chunk[chunk.startIndex...lastNewline]
        offsets[path] = start + UInt64(complete.count)

        return complete.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
    }

    func reset() { offsets.removeAll() }
}

enum FileScan {
    /// Every .jsonl under `root`, filtered by modification date, oldest first.
    static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date?) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [(URL, Date)] = []
        for case let url as URL in e {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if let cutoff, modified < cutoff { continue }
            out.append((url, modified))
        }
        return out.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
