import Foundation
import Security
import SpeechBarDomain

private struct KeychainCredentialCacheKey: Hashable {
    let service: String
    let account: String
}

private final class KeychainCredentialCache: @unchecked Sendable {
    static let shared = KeychainCredentialCache()

    private let queue = DispatchQueue(label: "com.slashvibe.desktop.keychain-cache")
    private var values: [KeychainCredentialCacheKey: String] = [:]

    func value(for key: KeychainCredentialCacheKey) -> String? {
        queue.sync { values[key] }
    }

    func setValue(_ value: String, for key: KeychainCredentialCacheKey) {
        queue.sync {
            values[key] = value
        }
    }

    func removeValue(for key: KeychainCredentialCacheKey) {
        _ = queue.sync {
            values.removeValue(forKey: key)
        }
    }
}

public enum KeychainCredentialProviderError: LocalizedError {
    case missingValue
    case unexpectedData
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingValue:
            return "No Deepgram API key is currently stored in Keychain."
        case .unexpectedData:
            return "Keychain returned an unexpected value."
        case .keychainFailure(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

public struct KeychainCredentialProvider: CredentialProvider, Sendable {
    public let service: String
    public let account: String
    public let legacyServices: [String]

    public init(
        service: String = "com.slashvibe.desktop",
        account: String = "deepgram-api-key",
        legacyServices: [String] = ["com.startup.speechbar"]
    ) {
        self.service = service
        self.account = account
        self.legacyServices = legacyServices
    }

    public func credentialStatus() -> CredentialStatus {
        if hasCredential(forService: service) {
            return .available
        }
        for legacyService in legacyServices where legacyService != service {
            if hasCredential(forService: legacyService) {
                return .available
            }
        }
        return .missing
    }

    public func loadAPIKey() throws -> String {
        let cacheKey = KeychainCredentialCacheKey(service: service, account: account)
        if let cached = KeychainCredentialCache.shared.value(for: cacheKey) {
            return cached
        }

        if let key = try loadAPIKey(forService: service) {
            KeychainCredentialCache.shared.setValue(key, for: cacheKey)
            return key
        }

        for legacyService in legacyServices where legacyService != service {
            guard let key = try loadAPIKey(forService: legacyService) else {
                continue
            }
            try replaceStoredValue(with: Data(key.utf8), service: service)
            KeychainCredentialCache.shared.setValue(key, for: cacheKey)
            return key
        }

        throw KeychainCredentialProviderError.missingValue
    }

    public func save(apiKey: String) throws {
        let data = Data(apiKey.utf8)
        try replaceStoredValue(with: data, service: service)
        let cacheKey = KeychainCredentialCacheKey(service: service, account: account)
        KeychainCredentialCache.shared.setValue(apiKey, for: cacheKey)
    }

    public func deleteAPIKey() throws {
        let servicesToDelete = [service] + legacyServices.filter { $0 != service }
        for targetService in servicesToDelete {
            let status = SecItemDelete(baseQuery(forService: targetService) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainCredentialProviderError.keychainFailure(status)
            }
            let cacheKey = KeychainCredentialCacheKey(service: targetService, account: account)
            KeychainCredentialCache.shared.removeValue(for: cacheKey)
        }
    }

    private func baseQuery(forService service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func replaceStoredValue(with data: Data, service: String) throws {
        let deleteStatus = SecItemDelete(baseQuery(forService: service) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainCredentialProviderError.keychainFailure(deleteStatus)
        }

        var addQuery = baseQuery(forService: service)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        if let access = makeTrustedAccess(service: service) {
            addQuery[kSecAttrAccess as String] = access
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialProviderError.keychainFailure(addStatus)
        }
    }

    private func makeTrustedAccess(service: String) -> SecAccess? {
        let path = Bundle.main.bundlePath
        guard !path.isEmpty else { return nil }

        var trustedApplication: SecTrustedApplication?
        let trustedStatus = path.withCString { pointer in
            SecTrustedApplicationCreateFromPath(pointer, &trustedApplication)
        }
        guard trustedStatus == errSecSuccess, let trustedApplication else {
            return nil
        }

        var access: SecAccess?
        let accessLabel = "\(service):\(account)" as CFString
        let accessStatus = SecAccessCreate(accessLabel, [trustedApplication] as CFArray, &access)
        guard accessStatus == errSecSuccess else {
            return nil
        }

        return access
    }

    private func hasCredential(forService service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadAPIKey(forService service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialProviderError.keychainFailure(status)
        }
        guard let data = item as? Data else {
            throw KeychainCredentialProviderError.unexpectedData
        }
        guard let key = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialProviderError.unexpectedData
        }
        return key
    }
}
