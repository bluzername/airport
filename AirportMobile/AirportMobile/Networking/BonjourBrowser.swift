import Foundation
import Network

/// Discovers Airport desktop instances on the local network via Bonjour/mDNS.
@Observable
final class BonjourBrowser {
    struct DiscoveredServer: Identifiable, Hashable {
        let id: String
        let name: String
        let host: String
        let port: Int
    }

    private(set) var servers: [DiscoveredServer] = []
    private var browser: NWBrowser?

    init() {
        startBrowsing()
    }

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_airport-sync._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.handleResults(results)
            }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("Bonjour browse failed: \(error)")
            default:
                break
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var newServers: [DiscoveredServer] = []

        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                // Resolve the service to get host/port
                let connection = NWConnection(to: result.endpoint, using: .tcp)
                connection.stateUpdateHandler = { [weak self] state in
                    if case .ready = state {
                        if let endpoint = connection.currentPath?.remoteEndpoint,
                           case .hostPort(let host, let port) = endpoint {
                            let hostStr: String
                            switch host {
                            case .ipv4(let addr):
                                hostStr = "\(addr)"
                            case .ipv6(let addr):
                                hostStr = "\(addr)"
                            case .name(let hostname, _):
                                hostStr = hostname
                            @unknown default:
                                hostStr = "unknown"
                            }
                            let server = DiscoveredServer(
                                id: name,
                                name: name,
                                host: hostStr,
                                port: Int(port.rawValue)
                            )
                            DispatchQueue.main.async {
                                if !(self?.servers.contains(where: { $0.id == server.id }) ?? false) {
                                    self?.servers.append(server)
                                }
                            }
                        }
                        connection.cancel()
                    }
                }
                connection.start(queue: .global())

                // Also add with the service name for display
                newServers.append(DiscoveredServer(
                    id: name,
                    name: name,
                    host: "", // Will be resolved
                    port: 0
                ))
            }
        }
    }
}
