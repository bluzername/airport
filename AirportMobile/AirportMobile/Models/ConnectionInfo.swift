import Foundation

/// Persisted connection info for auto-reconnect.
struct SavedConnection: Codable {
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
    private static let key = "airport_saved_connection"

    static func save(_ connection: SavedConnection) {
        if let data = try? JSONEncoder().encode(connection) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> SavedConnection? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedConnection.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
