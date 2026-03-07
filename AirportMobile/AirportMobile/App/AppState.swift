import SwiftUI
import Combine

/// Root application state — observed by all views.
@Observable
final class AppState {
    // Connection
    var isConnected = false
    var hasSavedConnection = false
    var serverName = ""

    // Sessions
    var sessions: [Session] = []
    var activeSessionId: String?
    var workspaces: [Workspace] = []
    var activeWorkspaceId: String = "default"

    // Terminal output buffers (sessionId → lines)
    var terminalBuffers: [String: [String]] = [:]

    // Networking
    private(set) var syncClient: SyncClient?
    private(set) var bonjourBrowser: BonjourBrowser?

    init() {
        let saved = ConnectionStore.load()
        hasSavedConnection = saved != nil

        bonjourBrowser = BonjourBrowser()

        if let saved = saved {
            connect(host: saved.host, port: saved.port, deviceToken: saved.deviceToken)
        }
    }

    // MARK: - Connection

    func connect(host: String, port: Int, deviceToken: String) {
        let client = SyncClient(host: host, port: port, deviceToken: deviceToken)
        client.delegate = self
        client.connect()
        syncClient = client
    }

    func disconnect() {
        syncClient?.disconnect()
        syncClient = nil
        isConnected = false
        sessions = []
        workspaces = []
    }

    func clearSavedConnection() {
        ConnectionStore.clear()
        hasSavedConnection = false
        disconnect()
    }

    // MARK: - Computed

    var activeSessions: [Session] {
        sessions.filter { !$0.backlog && $0.workspaceId == activeWorkspaceId }
    }

    var backlogSessions: [Session] {
        sessions.filter { $0.backlog }
    }

    var waitingSessions: [Session] {
        sessions.filter { $0.status == .waitingForInput || $0.hookDone }
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeWorkspaceId }
    }

    // MARK: - Actions (sent to desktop)

    func sendQuickReply(sessionId: String, text: String) {
        syncClient?.send(.ptyWrite(sessionId: sessionId, data: text + "\n"))
    }

    func renameSession(id: String, title: String) {
        syncClient?.send(.sessionRename(id: id, title: title))
    }

    func moveToBacklog(id: String) {
        syncClient?.send(.sessionBacklog(id: id))
    }

    func restoreFromBacklog(id: String) {
        syncClient?.send(.sessionRestore(id: id))
    }

    func setActiveSession(id: String) {
        activeSessionId = id
        syncClient?.send(.sessionSetActive(id: id))
    }

    func switchWorkspace(id: String) {
        activeWorkspaceId = id
        syncClient?.send(.workspaceSwitch(id: id))
    }

    func subscribeTerminal(sessionId: String) {
        syncClient?.send(.terminalSubscribe(sessionId: sessionId))
    }

    func unsubscribeTerminal(sessionId: String) {
        syncClient?.send(.terminalUnsubscribe(sessionId: sessionId))
    }

    func requestPlan(sessionId: String, filename: String) {
        syncClient?.send(.planRequest(sessionId: sessionId, filename: filename))
    }
}

// MARK: - SyncClientDelegate

extension AppState: SyncClientDelegate {
    func syncClientDidConnect(_ client: SyncClient) {
        isConnected = true
    }

    func syncClientDidDisconnect(_ client: SyncClient) {
        isConnected = false
        // Auto-reconnect after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            if !isConnected && hasSavedConnection {
                client.connect()
            }
        }
    }

    func syncClient(_ client: SyncClient, didReceiveSnapshot snapshot: SnapshotMessage) {
        sessions = snapshot.sessions
        workspaces = snapshot.workspaces
        activeSessionId = snapshot.activeSessionId
        activeWorkspaceId = snapshot.activeWorkspaceId
    }

    func syncClient(_ client: SyncClient, didUpdateSession id: String, changes: SessionChanges) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].apply(changes)
    }

    func syncClient(_ client: SyncClient, didAddSession session: Session) {
        sessions.append(session)
    }

    func syncClient(_ client: SyncClient, didRemoveSession id: String) {
        sessions.removeAll { $0.id == id }
        terminalBuffers.removeValue(forKey: id)
    }

    func syncClient(_ client: SyncClient, didReceiveTerminalOutput id: String, lines: [String]) {
        var buf = terminalBuffers[id, default: []]
        buf.append(contentsOf: lines)
        if buf.count > 500 {
            buf = Array(buf.suffix(500))
        }
        terminalBuffers[id] = buf
    }

    func syncClient(_ client: SyncClient, didReceiveWorkspaceUpdate workspaces: [Workspace], activeWorkspaceId: String) {
        self.workspaces = workspaces
        self.activeWorkspaceId = activeWorkspaceId
    }

    func syncClient(_ client: SyncClient, didReceiveNotification notification: SyncNotification) {
        // Schedule local notification
        NotificationManager.scheduleLocal(
            title: notification.title,
            body: notification.body,
            sessionId: notification.sessionId
        )
    }

    func syncClient(_ client: SyncClient, didReceivePlanContent sessionId: String, filename: String, content: String) {
        // Store plan content for viewing
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].planContent = content
            sessions[idx].planFilename = filename
        }
    }
}
