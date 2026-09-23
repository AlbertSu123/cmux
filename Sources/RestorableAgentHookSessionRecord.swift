import Foundation

struct RestorableAgentHookSessionRecord: Codable, Sendable {
    var sessionId: String
    var workspaceId: String
    var surfaceId: String
    var cwd: String?
    var transcriptPath: String?
    var pid: Int?
    /// Exact process-generation identity captured when the hook recorded `pid`.
    var pidStartSeconds: Int64?
    var pidStartMicroseconds: Int64?
    var launchCommand: AgentLaunchCommandSnapshot?
    /// Last hook-observed agent permission mode (e.g. Claude's `permission_mode`).
    var lastPermissionMode: String?
    var isRestorable: Bool?
    var agentLifecycle: AgentHibernationLifecycleState?
    /// Whether the agent's last turn ended with background work still live
    /// (a background task, scheduled wakeup, or child agent). The pane is idle
    /// for display; hibernation must not tear that work down.
    var hadPendingBackgroundWorkAtStop: Bool?
    var updatedAt: TimeInterval
}
