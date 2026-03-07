import Foundation

/// Handles the pairing flow with the Airport desktop app.
enum PairingError: LocalizedError {
    case invalidQRData
    case networkError(Error)
    case pairingRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidQRData:
            return "Invalid QR code data"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .pairingRejected(let reason):
            return "Pairing rejected: \(reason)"
        }
    }
}

struct PairingResult {
    let deviceToken: String
    let serverName: String
    let host: String
    let port: Int
}

enum PairingManager {
    /// Parse QR code data from the Airport desktop app.
    static func parseQR(_ string: String) throws -> PairingQRData {
        guard let data = string.data(using: .utf8),
              let qr = try? JSONDecoder().decode(PairingQRData.self, from: data) else {
            throw PairingError.invalidQRData
        }
        return qr
    }

    /// Complete pairing by exchanging the one-time token for a persistent device token.
    static func pair(host: String, port: Int, token: String) async throws -> PairingResult {
        let url = URL(string: "http://\(host):\(port)/pair")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceId: String
        if let saved = UserDefaults.standard.string(forKey: "airport_device_id") {
            deviceId = saved
        } else {
            deviceId = UUID().uuidString
            UserDefaults.standard.set(deviceId, forKey: "airport_device_id")
        }

        let deviceName = UIDevice.current.name
        let body: [String: Any] = [
            "token": token,
            "deviceId": deviceId,
            "deviceName": deviceName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PairingError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw PairingError.pairingRejected(error)
            }
            throw PairingError.pairingRejected("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceToken = json["deviceToken"] as? String,
              let serverName = json["serverName"] as? String else {
            throw PairingError.pairingRejected("Invalid response")
        }

        return PairingResult(
            deviceToken: deviceToken,
            serverName: serverName,
            host: host,
            port: port
        )
    }

    /// Complete the full pairing flow from QR data.
    static func pairFromQR(_ qrString: String) async throws -> PairingResult {
        let qr = try parseQR(qrString)
        return try await pair(host: qr.h, port: qr.p, token: qr.t)
    }
}

import UIKit  // For UIDevice.current.name
