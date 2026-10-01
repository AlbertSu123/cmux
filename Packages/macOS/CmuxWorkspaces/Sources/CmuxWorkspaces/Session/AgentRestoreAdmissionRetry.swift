/// Rechecks startup ownership while prior agent processes finish shutting down.
/// Every attempt must perform its own fresh ownership and session-identity checks.
@MainActor
public enum AgentRestoreAdmissionRetry {
    /// Attempts a deferred startup restore makes while the live agent index is
    /// still settling (one attempt per `pause`, 500 ms by default, so about a
    /// minute). Codex verification can stay unavailable for seconds while
    /// other Codex processes hold its state database around a relaunch;
    /// waiting costs nothing because nothing launches until the index is
    /// complete, and giving up early strands the tab at a shell.
    public static let startupIndexSettleMaximumAttempts = 120
    /// Retries an inconclusive admission without ever treating elapsed time as permission.
    /// Returns false on cancellation or exhaustion so the owner can retain manual restore.
    public static func run(
        maximumAttempts: Int = 12,
        pause: @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(500))
        },
        attempt: @MainActor () async -> Bool
    ) async -> Bool {
        guard maximumAttempts > 0 else { return false }
        for number in 0..<maximumAttempts {
            guard !Task.isCancelled else { return false }
            if await attempt() { return !Task.isCancelled }
            guard number + 1 < maximumAttempts else { break }
            do { try await pause() } catch { return false }
        }
        return false
    }
}
