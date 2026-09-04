import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Verifies that quitting an agent leaves its tab restorable.
///
/// The Claude `SessionEnd` hook clears the surface resume binding. Removing it
/// outright orphaned the tab: it kept the agent's auto-generated title while
/// losing the only record of which checkpoint to resume, even though the
/// transcript was still on disk.
@MainActor
@Suite(.serialized)
struct SurfaceResumeSessionEndRetentionTests {
    private func agentHookBinding(
        checkpointId: String = "ended-session",
        source: String = "agent-hook"
    ) -> SurfaceResumeBindingSnapshot {
        SurfaceResumeBindingSnapshot(
            name: "Claude Code",
            kind: "claude",
            command: "claude --resume \(checkpointId)",
            cwd: "/tmp/agent-cwd",
            checkpointId: checkpointId,
            source: source,
            autoResume: true,
            approvalPolicy: .auto,
            updatedAt: 10
        )
    }

    @Test
    func agentSessionEndKeepsBindingButDisablesAutomaticResume() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelID = try #require(workspace.focusedPanelId)
        #expect(workspace.setSurfaceResumeBinding(agentHookBinding(), panelId: panelID))

        #expect(workspace.clearSurfaceResumeBinding(panelId: panelID, agentSessionEnded: true))

        let retained = try #require(workspace.surfaceResumeBinding(panelId: panelID))
        #expect(retained.checkpointId == "ended-session")
        #expect(retained.autoResume == false)
        #expect(retained.approvalPolicy == .manual)
        #expect(!retained.allowsAutomaticResume)
        #expect(!retained.requiresPromptApproval)
    }

    @Test
    func clearWithoutSessionEndStillRemovesBinding() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelID = try #require(workspace.focusedPanelId)
        #expect(workspace.setSurfaceResumeBinding(agentHookBinding(), panelId: panelID))

        #expect(workspace.clearSurfaceResumeBinding(panelId: panelID))

        #expect(workspace.surfaceResumeBinding(panelId: panelID) == nil)
    }

    @Test
    func agentSessionEndDoesNotRetainNonAgentHookBinding() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelID = try #require(workspace.focusedPanelId)
        #expect(workspace.setSurfaceResumeBinding(
            agentHookBinding(source: "cli"),
            panelId: panelID
        ))

        #expect(workspace.clearSurfaceResumeBinding(panelId: panelID, agentSessionEnded: true))

        #expect(workspace.surfaceResumeBinding(panelId: panelID) == nil)
    }

    @Test
    func agentSessionEndDoesNotRetainBindingWithoutCheckpoint() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelID = try #require(workspace.focusedPanelId)
        let uncheckpointed = SurfaceResumeBindingSnapshot(
            kind: "claude",
            command: "claude",
            cwd: "/tmp/agent-cwd",
            source: "agent-hook",
            autoResume: true,
            approvalPolicy: .auto,
            updatedAt: 10
        )
        #expect(workspace.setSurfaceResumeBinding(uncheckpointed, panelId: panelID))

        #expect(workspace.clearSurfaceResumeBinding(panelId: panelID, agentSessionEnded: true))

        #expect(workspace.surfaceResumeBinding(panelId: panelID) == nil)
    }
}
