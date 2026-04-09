import Foundation
import Testing

@Suite("RepositoryPathCasing")
struct RepositoryPathCasingTests {
    @Test
    func trackedPathsDoNotCollideIgnoringCase() throws {
        let paths = try trackedRepositoryPaths()
        let grouped = Dictionary(grouping: paths, by: { $0.lowercased() })
        let collisions = grouped
            .values
            .filter { Set($0).count > 1 }
            .map { $0.sorted() }

        #expect(collisions.isEmpty, "Found case-colliding tracked paths: \(collisions)")
    }

    @Test
    func trackedTextFilesDoNotReferenceUppercaseDocsPrefix() throws {
        let forbiddenDocsPrefix = "Doc" + "s/"
        let offenders = try trackedRepositoryPaths()
            .filter { !$0.hasPrefix(".git/") }
            .filter { isLikelyTextFile(path: $0) }
            .filter { path in
                let url = repositoryRootURL.appending(path: path)
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    return false
                }

                return contents.contains(forbiddenDocsPrefix)
            }

        #expect(offenders.isEmpty, "Found tracked files that reference '\(forbiddenDocsPrefix)': \(offenders)")
    }
}

private let repositoryRootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func trackedRepositoryPaths() throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "ls-files"]
    process.currentDirectoryURL = repositoryRootURL

    let outputPipe = Pipe()
    process.standardOutput = outputPipe

    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: outputData, as: UTF8.self)

    return output
        .split(separator: "\n")
        .map(String.init)
}

private func isLikelyTextFile(path: String) -> Bool {
    let binaryExtensions = [
        "png", "jpg", "jpeg", "gif", "pdf", "zip",
        "xcworkspace", "xcodeproj", "app", "wav", "pcm"
    ]
    let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
    return !binaryExtensions.contains(fileExtension)
}
