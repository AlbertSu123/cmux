import Dispatch
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A Codex turn that dies with its process (cmux relaunch or crash) never
/// reports Stop, so it used to stay on the session's active-turn stack. Every
/// later prompt in that pane was then classified as a nested subagent prompt
/// and its visible running state was suppressed: the agent worked while the
/// pane showed idle. Turns are owned by a process generation; a prompt from a
/// new generation must retire the dead generation's turns.
@Suite(.serialized)
struct CodexPromptTurnProcessGenerationTests {
    private struct Harness {
        let support: ClaudeHookSurfaceResolutionSwiftTests
        let context: ClaudeHookSurfaceResolutionSwiftTests.ClaudeHookContext
        let handled: DispatchSemaphore
        let environment: [String: String]
        let sessionId: String
    }

    @Test
    func promptFromNewProcessGenerationRetiresTurnsOfDeadProcess() throws {
        let harness = try makeHarness(name: "codex-turn-owner-relaunch")
        defer { harness.context.cleanup() }
        try runHook(harness, subcommand: "session-start", input: sessionStartPayload(harness))
        try runHook(harness, subcommand: "prompt-submit", input: promptPayload(harness, turnId: "turn-before-relaunch"))

        // No Stop for the first turn: the agent process died with cmux. The
        // resumed agent is a new process generation with its own invocation
        // token; its session-start re-keys the turn ledger the way the app's
        // restore request does for a `codex resume`.
        var relaunchedEnvironment = harness.environment
        relaunchedEnvironment["CMUX_CODEX_PID"] = "4343"
        relaunchedEnvironment["CMUX_CODEX_HOOK_PID"] = "4343"
        relaunchedEnvironment["CMUX_CODEX_INVOCATION_ID"] = "codex-owner-relaunched"
        try runHook(
            harness,
            subcommand: "session-start",
            input: sessionStartPayload(harness),
            environment: relaunchedEnvironment
        )
        let beforePrompt = harness.context.state.snapshot().count
        try runHook(
            harness,
            subcommand: "prompt-submit",
            input: promptPayload(harness, turnId: "turn-after-relaunch"),
            environment: relaunchedEnvironment
        )
        let commands = Array(harness.context.state.snapshot().dropFirst(beforePrompt))
        #expect(
            commands.contains { $0.hasPrefix("set_status codex Running ") },
            "A prompt from the resumed process must show the pane running: \(commands)"
        )

        let record = try sessionRecord(harness)
        #expect(record["activePromptTurnIds"] as? [String] == ["turn-after-relaunch"])
        #expect(record["activePromptDepth"] as? Int == 1)
        #expect((record["terminalPromptTurnIds"] as? [String] ?? []).contains("turn-before-relaunch"))
    }

    @Test
    func promptFromSameProcessGenerationStaysNested() throws {
        let harness = try makeHarness(name: "codex-turn-owner-same-process")
        defer { harness.context.cleanup() }
        try runHook(harness, subcommand: "session-start", input: sessionStartPayload(harness))
        try runHook(harness, subcommand: "prompt-submit", input: promptPayload(harness, turnId: "outer-turn"))

        let beforePrompt = harness.context.state.snapshot().count
        try runHook(harness, subcommand: "prompt-submit", input: promptPayload(harness, turnId: "inner-turn"))
        let commands = Array(harness.context.state.snapshot().dropFirst(beforePrompt))
        #expect(
            !commands.contains { $0.hasPrefix("set_status codex Running ") },
            "A nested prompt from the live process must stay hidden: \(commands)"
        )

        let record = try sessionRecord(harness)
        #expect(record["activePromptTurnIds"] as? [String] == ["outer-turn", "inner-turn"])
        #expect(record["activePromptDepth"] as? Int == 2)
    }

    private func makeHarness(name: String) throws -> Harness {
        let support = ClaudeHookSurfaceResolutionSwiftTests()
        let context = try support.makeClaudeHookContext(name: name)
        let handled = support.startClaudeSurfaceResolutionServer(
            context: context,
            surfaces: [(context.surfaceId, "surface:1", true)],
            ttyName: "ttys-\(name)",
            ttySurfaceId: context.surfaceId
        )
        let environment = [
            "HOME": context.root.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "PWD": context.root.path,
            "CMUX_SOCKET_PATH": context.socketPath,
            "CMUX_WORKSPACE_ID": context.workspaceId,
            "CMUX_SURFACE_ID": context.surfaceId,
            "CMUX_CLI_TTY_NAME": "ttys-\(name)",
            "CMUX_CODEX_PID": "4242",
            "CMUX_CODEX_HOOK_PID": "4242",
            "CMUX_CODEX_INVOCATION_ID": "codex-owner-\(name)",
            "CMUX_AGENT_HOOK_STATE_DIR": context.root.path,
            "CMUX_CODEX_TURN_LEDGER_PATH": context.root.appendingPathComponent("codex-turn-ledger.json").path,
            "CMUX_CLI_SENTRY_DISABLED": "1",
            "CMUX_AGENT_LAUNCH_KIND": "codex",
            "CMUX_AGENT_LAUNCH_EXECUTABLE": "/usr/local/bin/codex",
            "CMUX_AGENT_LAUNCH_CWD": context.root.path,
        ]
        return Harness(
            support: support,
            context: context,
            handled: handled,
            environment: environment,
            sessionId: "session-\(name)"
        )
    }

    private func runHook(
        _ harness: Harness,
        subcommand: String,
        input: String,
        environment: [String: String]? = nil
    ) throws {
        let result = harness.support.runProcess(
            executablePath: harness.context.cliPath,
            arguments: ["hooks", "codex", subcommand],
            environment: environment ?? harness.environment,
            standardInput: input,
            timeout: 10
        )
        #expect(harness.handled.wait(timeout: .now() + 10) == .success)
        harness.support.assertSuccessfulHook(result)
    }

    private func sessionRecord(_ harness: Harness) throws -> [String: Any] {
        let storeURL = harness.context.root.appendingPathComponent("codex-hook-sessions.json")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as? [String: Any]
        let sessions = saved?["sessions"] as? [String: Any]
        return try #require(sessions?[harness.sessionId] as? [String: Any])
    }

    private func sessionStartPayload(_ harness: Harness) -> String {
        #"{"session_id":"\#(harness.sessionId)","cwd":"\#(harness.context.root.path)","hook_event_name":"SessionStart"}"#
    }

    private func promptPayload(_ harness: Harness, turnId: String) -> String {
        #"{"session_id":"\#(harness.sessionId)","turn_id":"\#(turnId)","cwd":"\#(harness.context.root.path)","hook_event_name":"UserPromptSubmit"}"#
    }
}
