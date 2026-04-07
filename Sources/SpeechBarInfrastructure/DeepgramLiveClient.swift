import Foundation
import SpeechBarDomain

public enum DeepgramLiveClientError: LocalizedError {
    case invalidRequestURL
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .invalidRequestURL:
            return "Deepgram WebSocket URL is invalid."
        case .notConnected:
            return "Deepgram WebSocket is not connected."
        }
    }
}

public actor DeepgramLiveClient: TranscriptionClient {
    public nonisolated let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let session: URLSession
    private let decoder: DeepgramMessageDecoder

    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var isClosing = false

    public init(
        session: URLSession = .shared,
        decoder: DeepgramMessageDecoder = DeepgramMessageDecoder()
    ) {
        var capturedContinuation: AsyncStream<TranscriptEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
        self.session = session
        self.decoder = decoder
    }

    public func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {
        await close()

        let url = configuration.websocketURL
        var request = URLRequest(url: url)
        request.setValue("token \(apiKey)", forHTTPHeaderField: "Authorization")

        let socketTask = session.webSocketTask(with: request)
        self.socketTask = socketTask
        self.isClosing = false
        socketTask.resume()

        continuation.yield(.opened)
        startReceiveLoop(socketTask)
        startKeepAliveLoop()
    }

    public func send(audioChunk: AudioChunk) async throws {
        guard let socketTask else {
            throw DeepgramLiveClientError.notConnected
        }
        try await socketTask.send(.data(audioChunk.data))
    }

    public func finalize() async throws {
        try await sendControlMessage(type: "Finalize")
    }

    public func close() async {
        isClosing = true

        keepAliveTask?.cancel()
        keepAliveTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil

        continuation.yield(.closed)
    }

    private func startReceiveLoop(_ socketTask: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let message = try await socketTask.receive()
                    switch message {
                    case .data(let data):
                        let events = try self.decoder.decode(data: data)
                        await self.emit(events)

                    case .string(let text):
                        let data = Data(text.utf8)
                        let events = try self.decoder.decode(data: data)
                        await self.emit(events)

                    @unknown default:
                        break
                    }
                } catch is CancellationError {
                    return
                } catch {
                    let shouldEmitError = await !self.isClosing
                    if shouldEmitError {
                        await self.emit([.error("Deepgram connection closed unexpectedly.")])
                    }
                    return
                }
            }
        }
    }

    private func startKeepAliveLoop() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                    try await self.sendControlMessage(type: "KeepAlive")
                } catch is CancellationError {
                    return
                } catch {
                    let shouldEmitError = await !self.isClosing
                    if shouldEmitError {
                        await self.emit([.error("Failed to keep the Deepgram stream alive.")])
                    }
                    return
                }
            }
        }
    }

    private func sendControlMessage(type: String) async throws {
        guard let socketTask else {
            throw DeepgramLiveClientError.notConnected
        }

        let payload = try JSONSerialization.data(withJSONObject: ["type": type])
        let text = String(decoding: payload, as: UTF8.self)
        try await socketTask.send(.string(text))
    }

    private func emit(_ events: [TranscriptEvent]) {
        for event in events {
            continuation.yield(event)
        }
    }
}
