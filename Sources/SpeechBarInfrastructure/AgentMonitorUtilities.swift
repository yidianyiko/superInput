import Foundation
import SpeechBarDomain

struct IncrementalTextFileReader: Sendable {
    var offset: UInt64 = 0
    var partialUTF8 = ""

    mutating func readNewLines(from url: URL, fileManager: FileManager = .default) throws -> [String] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize >= offset else {
            offset = 0
            partialUTF8 = ""
            return try readNewLines(from: url, fileManager: fileManager)
        }

        guard fileSize > offset else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        offset = fileSize

        let chunk = partialUTF8 + String(decoding: data, as: UTF8.self)
        var lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if chunk.hasSuffix("\n") {
            partialUTF8 = ""
        } else {
            partialUTF8 = lines.popLast() ?? ""
        }

        return lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum UTF8SafeTruncator {
    static func truncated(_ string: String, maxByteCount: Int) -> String {
        guard maxByteCount > 0 else { return "" }
        let utf8 = Array(string.utf8)
        guard utf8.count > maxByteCount else { return string }

        var upperBound = maxByteCount
        while upperBound > 0 && (utf8[upperBound] & 0b1100_0000) == 0b1000_0000 {
            upperBound -= 1
        }
        return String(decoding: utf8.prefix(upperBound), as: UTF8.self)
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { byte in
            var value = UInt32(byte)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = 0xEDB88320 ^ (value >> 1)
                } else {
                    value >>= 1
                }
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = Self.table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

struct JSONLinesWriter: @unchecked Sendable {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func append<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var payload = try encoder.encode(value)
        payload.append(0x0A)

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: payload)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
    }
}

enum AgentMonitorClock {
    static func now() -> Date {
        Date()
    }
}
