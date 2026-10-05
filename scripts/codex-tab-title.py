#!/usr/bin/env python3
"""Keep the opening Codex query title in cmux and/or tmux."""
import os
import fcntl
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import unicodedata


def main():
    title = " ".join("".join(c for c in " ".join(sys.argv[1:])
        if not unicodedata.category(c).startswith("C")).split())[:80]
    if not title:
        return 0
    env = os.environ
    commands = []
    surface = env.get("CMUX_SURFACE_ID")
    workspace = env.get("CMUX_WORKSPACE_ID")
    cli = env.get("CMUX_BUNDLED_CLI_PATH")
    if not cli or not os.access(cli, os.X_OK):
        cli = shutil.which("cmux")
    if surface and workspace and cli:
        commands.append([cli, "rename-tab", "--workspace", workspace,
                         "--surface", surface, title])
    tmux = shutil.which("tmux")
    if env.get("TMUX") and env.get("TMUX_PANE") and tmux:
        commands.append([tmux, "rename-window", "-t", env["TMUX_PANE"], title])
    # Keep the first query's title across later turns and app restarts.
    # Explicit user renames remain available through cmux rename-tab.
    identity = surface or env.get("TMUX_PANE")
    if not identity or not commands:
        return 0
    state_dir = Path(env.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "codex-tab-titles"
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    context = workspace or env.get("TMUX", "")
    key = hashlib.sha256((context + ":" + identity).encode()).hexdigest()
    with (state_dir / key).open("a+") as state:
        fcntl.flock(state, fcntl.LOCK_EX)
        state.seek(0)
        if state.read().strip():
            return 0
        applied = False
        for command in commands:
            try:
                subprocess.run(command, check=True, timeout=5, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
                applied = True
            except (OSError, subprocess.SubprocessError):
                pass
        if applied:
            state.write(title + "\n")
            state.flush()
    return 0



if __name__ == "__main__":
    sys.exit(main())
