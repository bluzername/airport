import Foundation

// MARK: - Messages

enum ClientMessage {
    case auth(deviceId: String, token: String)
    case ptyWrite(sessionId: String, data: String)
    case sessionRename(id: String, title: String)
    case sessionBacklog(id: String)
    case sessionRestore(id: String)
    case sessionSetActive(id: String)
    case workspaceSwitch(id: String)
    case planRequest(sessionId: String, filename: String)
    case terminalSubscribe(sessionId: String)
    case terminalUnsubscribe(sessionId: String)
    case ping

    var json: [String: Any] {
        switch self {
        case .auth(let deviceId, let token):
            return ["type": "auth", "deviceId": deviceId, "token": token]
        case .ptyWrite(let sessionId, let data):
            return ["type": "pty:write", "sessionId": sessionId, "data": data]
        case .sessionRename(let id, let title):
            return ["type": "session:rename", "id": id, "title": title]
        case .sessionBacklog(let id):
            return ["type": "session:backlog", "id": id]
        case .sessionRestore(let id):
            return ["type": "session:restore", "id": id]
        case .sessionSetActive(let id):
            return ["type": "session:setActive", "id": id]
        case .workspaceSwitch(let id):
            return ["type": "workspace:switch", "id": id]
        case .planRequest(let sessionId, let filename):
            return ["type": "plan:request", "sessionId": sessionId, "filename": filename]
        case .terminalSubscribe(let sessionId):
            return ["type": "terminal:subscribe", "sessionId": sessionId]
        case .terminalUnsubscribe(let sessionId):
            return ["type": "terminal:unsubscribe", "sessionId": sessionId]
        case .ping:
            return ["type": "ping"]
        }
    }
}

struct SnapshotMessage {
    let sessions: [Session]
    let workspaces: [Workspace]
    let activeSessionId: String?
    let activeWorkspaceId: String
}

struct SyncNotification {
    let sessionId: String
    let kind: String  // "waiting", "done", "error"
    let title: String
    let body: String
}

// MARK: - Delegate

protocol SyncClientDelegate: AnyObject {
    func syncClientDidConnect(_ client: SyncClient)
    func syncClientDidDisconnect(_ client: SyncClient)
    func syncClient(_ client: SyncClient, didReceiveSnapshot snapshot: SnapshotMessage)
    func syncClient(_ client: SyncClient, didUpdateSession id: String, changes: SessionChanges)
    func syncClient(_ client: SyncClient, didAddSession session: Session)
    func syncClient(_ client: SyncClient, didRemoveSession id: String)
    func syncClient(_ client: SyncClient, didReceiveTerminalOutput id: String, lines: [String])
    func syncClient(_ client: SyncClient, didReceiveWorkspaceUpdate workspaces: [Workspace], activeWorkspaceId: String)
    func syncClient(_ client: SyncClient, didReceiveNotification notification: SyncNotification)
    func syncClient(_ client: SyncClient, didReceivePlanContent sessionId: String, filename: String, content: String)
}

// MARK: - Client

final class SyncClient: NSObject {
    let host: String
    let port: Int
    let deviceToken: String
    weak var delegate: SyncClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: Timer?
    private let deviceId: String

    init(host: String, port: Int, deviceToken: String) {
        self.host = host
        self.port = port
        self.deviceToken = deviceToken
        // Stable device ID persisted across sessions
        if let saved = UserDefaults.standard.string(forKey: "airport_device_id") {
            self.deviceId = saved
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "airport_device_id")
            self.deviceId = id
        }
        super.init()
    }

    func connect() {
        let url = URL(string: "ws://\(host):\(port)")!
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Authenticate
        send(.auth(deviceId: deviceId, token: deviceToken))

        // Start receiving
        receiveMessage()

        // Ping every 25 seconds to keep connection alive
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.send(.ping)
        }
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONSerialization.data(withJSONObject: message.json) else { return }
        let string = String(data: data, encoding: .utf8) ?? ""
        webSocketTask?.send(.string(string)) { _ in }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage() // Continue receiving

            case .failure:
                DispatchQueue.main.async {
                    self.delegate?.syncClientDidDisconnect(self)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch type {
            case "snapshot":
                guard let sessionsData = json["sessions"],
                      let workspacesData = json["workspaces"],
                      let sessionsJSON = try? JSONSerialization.data(withJSONObject: sessionsData),
                      let workspacesJSON = try? JSONSerialization.data(withJSONObject: workspacesData),
                      let sessions = try? JSONDecoder().decode([Session].self, from: sessionsJSON),
                      let workspaces = try? JSONDecoder().decode([Workspace].self, from: workspacesJSON)
                else { return }

                let snapshot = SnapshotMessage(
                    sessions: sessions,
                    workspaces: workspaces,
                    activeSessionId: json["activeSessionId"] as? String,
                    activeWorkspaceId: json["activeWorkspaceId"] as? String ?? "default"
                )
                self.delegate?.syncClient(self, didReceiveSnapshot: snapshot)

            case "session:update":
                guard let id = json["id"] as? String,
                      let changesData = json["changes"],
                      let changesJSON = try? JSONSerialization.data(withJSONObject: changesData),
                      let changes = try? JSONDecoder().decode(SessionChanges.self, from: changesJSON)
                else { return }
                self.delegate?.syncClient(self, didUpdateSession: id, changes: changes)

            case "session:add":
                guard let sessionData = json["session"],
                      let sessionJSON = try? JSONSerialization.data(withJSONObject: sessionData),
                      let session = try? JSONDecoder().decode(Session.self, from: sessionJSON)
                else { return }
                self.delegate?.syncClient(self, didAddSession: session)

            case "session:remove":
                guard let id = json["id"] as? String else { return }
                self.delegate?.syncClient(self, didRemoveSession: id)

            case "terminal:output":
                guard let id = json["id"] as? String,
                      let lines = json["lines"] as? [String]
                else { return }
                self.delegate?.syncClient(self, didReceiveTerminalOutput: id, lines: lines)

            case "workspace:update":
                guard let workspacesData = json["workspaces"],
                      let workspacesJSON = try? JSONSerialization.data(withJSONObject: workspacesData),
                      let workspaces = try? JSONDecoder().decode([Workspace].self, from: workspacesJSON),
                      let activeId = json["activeWorkspaceId"] as? String
                else { return }
                self.delegate?.syncClient(self, didReceiveWorkspaceUpdate: workspaces, activeWorkspaceId: activeId)

            case "notification":
                guard let sessionId = json["sessionId"] as? String,
                      let kind = json["kind"] as? String,
                      let title = json["title"] as? String,
                      let body = json["body"] as? String
                else { return }
                let notification = SyncNotification(sessionId: sessionId, kind: kind, title: title, body: body)
                self.delegate?.syncClient(self, didReceiveNotification: notification)

            case "plan:content":
                guard let sessionId = json["sessionId"] as? String,
                      let filename = json["filename"] as? String,
                      let content = json["content"] as? String
                else { return }
                self.delegate?.syncClient(self, didReceivePlanContent: sessionId, filename: filename, content: content)

            case "pong":
                break

            default:
                break
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SyncClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.delegate?.syncClientDidConnect(self)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.delegate?.syncClientDidDisconnect(self)
        }
    }
}
