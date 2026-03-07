import Foundation

enum SessionStatus: String, Codable {
    case active
    case idle
    case standby
    case waitingForInput = "waiting-for-input"

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .idle: return "Idle"
        case .standby: return "Standby"
        case .waitingForInput: return "Waiting"
        }
    }

    var color: SessionColor {
        switch self {
        case .active: return .green
        case .idle: return .gray
        case .standby: return .yellow
        case .waitingForInput: return .red
        }
    }
}

enum SessionColor {
    case green, yellow, red, gray

    var hex: String {
        switch self {
        case .green: return "#a6e3a1"
        case .yellow: return "#f9e2af"
        case .red: return "#f38ba8"
        case .gray: return "#6c7086"
        }
    }
}

struct Session: Identifiable, Codable {
    let id: String
    var title: String
    var customTitle: Bool
    var status: SessionStatus
    var processName: String
    var isStandby: Bool
    var lastOutputAt: Double
    var hookMessage: String
    var hookDone: Bool
    var waitingQuestion: String
    var gitRepo: String
    var gitBranch: String
    var colorIndex: Int
    var backlog: Bool
    var cwd: String
    var workspaceId: String
    var hasPlans: Bool

    // Local-only (not from server)
    var planContent: String?
    var planFilename: String?

    enum CodingKeys: String, CodingKey {
        case id, title, customTitle, status, processName, isStandby
        case lastOutputAt, hookMessage, hookDone, waitingQuestion
        case gitRepo, gitBranch, colorIndex, backlog, cwd, workspaceId, hasPlans
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !gitRepo.isEmpty { return gitRepo }
        return cwd.components(separatedBy: "/").last ?? "Session"
    }

    var statusText: String {
        if hookDone { return "Done" }
        if !hookMessage.isEmpty { return hookMessage }
        if !waitingQuestion.isEmpty { return "Needs input" }
        return status.displayName
    }

    var needsAttention: Bool {
        hookDone || status == .waitingForInput || !waitingQuestion.isEmpty
    }

    mutating func apply(_ changes: SessionChanges) {
        if let v = changes.title { title = v }
        if let v = changes.customTitle { customTitle = v }
        if let v = changes.status { status = v }
        if let v = changes.processName { processName = v }
        if let v = changes.isStandby { isStandby = v }
        if let v = changes.lastOutputAt { lastOutputAt = v }
        if let v = changes.hookMessage { hookMessage = v }
        if let v = changes.hookDone { hookDone = v }
        if let v = changes.waitingQuestion { waitingQuestion = v }
        if let v = changes.gitRepo { gitRepo = v }
        if let v = changes.gitBranch { gitBranch = v }
        if let v = changes.colorIndex { colorIndex = v }
        if let v = changes.backlog { backlog = v }
        if let v = changes.cwd { cwd = v }
        if let v = changes.workspaceId { workspaceId = v }
        if let v = changes.hasPlans { hasPlans = v }
    }
}

struct SessionChanges: Codable {
    var title: String?
    var customTitle: Bool?
    var status: SessionStatus?
    var processName: String?
    var isStandby: Bool?
    var lastOutputAt: Double?
    var hookMessage: String?
    var hookDone: Bool?
    var waitingQuestion: String?
    var gitRepo: String?
    var gitBranch: String?
    var colorIndex: Int?
    var backlog: Bool?
    var cwd: String?
    var workspaceId: String?
    var hasPlans: Bool?
}

struct Workspace: Identifiable, Codable {
    let id: String
    var name: String
}
