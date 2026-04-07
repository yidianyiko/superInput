import Foundation
import Security

@MainActor
enum SlashVibeMigration {
    private static let oldBundleIdentifier = "com.startup.speechbar.local"
    private static let newBundleIdentifier = "com.slashvibe.desktop.local"
    private static let oldCredentialService = "com.startup.speechbar"
    private static let newCredentialService = "com.slashvibe.desktop"
    private static let oldApplicationSupportFolder = "StartUpSpeechBar"
    private static let newApplicationSupportFolder = "SlashVibe"

    private static var hasRunInProcess = false

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard hasRunInProcess == false else {
            return
        }
        hasRunInProcess = true

        migrateDefaultsDomain(defaults: defaults)
        migrateDefaultCredentialEntries(defaults: defaults)
        migrateApplicationSupportDirectory(fileManager: fileManager)
        migrateKeychainCredentials()
    }

    private static func migrateDefaultsDomain(defaults: UserDefaults) {
        let currentBundleIdentifier = Bundle.main.bundleIdentifier ?? newBundleIdentifier
        guard currentBundleIdentifier == newBundleIdentifier else {
            return
        }
        guard let legacyDomain = defaults.persistentDomain(forName: oldBundleIdentifier), !legacyDomain.isEmpty else {
            return
        }

        var currentDomain = defaults.persistentDomain(forName: currentBundleIdentifier) ?? [:]
        var copiedCount = 0
        for (key, value) in legacyDomain where currentDomain[key] == nil {
            currentDomain[key] = value
            copiedCount += 1
        }

        guard copiedCount > 0 else {
            return
        }
        defaults.setPersistentDomain(currentDomain, forName: currentBundleIdentifier)
        NSLog("SlashVibeMigration: copied \(copiedCount) UserDefaults keys from \(oldBundleIdentifier) to \(currentBundleIdentifier).")
    }

    private static func migrateDefaultCredentialEntries(defaults: UserDefaults) {
        let oldPrefix = "credentials.\(oldCredentialService)."
        let newPrefix = "credentials.\(newCredentialService)."
        var copiedCount = 0

        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(oldPrefix) {
            let suffix = String(key.dropFirst(oldPrefix.count))
            let newKey = newPrefix + suffix
            guard defaults.object(forKey: newKey) == nil else {
                continue
            }
            defaults.set(value, forKey: newKey)
            copiedCount += 1
        }

        if copiedCount > 0 {
            NSLog("SlashVibeMigration: migrated \(copiedCount) local credential entries in UserDefaults.")
        }
    }

    private static func migrateApplicationSupportDirectory(fileManager: FileManager) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)

        let oldDirectory = applicationSupport.appendingPathComponent(oldApplicationSupportFolder, isDirectory: true)
        let newDirectory = applicationSupport.appendingPathComponent(newApplicationSupportFolder, isDirectory: true)

        guard fileManager.fileExists(atPath: oldDirectory.path) else {
            return
        }

        do {
            if fileManager.fileExists(atPath: newDirectory.path) == false {
                try fileManager.createDirectory(at: newDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: oldDirectory, to: newDirectory)
                NSLog("SlashVibeMigration: moved Application Support directory to \(newDirectory.path).")
                return
            }

            let mergedCount = try mergeMissingContents(
                from: oldDirectory,
                to: newDirectory,
                fileManager: fileManager
            )
            if mergedCount > 0 {
                NSLog("SlashVibeMigration: merged \(mergedCount) missing files into \(newDirectory.path).")
            }
        } catch {
            NSLog("SlashVibeMigration: Application Support migration failed: \(error.localizedDescription)")
        }
    }

    private static func mergeMissingContents(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws -> Int {
        let sourceRootPath = sourceRoot.path
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var copiedCount = 0
        for case let sourceURL as URL in enumerator {
            let resourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            let sourcePath = sourceURL.path
            guard sourcePath.count > sourceRootPath.count else {
                continue
            }

            let relativePath = String(sourcePath.dropFirst(sourceRootPath.count + 1))
            let destinationURL = destinationRoot.appendingPathComponent(
                relativePath,
                isDirectory: resourceValues.isDirectory ?? false
            )

            if resourceValues.isDirectory == true {
                if fileManager.fileExists(atPath: destinationURL.path) == false {
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                }
                continue
            }

            guard fileManager.fileExists(atPath: destinationURL.path) == false else {
                continue
            }

            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            copiedCount += 1
        }

        return copiedCount
    }

    private static func migrateKeychainCredentials() {
        guard let legacyItems = fetchKeychainItems(service: oldCredentialService), legacyItems.isEmpty == false else {
            return
        }

        var migratedCount = 0
        for item in legacyItems {
            guard
                let account = item[kSecAttrAccount as String] as? String,
                let valueData = item[kSecValueData as String] as? Data
            else {
                continue
            }

            guard keychainItemExists(service: newCredentialService, account: account) == false else {
                continue
            }

            let status = saveKeychainItem(
                service: newCredentialService,
                account: account,
                valueData: valueData
            )
            if status == errSecSuccess || status == errSecDuplicateItem {
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            NSLog("SlashVibeMigration: migrated \(migratedCount) Keychain credentials.")
        }
    }

    private static func fetchKeychainItems(service: String) -> [[String: Any]]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            NSLog("SlashVibeMigration: failed to read legacy Keychain items (\(status)).")
            return nil
        }

        if let singleItem = result as? [String: Any] {
            return [singleItem]
        }
        if let itemList = result as? [[String: Any]] {
            return itemList
        }
        return []
    }

    private static func keychainItemExists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func saveKeychainItem(
        service: String,
        account: String,
        valueData: Data
    ) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }
}
