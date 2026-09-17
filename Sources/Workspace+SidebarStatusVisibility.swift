import CmuxSidebar
import Foundation

extension Workspace {
    func sidebarStatusEntriesVisibleForDisplay() -> [SidebarStatusEntry] {
        let visibleStructuredStatusKeys = visibleStructuredAgentStatusKeysByPanel()
        let entries = statusEntries.values.filter { entry in
            shouldDisplaySidebarStatusEntry(entry, visibleStructuredStatusKeys: visibleStructuredStatusKeys)
        }
        return Self.countingAgentTabs(
            in: entries,
            lifecycleStatesByPanelId: agentLifecycleStatesByPanelId.filter { panels[$0.key] != nil }
        )
    }

    /// Replaces the per-agent "Running" / "needs input" rows with one row per
    /// state that counts the tabs in it, so a workspace with three agents
    /// mid-turn reads "x3 running" instead of identical "Running" lines that
    /// don't say how many tabs are busy. Counts come from the per-tab
    /// lifecycle the hooks report, so they hold even when an agent never
    /// published a status row. Error rows and non-agent rows pass through.
    static func countingAgentTabs(
        in entries: [SidebarStatusEntry],
        lifecycleStatesByPanelId: [UUID: [String: AgentHibernationLifecycleState]]
    ) -> [SidebarStatusEntry] {
        var runningTabs = 0
        var needsInputTabs = 0
        var countedKeys = Set<String>()
        for states in lifecycleStatesByPanelId.values {
            let agentStates = states.filter { !AgentHibernationLifecycleStatusKeys.isManualKey($0.key) }
            if agentStates.values.contains(.needsInput) {
                needsInputTabs += 1
            } else if agentStates.values.contains(.running) {
                runningTabs += 1
            }
            for (key, lifecycle) in agentStates where lifecycle == .running || lifecycle == .needsInput {
                countedKeys.insert(key)
            }
        }
        guard runningTabs > 0 || needsInputTabs > 0 else { return entries }

        let agentEntries = entries.filter { AgentHibernationLifecycleStatusKeys.allowedStatusKeys.contains($0.key) }
        var result = entries.filter { entry in
            !countedKeys.contains(entry.key) || entry.icon == Self.agentErrorStatusIcon
        }
        let timestamp = agentEntries.map(\.timestamp).max() ?? Date()
        if needsInputTabs > 0 {
            result.append(SidebarStatusEntry(
                key: Self.countedNeedsInputStatusKey,
                value: String(localized: "sidebar.agentStatus.needsInputCount", defaultValue: "x\(needsInputTabs) needs input"),
                icon: "bell.fill",
                color: Self.agentStatusColor,
                priority: 100,
                timestamp: timestamp
            ))
        }
        if runningTabs > 0 {
            result.append(SidebarStatusEntry(
                key: Self.countedRunningStatusKey,
                value: String(localized: "sidebar.agentStatus.runningCount", defaultValue: "x\(runningTabs) running"),
                icon: "bolt.fill",
                color: Self.agentStatusColor,
                priority: agentEntries.map(\.priority).max() ?? 0,
                timestamp: timestamp
            ))
        }
        return result
    }

    static let countedRunningStatusKey = "cmux.agents.running"
    static let countedNeedsInputStatusKey = "cmux.agents.needsInput"
    /// The icon and color the hook CLI uses for agent status rows.
    private static let agentErrorStatusIcon = "exclamationmark.triangle.fill"
    private static let agentStatusColor = "#4C8DFF"

    private func shouldDisplaySidebarStatusEntry(
        _ entry: SidebarStatusEntry,
        visibleStructuredStatusKeys: Set<String>
    ) -> Bool {
        guard AgentHibernationLifecycleStatusKeys.allowedStatusKeys.contains(entry.key) else {
            return true
        }
        return visibleStructuredStatusKeys.contains(entry.key)
    }

    private func visibleStructuredAgentStatusKeysByPanel() -> Set<String> {
        var statusKeysByPanelId: [UUID: Set<String>] = [:]
        for (key, panelId) in agentPIDPanelIdsByKey
        where panels[panelId] != nil {
            let statusKey = agentStatusKey(forAgentPIDKey: key)
            guard AgentHibernationLifecycleStatusKeys.allowedStatusKeys.contains(statusKey),
                  statusEntries[statusKey] != nil else {
                continue
            }
            statusKeysByPanelId[panelId, default: []].insert(statusKey)
        }
        var visibleStatusKeys = Set<String>()
        for statusKeys in statusKeysByPanelId.values {
            let winningEntry = statusKeys.compactMap { statusEntries[$0] }.max {
                isSidebarStatusEntryLessCurrent($0, than: $1)
            }
            if let winningEntry {
                visibleStatusKeys.insert(winningEntry.key)
            }
        }

        for key in agentPIDs.keys where agentPIDPanelIdsByKey[key] == nil {
            let statusKey = agentStatusKey(forAgentPIDKey: key)
            guard AgentHibernationLifecycleStatusKeys.allowedStatusKeys.contains(statusKey),
                  statusEntries[statusKey] != nil else {
                continue
            }
            visibleStatusKeys.insert(statusKey)
        }

        return visibleStatusKeys
    }

    private func isSidebarStatusEntryLessCurrent(
        _ lhs: SidebarStatusEntry,
        than rhs: SidebarStatusEntry
    ) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.key > rhs.key
    }
}
