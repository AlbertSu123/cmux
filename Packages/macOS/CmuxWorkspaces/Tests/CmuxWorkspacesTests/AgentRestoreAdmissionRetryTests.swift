import Testing
@testable import CmuxWorkspaces

@MainActor
struct AgentRestoreAdmissionRetryTests {
    @Test func transientOwnershipIsRetriedUntilLaunchIsAdmitted() async {
        var scans = 0
        var launches = 0
        let admitted = await AgentRestoreAdmissionRetry.run(maximumAttempts: 4, pause: {}) {
            scans += 1
            guard scans == 3 else { return false }
            launches += 1
            return true
        }
        #expect(admitted)
        #expect(scans == 3)
        #expect(launches == 1)
    }

    @Test func persistentConflictExhaustsBudgetWithoutLaunching() async {
        var scans = 0
        let admitted = await AgentRestoreAdmissionRetry.run(maximumAttempts: 3, pause: {}) {
            scans += 1
            return false
        }
        #expect(!admitted)
        #expect(scans == 3)
    }

    @Test func cancellationDuringWaitNeverRunsAnotherAdmission() async {
        var scans = 0
        let task = Task { @MainActor in
            await AgentRestoreAdmissionRetry.run(maximumAttempts: 4, pause: {
                throw CancellationError()
            }) {
                scans += 1
                return false
            }
        }
        #expect(await task.value == false)
        #expect(scans == 1)
    }
}
