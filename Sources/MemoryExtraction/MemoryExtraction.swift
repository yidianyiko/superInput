import Foundation
import MemoryDomain

public struct DefaultMemoryExtractor: MemoryExtractor {
    public init() {}

    public func extract(from event: InputEvent) async throws -> [MemoryItem] {
        guard event.sensitivityClass == .normal || event.sensitivityClass == .redacted else {
            return []
        }

        var results: [MemoryItem] = []

        if let correction = correctionMemory(from: event) {
            results.append(correction)
        }
        if let vocabulary = vocabularyMemory(from: event) {
            results.append(vocabulary)
        }
        if let scene = sceneMemory(from: event) {
            results.append(scene)
        }
        if let style = styleMemory(from: event) {
            results.append(style)
        }

        return results
    }

    private func correctionMemory(from event: InputEvent) -> MemoryItem? {
        guard event.hasConfirmedFinalText,
              let source = event.insertedText ?? event.rawTranscript,
              let final = event.finalUserEditedText,
              source != final else {
            return nil
        }

        return makeMemory(
            type: .correction,
            key: "corr:\(normalized(source))",
            payload: final,
            scope: .app(event.appIdentifier),
            confidence: 0.75,
            sourceEventID: event.id,
            timestamp: event.timestamp,
            confirmedAt: event.timestamp
        )
    }

    private func vocabularyMemory(from event: InputEvent) -> MemoryItem? {
        guard let text = event.effectiveLearningText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let confidence = event.hasConfirmedFinalText ? 0.65 : 0.55
        return makeMemory(
            type: .vocabulary,
            key: "term:\(normalized(text))",
            payload: text,
            scope: .app(event.appIdentifier),
            confidence: confidence,
            sourceEventID: event.id,
            timestamp: event.timestamp,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func sceneMemory(from event: InputEvent) -> MemoryItem? {
        guard let label = event.fieldLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return nil
        }

        let confidence = event.hasConfirmedFinalText ? 0.65 : 0.45
        return makeMemory(
            type: .scene,
            key: "scene:\(event.appIdentifier):\(normalized(label))",
            payload: event.fieldRole,
            scope: .field(
                appIdentifier: event.appIdentifier,
                windowTitle: event.windowTitle,
                fieldRole: event.fieldRole,
                fieldLabel: event.fieldLabel
            ),
            confidence: confidence,
            sourceEventID: event.id,
            timestamp: event.timestamp,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func styleMemory(from event: InputEvent) -> MemoryItem? {
        guard event.actionType == .polish,
              let final = event.effectiveLearningText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !final.isEmpty else {
            return nil
        }

        let brevity = final.count < 80 ? "short" : "long"
        let confidence = event.hasConfirmedFinalText ? 0.65 : 0.45
        return makeMemory(
            type: .style,
            key: "style:\(event.appIdentifier):default",
            payload: "brevity=\(brevity)",
            scope: .app(event.appIdentifier),
            confidence: confidence,
            sourceEventID: event.id,
            timestamp: event.timestamp,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func makeMemory(
        type: MemoryType,
        key: String,
        payload: String,
        scope: MemoryScope,
        confidence: Double,
        sourceEventID: UUID,
        timestamp: Date,
        confirmedAt: Date?
    ) -> MemoryItem {
        let normalizedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return MemoryItem(
            id: UUID(),
            type: type,
            key: key,
            valuePayload: Data(normalizedPayload.utf8),
            valueFingerprint: normalizedPayload,
            identityHash: "\(type.rawValue)|\(key)|\(scope.identityComponent)|\(normalizedPayload)",
            scope: scope,
            confidence: confidence,
            status: .active,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastConfirmedAt: confirmedAt,
            sourceEventIDs: [sourceEventID]
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
