#!/usr/bin/env python3
"""Exercise the tagged Debug app's existing Command-click test harness."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def wait_json(path, predicate, process, timeout=45):
    deadline = time.monotonic() + timeout
    latest = {}
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Test app exited: {process.returncode}")
        try:
            latest = json.loads(path.read_text())
            if predicate(latest):
                return latest
        except (OSError, ValueError):
            pass
        time.sleep(0.1)
    raise RuntimeError(f"Harness timeout: {latest}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--open-system", action="store_true")
    args = parser.parse_args()
    import plistlib
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"].endswith(".installed-vnc-links"), "Only the isolated tagged app is allowed"
    binary = args.app / "Contents/MacOS" / info["CFBundleExecutable"]
    cases = [("log", "vnc://100.77.228.53"), ("osc8", "vnc://100.77.228.53")]
    if not args.open_system:
        cases += [("log", "VNC://remote.example.com:5901"), ("log", "vnc://admin@mac3.local:5900"), ("log", "vnc://[::1]:5900")]
    for mode, destination in cases:
        root = Path(tempfile.mkdtemp(prefix="cmux-vnc-click-"))
        manifest, command, capture = [root / name for name in ("setup.json", "command.json", "open.log")]
        command.write_text("{}")
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CMUX_", "GHOSTTY_"))}
        env.update({
            "CMUX_TAG": "installed-vnc-links",
            "CMUX_UI_TEST_MODE": "1",
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_SETUP": "1",
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_PATH": str(manifest),
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_COMMAND_PATH": str(command),
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_FIXTURE_DIR": str(root),
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_FILE_NAME": "VNC",
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_DISPLAY_MODE": "raw",
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_LINE_FORMAT": mode,
            "CMUX_UI_TEST_TERMINAL_CMD_CLICK_URL": destination,
        })
        if not args.open_system:
            env["CMUX_UI_TEST_CAPTURE_OPEN_URL_PATH"] = str(capture)
        with (root / "app.log").open("w") as log:
            process = subprocess.Popen([str(binary)], env=env, stdout=log, stderr=log)
            try:
                wait_json(manifest, lambda p: p.get("ready") == "1", process)
                request_id = str(uuid.uuid4())
                command.write_text(json.dumps({"id": request_id, "action": "stationary_cmd_click_token"}))
                result = wait_json(manifest, lambda p: p.get("lastCommandId") == request_id, process)
                if not args.open_system:
                    opened = capture.read_text().splitlines() if capture.exists() else []
                    assert opened == [destination], (mode, destination, opened, result)
                    print(f"PASS {mode}: {destination}", flush=True)
                else:
                    print(f"SYSTEM OPEN ATTEMPT {mode}: {destination}; inspect Screen Sharing. Evidence: {root}", flush=True)
            finally:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    main()
