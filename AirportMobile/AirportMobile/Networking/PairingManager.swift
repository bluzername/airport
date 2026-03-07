import Foundation
import UIKit  // For UIDevice.current.name

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
    let certFingerprint: String
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
    /// The pairing POST itself uses HTTPS with the self-signed cert.
    /// We accept any cert for this one request since we don't have the fingerprint yet
    /// (the fingerprint is in the QR code / provided by the user).
    static func pair(host: String, port: Int, token: String, certFingerprint: String? = nil) async throws -> PairingResult {
        let url = URL(string: "https://\(host):\(port)/pair")!
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

        // Use a delegate that accepts the self-signed cert during pairing
        let pairingDelegate = PairingURLSessionDelegate(expectedFingerprint: certFingerprint)
        let session = URLSession(configuration: .default, delegate: pairingDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)

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

        // Use the fingerprint from the actual server cert if we captured it,
        // otherwise fall back to the one from the QR code
        let actualFingerprint = pairingDelegate.capturedFingerprint ?? certFingerprint ?? ""

        return PairingResult(
            deviceToken: deviceToken,
            serverName: serverName,
            certFingerprint: actualFingerprint,
            host: host,
            port: port
        )
    }

    /// Complete the full pairing flow from QR data.
    static func pairFromQR(_ qrString: String) async throws -> PairingResult {
        let qr = try parseQR(qrString)
        return try await pair(host: qr.h, port: qr.p, token: qr.t, certFingerprint: qr.k)
    }
}

// MARK: - Pairing-specific URLSession delegate

/// Accepts self-signed certs during initial pairing and captures
/// the server certificate fingerprint for future pinning.
private class PairingURLSessionDelegate: NSObject, URLSessionDelegate {
    let expectedFingerprint: String?
    var capturedFingerprint: String?

    init(expectedFingerprint: String?) {
        self.expectedFingerprint = expectedFingerprint
        super.init()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Capture the server cert fingerprint
        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let cert = chain.first {
            let certData = SecCertificateCopyData(cert) as Data
            var hash = [UInt8](repeating: 0, count: 32)
            certData.withUnsafeBytes { bytes in
                CC_SHA256(bytes.baseAddress, CC_LONG(certData.count), &hash)
            }
            capturedFingerprint = hash.map { String(format: "%02X", $0) }.joined(separator: ":")
        }

        // If we have an expected fingerprint from the QR code, verify it
        if let expected = expectedFingerprint, !expected.isEmpty {
            if capturedFingerprint == expected {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        // No expected fingerprint — accept for pairing (TOFU: Trust On First Use)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

import CommonCrypto
