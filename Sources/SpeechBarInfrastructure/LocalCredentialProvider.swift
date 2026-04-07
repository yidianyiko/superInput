import Foundation
import SpeechBarDomain

public enum LocalCredentialProviderError: LocalizedError {
    case missingValue

    public var errorDescription: String? {
        switch self {
        case .missingValue:
            return "No API key is currently stored locally."
        }
    }
}

public final class LocalCredentialProvider: CredentialProvider, @unchecked Sendable {
    public let service: String
    public let account: String
    public let defaults: UserDefaults
    public let legacyServices: [String]

    public init(
        service: String = "com.slashvibe.desktop",
        account: String = "deepgram-api-key",
        defaults: UserDefaults = .standard,
        legacyServices: [String] = ["com.startup.speechbar"]
    ) {
        self.service = service
        self.account = account
        self.defaults = defaults
        self.legacyServices = legacyServices
    }

    public func credentialStatus() -> CredentialStatus {
        if let value = defaults.string(forKey: storageKey(for: service)) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .missing : .available
        }

        for legacyService in legacyServices where legacyService != service {
            guard let legacyValue = defaults.string(forKey: storageKey(for: legacyService)) else {
                continue
            }
            if legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return .available
            }
        }
        return .missing
    }

    public func loadAPIKey() throws -> String {
        if let value = defaults.string(forKey: storageKey(for: service)) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw LocalCredentialProviderError.missingValue
            }
            return trimmed
        }

        for legacyService in legacyServices where legacyService != service {
            guard let legacyValue = defaults.string(forKey: storageKey(for: legacyService)) else {
                continue
            }
            let trimmed = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            defaults.set(trimmed, forKey: storageKey(for: service))
            return trimmed
        }

        throw LocalCredentialProviderError.missingValue
    }

    public func save(apiKey: String) throws {
        defaults.set(apiKey, forKey: storageKey(for: service))
    }

    public func deleteAPIKey() throws {
        defaults.removeObject(forKey: storageKey(for: service))
        for legacyService in legacyServices where legacyService != service {
            defaults.removeObject(forKey: storageKey(for: legacyService))
        }
    }

    private func storageKey(for service: String) -> String {
        "credentials.\(service).\(account)"
    }
}
