import Foundation

/// Читання хвоста великого текстового файлу без завантаження його цілком.
/// Сесійні логи агентів сягають кількох мегабайт, а потрібні лише останні події.
enum FileTail {
    /// Повертає рядки з кінця файлу, від найновішого до найстарішого.
    /// Перший (можливо обрізаний) рядок прочитаного блоку відкидається.
    static func lines(of url: URL, maxBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else { return [] }
        let offset = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        let truncated = offset > 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if truncated, !lines.isEmpty { lines.removeFirst() }
        return lines.reversed()
    }

    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
