import Foundation
import Security

public protocol MemoryKeyProviding: Sendable {
    func loadOrCreateMasterKey() throws -> Data
}

public struct KeychainMemoryKeyProvider: MemoryKeyProviding {
    public let service: String
    public let account: String

    public init(
        service: String,
        account: String = "local-master-key"
    ) {
        self.service = service
        self.account = account
    }

    public func loadOrCreateMasterKey() throws -> Data {
        if let existing = try loadExistingKey() {
            return existing
        }

        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MemoryKeyProviderError.keyGenerationFailed(status)
        }

        try store(data: data)
        return data
    }

    private func baseQuery(returnData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if returnData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    private func loadExistingKey() throws -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(baseQuery(returnData: true) as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw MemoryKeyProviderError.keychainFailure(status)
        }
        guard let data = item as? Data, data.count == 32 else {
            throw MemoryKeyProviderError.invalidStoredKey
        }
        return data
    }

    private func store(data: Data) throws {
        let deleteStatus = SecItemDelete(baseQuery() as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw MemoryKeyProviderError.keychainFailure(deleteStatus)
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MemoryKeyProviderError.keychainFailure(addStatus)
        }
    }
}

private enum MemoryKeyProviderError: LocalizedError {
    case keyGenerationFailed(OSStatus)
    case keychainFailure(OSStatus)
    case invalidStoredKey

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let status):
            return "Failed to generate memory encryption key (\(status))."
        case .keychainFailure(let status):
            return "Keychain memory key operation failed (\(status))."
        case .invalidStoredKey:
            return "Stored memory encryption key was invalid."
        }
    }
}
