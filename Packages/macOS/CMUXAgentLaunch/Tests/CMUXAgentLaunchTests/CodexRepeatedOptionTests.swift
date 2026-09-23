import CMUXAgentLaunch
import Testing

/// codex's `resume` subcommand rejects `--sandbox`, `--ask-for-approval`,
/// `--model` and `--profile` when any of them is given twice, while `-c`
/// repeats freely. A captured argv can carry a pair twice: a shell wrapper
/// such as `codex() { command codex -s danger-full-access -a never "$@"; }`
/// prepends its defaults ahead of a `resume` whose preserved options already
/// hold the same pair. codex accepted that launch (one pair on the top-level
/// command, one on the subcommand), but replaying both after `resume` fails.
@Suite("Codex repeated options")
struct CodexRepeatedOptionTests {
    private let updateCheck = ["-c", "check_for_update_on_startup=false"]

    @Test("Captured wrapper-plus-resume argv keeps one sandbox and approval pair")
    func captureCollapsesWrapperDefaults() {
        #expect(
            AgentLaunchSanitizer.sanitizedLaunchArguments(
                [
                    "/opt/bin/codex", "-s", "danger-full-access", "-a", "never",
                    "resume", "01a0ac78-7972-79b3-b6a9-a2f329e7addb",
                    "-c", "check_for_update_on_startup=false",
                    "-s", "danger-full-access", "-a", "never",
                    "-c", "model_provider=\"router\"",
                ],
                launcher: "codex",
                fallbackKind: "codex"
            ) == [
                "/opt/bin/codex",
                "-c", "check_for_update_on_startup=false",
                "-s", "danger-full-access", "-a", "never",
                "-c", "model_provider=\"router\"",
            ]
        )
    }

    @Test("Resume argv from a doubled record carries each option once, last value winning")
    func resumeCollapsesDoubledRecord() {
        #expect(
            AgentResumeArgv().builtInKind(
                kind: "codex",
                sessionId: "SID",
                executablePath: nil,
                arguments: [
                    "codex", "-s", "workspace-write", "-a", "on-request",
                    "--sandbox=danger-full-access", "-a", "never",
                    "--model", "a", "-m", "b",
                ]
            ) == ["codex", "resume", "SID"] + updateCheck + [
                "--sandbox=danger-full-access", "-a", "never", "-m", "b",
            ]
        )
    }

    @Test("Repeatable config overrides are untouched")
    func configOverridesStayRepeated() {
        #expect(
            AgentResumeArgv().builtInKind(
                kind: "codex",
                sessionId: "SID",
                executablePath: nil,
                arguments: ["codex", "-c", "a=1", "-c", "b=2", "--add-dir", "/x", "--add-dir", "/y"]
            ) == ["codex", "resume", "SID"] + updateCheck + ["-c", "a=1", "-c", "b=2", "--add-dir", "/x", "--add-dir", "/y"]
        )
    }
}
