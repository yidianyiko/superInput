import Foundation

public enum BoardInputPaths {
    public static func baseDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("StartUpSpeechBar", isDirectory: true)
            .appendingPathComponent("board-input", isDirectory: true)
    }

    public static func eventsFileURL(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager)
            .appendingPathComponent("events.jsonl")
    }

    public static func rawSerialCaptureFileURL(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager)
            .appendingPathComponent("raw-serial-rx.bin")
    }
}
