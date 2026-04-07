import Combine
import Foundation

public struct LocalWhisperModelDescriptor: Sendable, Equatable, Codable {
    public let name: String
    public let displayName: String
    public let sizeLabel: String
    public let description: String
    public let downloadURL: URL
    public let defaultLanguage: String

    public init(
        name: String,
        displayName: String,
        sizeLabel: String,
        description: String,
        downloadURL: URL,
        defaultLanguage: String
    ) {
        self.name = name
        self.displayName = displayName
        self.sizeLabel = sizeLabel
        self.description = description
        self.downloadURL = downloadURL
        self.defaultLanguage = defaultLanguage
    }

    public var filename: String {
        "\(name).bin"
    }

    public static let ggmlLargeV3TurboQ50 = LocalWhisperModelDescriptor(
        name: "ggml-large-v3-turbo-q5_0",
        displayName: "Large v3 Turbo (Quantized)",
        sizeLabel: "547 MB",
        description: "更适合中文语音输入的本地默认模型，体积和速度都更适合首次安装即用。",
        downloadURL: URL(
            string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
        )!,
        defaultLanguage: "zh"
    )
}

@MainActor
public final class LocalWhisperModelStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var installedModelNames: [String] = []
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var statusMessage = "本地 Whisper 模型尚未安装。"
    @Published public private(set) var lastErrorMessage: String?
    @Published public var shouldShowInstallPrompt = false

    public let defaults: UserDefaults
    public let modelsDirectory: URL
    public let defaultModel: LocalWhisperModelDescriptor

    private let fileManager: FileManager
    private let session: URLSession
    private var activeDownloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        modelsDirectory: URL? = nil,
        defaultModel: LocalWhisperModelDescriptor = .ggmlLargeV3TurboQ50
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.session = session
        self.defaultModel = defaultModel
        self.modelsDirectory = modelsDirectory ?? Self.defaultModelsDirectory(fileManager: fileManager)
        createModelsDirectoryIfNeeded()
        refreshInstalledModels()
    }

    public var isDefaultModelInstalled: Bool {
        isModelInstalled(named: defaultModel.name)
    }

    public func prepareForLaunch(showFirstInstallPrompt: Bool) {
        createModelsDirectoryIfNeeded()
        refreshInstalledModels()

        if isDefaultModelInstalled {
            shouldShowInstallPrompt = false
            statusMessage = "本地模型已就绪。"
            return
        }

        statusMessage = "首次使用时，建议先下载本地默认模型。"
        shouldShowInstallPrompt = showFirstInstallPrompt
    }

    public func refreshInstalledModels() {
        createModelsDirectoryIfNeeded()

        let fileURLs = (try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        installedModelNames = fileURLs
            .filter { $0.pathExtension.lowercased() == "bin" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func isModelInstalled(named name: String) -> Bool {
        fileManager.fileExists(atPath: modelURL(forModelNamed: name).path)
    }

    public func modelURL(forModelNamed name: String) -> URL {
        modelsDirectory.appendingPathComponent("\(name).bin")
    }

    public func resolvedModelURL(preferredModelName: String?) -> URL? {
        let normalizedPreferred = preferredModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedPreferred, !normalizedPreferred.isEmpty {
            let preferredURL = modelURL(forModelNamed: normalizedPreferred)
            if fileManager.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
        }

        let defaultURL = modelURL(forModelNamed: defaultModel.name)
        if fileManager.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }

        guard let firstInstalledName = installedModelNames.first else {
            return nil
        }
        return modelURL(forModelNamed: firstInstalledName)
    }

    public func installDefaultModel() async -> Bool {
        guard !isDownloading else { return false }

        if isDefaultModelInstalled {
            statusMessage = "本地默认模型已安装。"
            shouldShowInstallPrompt = false
            lastErrorMessage = nil
            return true
        }

        createModelsDirectoryIfNeeded()
        isDownloading = true
        downloadProgress = 0
        lastErrorMessage = nil
        statusMessage = "正在下载本地默认模型..."

        let destinationURL = modelURL(forModelNamed: defaultModel.name)

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let task = session.downloadTask(with: defaultModel.downloadURL) { tempURL, response, error in
                Task { @MainActor in
                    defer {
                        self.cleanupDownloadTracking()
                    }

                    if let error {
                        self.lastErrorMessage = error.localizedDescription
                        self.statusMessage = "本地模型下载失败。"
                        continuation.resume(returning: false)
                        return
                    }

                    guard
                        let httpResponse = response as? HTTPURLResponse,
                        (200..<300).contains(httpResponse.statusCode),
                        let tempURL
                    else {
                        self.lastErrorMessage = "下载服务返回了无效响应。"
                        self.statusMessage = "本地模型下载失败。"
                        continuation.resume(returning: false)
                        return
                    }

                    do {
                        if self.fileManager.fileExists(atPath: destinationURL.path) {
                            try self.fileManager.removeItem(at: destinationURL)
                        }
                        try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                        self.refreshInstalledModels()
                        self.shouldShowInstallPrompt = false
                        self.statusMessage = "本地默认模型已安装，可以直接开始使用。"
                        self.lastErrorMessage = nil
                        continuation.resume(returning: true)
                    } catch {
                        self.lastErrorMessage = error.localizedDescription
                        self.statusMessage = "模型文件写入失败。"
                        continuation.resume(returning: false)
                    }
                }
            }

            self.activeDownloadTask = task
            self.progressObservation = task.progress.observe(
                \.fractionCompleted,
                options: [.initial, .new]
            ) { [weak self] progress, _ in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
            task.resume()
        }

        return result
    }

    public func dismissInstallPrompt() {
        shouldShowInstallPrompt = false
    }

    private func cleanupDownloadTracking() {
        progressObservation?.invalidate()
        progressObservation = nil
        activeDownloadTask = nil
        isDownloading = false
    }

    private func createModelsDirectoryIfNeeded() {
        try? fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    private static func defaultModelsDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("SlashVibe", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }
}
