import Foundation
import SpeechBarInfrastructure

private func boardBridgeDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [BoardBridge] \(message)\n"
    let path = "/tmp/speechbar_debug.log"
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

final class BoardInputBridgeController: @unchecked Sendable {
    private static let preferredPortDefaultsKey = "board.input.preferredSerialPort"
    private static let preferredPythonEnvKey = "SLASHVIBE_PYTHON_EXECUTABLE"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let outputURL: URL
    private let rawCaptureURL: URL
    private let scriptsRuntimeDirectory: URL

    private var supervisorTask: Task<Void, Never>?
    private var currentProcess: Process?
    private var outputDrainTasks: [Task<Void, Never>] = []
    private var lastReportedPort: String?
    private var lastMissingPortLogAt = Date.distantPast

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        outputURL: URL = BoardInputPaths.eventsFileURL(fileManager: .default),
        rawCaptureURL: URL = BoardInputPaths.rawSerialCaptureFileURL(fileManager: .default),
        autoStart: Bool = true
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.outputURL = outputURL
        self.rawCaptureURL = rawCaptureURL
        self.scriptsRuntimeDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("SlashVibe/HardwareBridge", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("SlashVibe-HardwareBridge", isDirectory: true)

        if autoStart {
            start()
        }
    }

    deinit {
        stop()
    }

    func start() {
        guard supervisorTask == nil else { return }
        supervisorTask = Task { [weak self] in
            await self?.runSupervisorLoop()
        }
    }

    func stop() {
        supervisorTask?.cancel()
        supervisorTask = nil
        stopCurrentProcess()
    }

    private func runSupervisorLoop() async {
        boardBridgeDebugLog("board bridge supervisor started")

        while !Task.isCancelled {
            guard let portPath = preferredSerialPortPath() else {
                maybeLogMissingPort()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                continue
            }

            do {
                try await runBridge(on: portPath)
            } catch {
                boardBridgeDebugLog("bridge failed on port=\(portPath): \(error.localizedDescription)")
            }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    private func runBridge(on portPath: String) async throws {
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: outputURL.path) {
            fileManager.createFile(atPath: outputURL.path, contents: Data())
        }
        if fileManager.fileExists(atPath: rawCaptureURL.path) {
            try fileManager.removeItem(at: rawCaptureURL)
        }
        fileManager.createFile(atPath: rawCaptureURL.path, contents: Data())

        let scriptURLs = try prepareBridgeScripts()
        let pythonExecutable = resolvedPythonExecutable()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.currentDirectoryURL = scriptsRuntimeDirectory
        process.arguments = [
            "-u",
            scriptURLs.bridge.path,
            "--port", portPath,
            "--baudrate", "230400",
            "--output", outputURL.path,
            "--raw-dump", rawCaptureURL.path,
            "--source", "usbHID",
            "--hello-interval", "0.8"
        ]
        process.environment = pythonEnvironment(vendorURL: scriptURLs.vendor)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        boardBridgeDebugLog(
            "launching CDC bridge on port=\(portPath), python=\(pythonExecutable), rawCapture=\(rawCaptureURL.path)"
        )
        try process.run()
        currentProcess = process
        lastReportedPort = portPath
        startDraining(pipe: stdoutPipe, label: "stdout")
        startDraining(pipe: stderrPipe, label: "stderr")

        let terminationStatus = await waitForProcessExit(process)
        boardBridgeDebugLog("bridge exited status=\(terminationStatus) port=\(portPath)")
        stopCurrentProcess()
    }

    private func stopCurrentProcess() {
        outputDrainTasks.forEach { $0.cancel() }
        outputDrainTasks.removeAll()

        if let currentProcess, currentProcess.isRunning {
            currentProcess.terminate()
        }
        currentProcess = nil
    }

    private func startDraining(pipe: Pipe, label: String) {
        let task = Task.detached(priority: .utility) {
            let handle = pipe.fileHandleForReading
            while !Task.isCancelled {
                let data = try? handle.read(upToCount: 512)
                guard let data, !data.isEmpty else { break }
                let text = String(decoding: data, as: UTF8.self)
                for rawLine in text.split(whereSeparator: \.isNewline) {
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        boardBridgeDebugLog("\(label): \(line)")
                    }
                }
            }
        }
        outputDrainTasks.append(task)
    }

    private func waitForProcessExit(_ process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus)
            }
        }
    }

    private func prepareBridgeScripts() throws -> (bridge: URL, proto: URL, vendor: URL) {
        try fileManager.createDirectory(at: scriptsRuntimeDirectory, withIntermediateDirectories: true)

        let bridgeURL = scriptsRuntimeDirectory.appendingPathComponent("slashvibe_cdc_event_bridge.py")
        let protoURL = scriptsRuntimeDirectory.appendingPathComponent("slashvibe_host_proto.py")
        let vendorURL = scriptsRuntimeDirectory.appendingPathComponent("python_vendor", isDirectory: true)

        try copyBridgeResource(
            named: "slashvibe_cdc_event_bridge",
            extension: "py",
            to: bridgeURL
        )
        try copyBridgeResource(
            named: "slashvibe_host_proto",
            extension: "py",
            to: protoURL
        )
        try copyBridgeDirectory(
            named: "python_vendor",
            to: vendorURL
        )

        return (bridgeURL, protoURL, vendorURL)
    }

    private func copyBridgeResource(
        named resourceName: String,
        extension resourceExtension: String,
        to destinationURL: URL
    ) throws {
        guard let sourceURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "HardwareBridge"
        ) else {
            throw NSError(
                domain: "BoardInputBridgeController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到内置 CDC bridge 资源：\(resourceName).\(resourceExtension)"]
            )
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func copyBridgeDirectory(
        named resourceName: String,
        to destinationURL: URL
    ) throws {
        guard let sourceURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: nil,
            subdirectory: "HardwareBridge"
        ) else {
            throw NSError(
                domain: "BoardInputBridgeController",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "找不到内置 CDC bridge 目录资源：\(resourceName)"]
            )
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func resolvedPythonExecutable() -> String {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment[Self.preferredPythonEnvKey],
            "/usr/bin/python3",
            "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3"
        ]

        for candidate in candidates {
            guard let candidate,
                  !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  fileManager.isExecutableFile(atPath: candidate)
            else {
                continue
            }
            return candidate
        }

        return "/usr/bin/python3"
    }

    private func pythonEnvironment(vendorURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existing = environment["PYTHONPATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let merged = [vendorURL.path] + existing.filter { $0 != vendorURL.path }
        environment["PYTHONPATH"] = merged.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }
    private func preferredSerialPortPath() -> String? {
        if let envPort = ProcessInfo.processInfo.environment["SLASHVIBE_BOARD_PORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envPort.isEmpty,
           fileManager.fileExists(atPath: envPort) {
            return envPort
        }

        if let defaultsPort = defaults.string(forKey: Self.preferredPortDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !defaultsPort.isEmpty,
           fileManager.fileExists(atPath: defaultsPort) {
            return defaultsPort
        }

        let candidates = serialPortCandidates()
        return candidates.first
    }

    private func serialPortCandidates() -> [String] {
        let devURL = URL(fileURLWithPath: "/dev", isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: devURL.path)) ?? []
        let preferredPrefixes = [
            "cu.usbmodem",
            "tty.usbmodem",
            "cu.usbserial",
            "tty.usbserial",
            "cu.wchusbserial",
            "tty.wchusbserial",
            "cu.SLAB_USBtoUART",
            "tty.SLAB_USBtoUART"
        ]

        return names
            .filter { name in
                preferredPrefixes.contains { name.hasPrefix($0) }
            }
            .sorted()
            .map { devURL.appendingPathComponent($0).path }
    }

    private func maybeLogMissingPort() {
        let now = Date()
        guard now.timeIntervalSince(lastMissingPortLogAt) >= 5 else { return }
        lastMissingPortLogAt = now
        boardBridgeDebugLog("no CDC serial device detected under /dev")
    }
}
