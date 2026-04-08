import CryptoKit
import Foundation

struct MemoryCipher {
    private let key: SymmetricKey

    init(masterKeyData: Data) throws {
        guard masterKeyData.count == 32 else {
            throw MemoryCipherError.invalidKeyLength
        }
        self.key = SymmetricKey(data: masterKeyData)
    }

    func encrypt(_ plaintext: String) throws -> Data {
        try encrypt(Data(plaintext.utf8))
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw MemoryCipherError.missingCombinedRepresentation
        }
        return combined
    }

    func decrypt(_ payload: Data) throws -> Data {
        let sealed = try AES.GCM.SealedBox(combined: payload)
        return try AES.GCM.open(sealed, using: key)
    }

    func decryptToString(_ payload: Data) throws -> String {
        let decrypted = try decrypt(payload)
        return String(decoding: decrypted, as: UTF8.self)
    }
}

private enum MemoryCipherError: LocalizedError {
    case invalidKeyLength
    case missingCombinedRepresentation

    var errorDescription: String? {
        switch self {
        case .invalidKeyLength:
            return "Memory encryption requires a 32-byte symmetric key."
        case .missingCombinedRepresentation:
            return "Memory encryption could not produce a combined payload."
        }
    }
}
