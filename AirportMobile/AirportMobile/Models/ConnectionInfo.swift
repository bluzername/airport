import Foundation

/// Non-sensitive connection metadata (stored in UserDefaults).
struct SavedConnectionMeta: Codable {
    let host: String
    let port: Int
    let serverName: String
    let pairedAt: Date
}

/// Full connection info returned by ConnectionStore.load().
struct SavedConnection {
    let host: String
    let port: Int
    let deviceToken: String
    let serverName: String
    let pairedAt: Date
}

/// Pairing info received from QR code scan.
struct PairingQRData: Codable {
    let h: String   // host
    let p: Int      // port
    let t: String   // pairing token
    let n: String   // server name
}

enum ConnectionStore {
    private static let metaKey = "airport_connection_meta"
    private static let tokenKey = "airport_device_token"

    static func save(_ connection: SavedConnection) {
        // Store token in Keychain (secure)
        _ = KeychainStore.save(key: tokenKey, value: connection.deviceToken)

        // Store non-sensitive metadata in UserDefaults
        let meta = SavedConnectionMeta(
            host: connection.host,
            port: connection.port,
            serverName: connection.serverName,
            pairedAt: connection.pairedAt
        )
        if let data = try? JSONEncoder().encode(meta) {
            UserDefaults.standard.set(data, forKey: metaKey)
        }
    }

    static func load() -> SavedConnection? {
        guard let metaData = UserDefaults.standard.data(forKey: metaKey),
              let meta = try? JSONDecoder().decode(SavedConnectionMeta.self, from: metaData),
              let token = KeychainStore.load(key: tokenKey) else {
            return nil
        }
        return SavedConnection(
            host: meta.host,
            port: meta.port,
            deviceToken: token,
            serverName: meta.serverName,
            pairedAt: meta.pairedAt
        )
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: metaKey)
        KeychainStore.delete(key: tokenKey)
    }
}
