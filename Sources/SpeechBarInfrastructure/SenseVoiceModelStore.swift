import Combine
import Foundation

public struct SenseVoiceModelDescriptor: Sendable, Equatable, Codable {
    public let name: String
    public let displayName: String
    public let sizeLabel: String
    public let description: String
    public let downloadURL: URL
    public let extractedDirectoryName: String
    public let modelFilename: String
    public let tokensFilename: String
    public let defaultLanguage: String
    public let preferredExecutionProvider: String

    public init(
        name: String,
        displayName: String,
        sizeLabel: String,
        description: String,
        downloadURL: URL,
        extractedDirectoryName: String,
        modelFilename: String,
        tokensFilename: String,
        defaultLanguage: String,
        preferredExecutionProvider: String
    ) {
        self.name = name
        self.displayName = displayName
        self.sizeLabel = sizeLabel
        self.description = description
        self.downloadURL = downloadURL
        self.extractedDirectoryName = extractedDirectoryName
        self.modelFilename = modelFilename
        self.tokensFilename = tokensFilename
        self.defaultLanguage = defaultLanguage
        self.preferredExecutionProvider = preferredExecutionProvider
    }

    public static let smallInt8 = SenseVoiceModelDescriptor(
        name: "sensevoice-small-int8",
        displayName: "SenseVoice Small (Int8)",
        sizeLabel: "156 MB",
        description: "独立于 Whisper 的本地识别方案，面向低延迟语音输入；默认优先走 CPU，失败时再回退 Core ML。",
        downloadURL: URL(
            string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
        )!,
        extractedDirectoryName: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17",
        modelFilename: "model.int8.onnx",
        tokensFilename: "tokens.txt",
        defaultLanguage: "zh",
        preferredExecutionProvider: "cpu"
    )
}

@MainActor
public final class SenseVoiceModelStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var installedModelNames: [String] = []
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var statusMessage = "SenseVoice 本地运行时尚未安装。"
    @Published public private(set) var lastErrorMessage: String?
    @Published public var shouldShowInstallPrompt = false

    public let defaults: UserDefaults
    public let modelsDirectory: URL
    public let runtimeDirectory: URL
    public let defaultModel: SenseVoiceModelDescriptor

    private let fileManager: FileManager
    private let session: URLSession
    private var activeDownloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        modelsDirectory: URL? = nil,
        runtimeDirectory: URL? = nil,
        defaultModel: SenseVoiceModelDescriptor = .smallInt8
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.session = session
        self.defaultModel = defaultModel
        self.modelsDirectory = modelsDirectory ?? Self.defaultModelsDirectory(fileManager: fileManager)
        self.runtimeDirectory = runtimeDirectory ?? Self.defaultRuntimeDirectory(fileManager: fileManager)
        createDirectoriesIfNeeded()
        refreshInstalledModels()
        refreshStatusMessage()
    }

    public var isRuntimeInstalled: Bool {
        fileManager.fileExists(atPath: pythonExecutableURL.path) &&
            fileManager.fileExists(atPath: runtimeMarkerURL.path)
    }

    public var isDefaultModelInstalled: Bool {
        isModelInstalled(named: defaultModel.name)
    }

    public var isDefaultInstallationReady: Bool {
        isRuntimeInstalled && isDefaultModelInstalled
    }

    public func prepareForLaunch(showFirstInstallPrompt: Bool) {
        createDirectoriesIfNeeded()
        refreshInstalledModels()
        refreshStatusMessage()

        if isDefaultInstallationReady {
            shouldShowInstallPrompt = false
            return
        }

        shouldShowInstallPrompt = showFirstInstallPrompt
    }

    public func refreshInstalledModels() {
        createDirectoriesIfNeeded()

        let directoryURLs = (try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        installedModelNames = directoryURLs
            .filter { isValidModelDirectory($0) }
            .map(\.lastPathComponent)
            .sorted()
    }

    public func isModelInstalled(named name: String) -> Bool {
        isValidModelDirectory(modelDirectory(forModelNamed: name))
    }

    public func modelDirectory(forModelNamed name: String) -> URL {
        modelsDirectory.appendingPathComponent(name, isDirectory: true)
    }

    public func resolvedModelDirectory(preferredModelName: String?) -> URL? {
        let normalizedPreferred = preferredModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedPreferred, !normalizedPreferred.isEmpty {
            let preferredURL = modelDirectory(forModelNamed: normalizedPreferred)
            if isValidModelDirectory(preferredURL) {
                return preferredURL
            }
        }

        let defaultURL = modelDirectory(forModelNamed: defaultModel.name)
        if isValidModelDirectory(defaultURL) {
            return defaultURL
        }

        guard let firstInstalledName = installedModelNames.first else {
            return nil
        }
        return modelDirectory(forModelNamed: firstInstalledName)
    }

    public func resolvedPythonExecutableURL() -> URL? {
        isRuntimeInstalled ? pythonExecutableURL : nil
    }

    public func resolvedOfflineExecutableURL() -> URL? {
        isRuntimeInstalled ? offlineExecutableURL : nil
    }

    public func installDefaultModel() async -> Bool {
        guard !isDownloading else { return false }

        if isDefaultInstallationReady {
            statusMessage = "SenseVoice 已安装完成，可以直接开始使用。"
            shouldShowInstallPrompt = false
            lastErrorMessage = nil
            return true
        }

        createDirectoriesIfNeeded()
        isDownloading = true
        downloadProgress = 0
        lastErrorMessage = nil

        do {
            statusMessage = "正在准备 SenseVoice 本地运行时..."
            downloadProgress = 0.08
            try await bootstrapRuntimeIfNeeded()

            if !isDefaultModelInstalled {
                statusMessage = "正在检查本机已有 SenseVoice 模型..."
                downloadProgress = 0.18
                let importedLocalSeed = try await importLocalSeedModelIfAvailable()
                if !importedLocalSeed {
                    statusMessage = "正在下载 SenseVoice Small 模型..."
                    try await downloadAndInstallDefaultModelArchive()
                }
            }

            refreshInstalledModels()

            guard isDefaultInstallationReady else {
                throw SenseVoiceInstallationError.incompleteInstall
            }

            downloadProgress = 1
            statusMessage = "SenseVoice 已安装完成，可以直接开始使用。"
            shouldShowInstallPrompt = false
            lastErrorMessage = nil
            cleanupDownloadTracking()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = "SenseVoice 安装失败。"
            cleanupDownloadTracking()
            return false
        }
    }

    public func dismissInstallPrompt() {
        shouldShowInstallPrompt = false
    }

    public func modelAssetURLs(forModelNamed name: String) -> (model: URL, tokens: URL)? {
        let directory = modelDirectory(forModelNamed: name)
        guard isValidModelDirectory(directory) else {
            return nil
        }

        let modelURL = preferredModelFileURL(in: directory)
        let tokensURL = directory.appendingPathComponent(defaultModel.tokensFilename)
        guard let modelURL, fileManager.fileExists(atPath: tokensURL.path) else {
            return nil
        }
        return (modelURL, tokensURL)
    }

    private func bootstrapRuntimeIfNeeded() async throws {
        guard !isRuntimeInstalled else { return }

        try? fileManager.removeItem(at: runtimeMarkerURL)
        try createDirectoryIfNeeded(runtimeDirectory)

        try await Self.runProcessAsync(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-m", "venv", runtimeDirectory.path]
        )
        downloadProgress = 0.12

        try await Self.runProcessAsync(
            executableURL: pythonExecutableURL,
            arguments: ["-m", "pip", "install", "--upgrade", "pip"]
        )
        downloadProgress = 0.16

        try await Self.runProcessAsync(
            executableURL: pythonExecutableURL,
            arguments: [
                "-m", "pip", "install",
                "sherpa-onnx==1.12.35",
                "sherpa-onnx-bin==1.12.35"
            ]
        )

        try "ready".write(to: runtimeMarkerURL, atomically: true, encoding: .utf8)
    }

    private func downloadAndInstallDefaultModelArchive() async throws {
        let archiveURL = try await downloadArchive(from: defaultModel.downloadURL)
        defer { try? fileManager.removeItem(at: archiveURL) }

        let extractionParentURL = modelsDirectory
        let extractedURL = extractionParentURL.appendingPathComponent(
            defaultModel.extractedDirectoryName,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: extractedURL.path) {
            try fileManager.removeItem(at: extractedURL)
        }

        try await Self.runProcessAsync(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xjf", archiveURL.path, "-C", extractionParentURL.path]
        )
        downloadProgress = 0.9

        guard preferredModelFileURL(in: extractedURL) != nil else {
            throw SenseVoiceInstallationError.missingExtractedModel
        }

        let destinationURL = modelDirectory(forModelNamed: defaultModel.name)
        if extractedURL != destinationURL {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: extractedURL, to: destinationURL)
        }

        guard try await validateInstalledModel(at: destinationURL) else {
            try? fileManager.removeItem(at: destinationURL)
            throw SenseVoiceInstallationError.invalidInstalledModel
        }
    }

    private func importLocalSeedModelIfAvailable() async throws -> Bool {
        let seeds = localSeedCandidates()

        for seed in seeds {
            guard
                fileManager.fileExists(atPath: seed.modelURL.path),
                fileManager.fileExists(atPath: seed.tokensJSONURL.path)
            else {
                continue
            }

            let destinationURL = modelDirectory(forModelNamed: defaultModel.name)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try createDirectoryIfNeeded(destinationURL)

            let destinationModelURL = destinationURL.appendingPathComponent("model.onnx")
            let destinationTokensURL = destinationURL.appendingPathComponent(defaultModel.tokensFilename)

            try fileManager.copyItem(at: seed.modelURL, to: destinationModelURL)
            try convertTokensJSONToTokensTXT(
                from: seed.tokensJSONURL,
                to: destinationTokensURL
            )

            if try await validateInstalledModel(at: destinationURL) {
                statusMessage = "已导入本机现有 SenseVoice 模型。"
                downloadProgress = 0.92
                return true
            }

            try? fileManager.removeItem(at: destinationURL)
        }

        return false
    }

    private func downloadArchive(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let task = session.downloadTask(with: url) { tempURL, response, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard
                        let httpResponse = response as? HTTPURLResponse,
                        (200..<300).contains(httpResponse.statusCode),
                        let tempURL
                    else {
                        continuation.resume(throwing: SenseVoiceInstallationError.invalidDownloadResponse)
                        return
                    }

                    let destinationURL = self.fileManager.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("tar.bz2")

                    do {
                        try self.createDirectoryIfNeeded(destinationURL.deletingLastPathComponent())
                        if self.fileManager.fileExists(atPath: destinationURL.path) {
                            try self.fileManager.removeItem(at: destinationURL)
                        }
                        try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                        continuation.resume(returning: destinationURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.activeDownloadTask = task
            self.progressObservation = task.progress.observe(
                \.fractionCompleted,
                options: [.initial, .new]
            ) { [weak self] progress, _ in
                Task { @MainActor in
                    let clamped = max(0, min(1, progress.fractionCompleted))
                    self?.downloadProgress = 0.18 + (clamped * 0.62)
                }
            }
            task.resume()
        }
    }

    private func refreshStatusMessage() {
        if isDefaultInstallationReady {
            statusMessage = "SenseVoice 已就绪。"
        } else if isRuntimeInstalled && isDefaultModelInstalled {
            statusMessage = "SenseVoice 模型与运行时已安装。"
        } else if isRuntimeInstalled {
            statusMessage = "SenseVoice 运行时已安装，等待模型下载。"
        } else {
            statusMessage = "SenseVoice 本地运行时尚未安装。"
        }
    }

    private func preferredModelFileURL(in directory: URL) -> URL? {
        let preferredURL = directory.appendingPathComponent(defaultModel.modelFilename)
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let fileURLs = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return fileURLs
            .filter {
                let filename = $0.lastPathComponent.lowercased()
                return filename.hasSuffix(".onnx") && filename.contains("model")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private func isValidModelDirectory(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let tokensURL = url.appendingPathComponent(defaultModel.tokensFilename)
        guard fileManager.fileExists(atPath: tokensURL.path) else {
            return false
        }

        let readyMarkerURL = url.appendingPathComponent(".ready")
        guard fileManager.fileExists(atPath: readyMarkerURL.path) else {
            return false
        }

        return preferredModelFileURL(in: url) != nil
    }

    private func cleanupDownloadTracking() {
        progressObservation?.invalidate()
        progressObservation = nil
        activeDownloadTask = nil
        isDownloading = false
    }

    private func createDirectoriesIfNeeded() {
        try? createDirectoryIfNeeded(modelsDirectory)
        try? createDirectoryIfNeeded(runtimeDirectory.deletingLastPathComponent())
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private func convertTokensJSONToTokensTXT(from jsonURL: URL, to txtURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        let tokens = try JSONDecoder().decode([String].self, from: data)
        let lines = tokens.enumerated().map { index, token in
            "\(token) \(index)"
        }
        try lines.joined(separator: "\n").write(to: txtURL, atomically: true, encoding: .utf8)
    }

    private func validateInstalledModel(at directory: URL) async throws -> Bool {
        guard let modelURL = preferredModelFileURL(in: directory) else {
            return false
        }

        let tokensURL = directory.appendingPathComponent(defaultModel.tokensFilename)
        guard fileManager.fileExists(atPath: tokensURL.path) else {
            return false
        }
        guard isRuntimeInstalled else {
            return false
        }
        guard fileManager.fileExists(atPath: offlineExecutableURL.path) else {
            return false
        }

        let wavURL = fileManager.temporaryDirectory
            .appendingPathComponent("sensevoice-validate-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? fileManager.removeItem(at: wavURL) }

        try PCM16WAVFileWriter.writeMonoWAV(
            pcm16Data: Data(repeating: 0, count: 16_000),
            sampleRate: 16_000,
            to: wavURL
        )

        do {
            try await Self.runProcessAsync(
                executableURL: offlineExecutableURL,
                arguments: [
                    "--sense-voice-model=\(modelURL.path)",
                    "--tokens=\(tokensURL.path)",
                    "--sense-voice-language=\(defaultModel.defaultLanguage)",
                    "--provider=cpu",
                    "--num-threads=2",
                    wavURL.path
                ]
            )
            try "ready".write(
                to: directory.appendingPathComponent(".ready"),
                atomically: true,
                encoding: .utf8
            )
            return true
        } catch {
            try? fileManager.removeItem(at: directory.appendingPathComponent(".ready"))
            return false
        }
    }

    private func localSeedCandidates() -> [LocalSeedModelCandidate] {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        return [
            LocalSeedModelCandidate(
                modelURL: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("Shandianshuo", isDirectory: true)
                    .appendingPathComponent("models", isDirectory: true)
                    .appendingPathComponent("sensevoice-small", isDirectory: true)
                    .appendingPathComponent("model.onnx"),
                tokensJSONURL: homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("Shandianshuo", isDirectory: true)
                    .appendingPathComponent("models", isDirectory: true)
                    .appendingPathComponent("sensevoice-small", isDirectory: true)
                    .appendingPathComponent("tokens.json")
            )
        ]
    }

    nonisolated private static func runProcessAsync(executableURL: URL, arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            try runProcess(executableURL: executableURL, arguments: arguments)
        }.value
    }

    nonisolated private static func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let combined = String(data: errorData + outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SenseVoiceInstallationError.processFailure(
                executableURL.lastPathComponent,
                combined ?? "unknown error"
            )
        }
    }

    private var pythonExecutableURL: URL {
        runtimeDirectory.appendingPathComponent("bin/python3")
    }

    private var runtimeMarkerURL: URL {
        runtimeDirectory.appendingPathComponent(".runtime-ready")
    }

    private var offlineExecutableURL: URL {
        runtimeDirectory.appendingPathComponent("bin/sherpa-onnx-offline")
    }

    private static func defaultModelsDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("SlashVibe", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("SenseVoice", isDirectory: true)
    }

    private static func defaultRuntimeDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("SlashVibe", isDirectory: true)
            .appendingPathComponent("Runtimes", isDirectory: true)
            .appendingPathComponent("SenseVoice", isDirectory: true)
            .appendingPathComponent("venv", isDirectory: true)
    }
}

private enum SenseVoiceInstallationError: LocalizedError {
    case invalidDownloadResponse
    case missingExtractedModel
    case incompleteInstall
    case invalidInstalledModel
    case processFailure(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidDownloadResponse:
            return "SenseVoice 下载服务返回了无效响应。"
        case .missingExtractedModel:
            return "SenseVoice 模型解压后缺少必要文件。"
        case .incompleteInstall:
            return "SenseVoice 安装未完成。"
        case .invalidInstalledModel:
            return "SenseVoice 模型文件存在，但无法被运行时加载。"
        case .processFailure(let command, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "\(command) 执行失败。"
            }
            return "\(command) 执行失败：\(trimmed)"
        }
    }
}

private struct LocalSeedModelCandidate {
    let modelURL: URL
    let tokensJSONURL: URL
}
