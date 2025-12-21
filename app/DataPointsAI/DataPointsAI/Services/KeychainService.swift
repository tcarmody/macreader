import Foundation
import Security

/// Service for securely storing and retrieving API keys from macOS Keychain
final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let serviceName = "com.datapointsai.apikeys"

    private init() {}

    // MARK: - Keychain Keys

    enum KeychainKey: String, CaseIterable, Sendable {
        case anthropicAPIKey = "anthropic_api_key"
        case openaiAPIKey = "openai_api_key"
        case googleAPIKey = "google_api_key"

        var displayName: String {
            switch self {
            case .anthropicAPIKey: return "Anthropic API Key"
            case .openaiAPIKey: return "OpenAI API Key"
            case .googleAPIKey: return "Google API Key"
            }
        }

        /// Maps to the environment variable name expected by the backend
        var environmentVariable: String {
            switch self {
            case .anthropicAPIKey: return "ANTHROPIC_API_KEY"
            case .openaiAPIKey: return "OPENAI_API_KEY"
            case .googleAPIKey: return "GOOGLE_API_KEY"
            }
        }

        /// Maps to the LLMProvider enum
        var provider: LLMProvider {
            switch self {
            case .anthropicAPIKey: return .anthropic
            case .openaiAPIKey: return .openai
            case .googleAPIKey: return .google
            }
        }

        /// Creates KeychainKey from LLMProvider
        static func from(provider: LLMProvider) -> KeychainKey {
            switch provider {
            case .anthropic: return .anthropicAPIKey
            case .openai: return .openaiAPIKey
            case .google: return .googleAPIKey
            }
        }
    }

    // MARK: - Public API

    /// Save an API key to the Keychain
    func save(key: String, for keychainKey: KeychainKey) throws {
        let data = Data(key.utf8)

        // First try to delete any existing key
        try? delete(keychainKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve an API key from the Keychain
    func retrieve(_ keychainKey: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Delete an API key from the Keychain
    func delete(_ keychainKey: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keychainKey.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if an API key exists in the Keychain
    func hasKey(_ keychainKey: KeychainKey) -> Bool {
        return retrieve(keychainKey) != nil
    }

    /// Get all configured API keys as environment variables for the backend
    func getEnvironmentVariables() -> [String: String] {
        var env: [String: String] = [:]

        for key in KeychainKey.allCases {
            if let value = retrieve(key), !value.isEmpty {
                env[key.environmentVariable] = value
            }
        }

        return env
    }

    /// Check if any API key is configured
    func hasAnyAPIKey() -> Bool {
        return KeychainKey.allCases.contains { hasKey($0) }
    }

    /// Get the list of configured providers
    func configuredProviders() -> [LLMProvider] {
        return KeychainKey.allCases.compactMap { key in
            hasKey(key) ? key.provider : nil
        }
    }

    /// Save API key for a specific provider
    func save(key: String, for provider: LLMProvider) throws {
        try save(key: key, for: KeychainKey.from(provider: provider))
    }

    /// Retrieve API key for a specific provider
    func retrieve(for provider: LLMProvider) -> String? {
        return retrieve(KeychainKey.from(provider: provider))
    }

    /// Delete API key for a specific provider
    func delete(provider: LLMProvider) throws {
        try delete(KeychainKey.from(provider: provider))
    }

    /// Check if a provider has an API key configured
    func hasKey(for provider: LLMProvider) -> Bool {
        return hasKey(KeychainKey.from(provider: provider))
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (error \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (error \(status))"
        }
    }
}
