#!/usr/bin/env python3
"""Verify on-save injection and restoration in one running Debug cmux process."""
import argparse
import json
import os
import shlex
import subprocess
from pathlib import Path
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--tag', help='Also verify terminal state and creation; run inside this tagged app')
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / 'Sources/DevelopmentHotReload.swift'
    status_path = Path(tempfile.gettempdir()) / f'cmux-hot-reload-{args.pid}.json'
    initial = json.loads(status_path.read_text())
    assert initial['pid'] == args.pid

    def cli(*arguments):
        helper = source.parents[1] / 'scripts/cmux-debug-cli.sh'
        result = subprocess.run([str(helper), '--json', *arguments],
                                env={**os.environ, 'CMUX_TAG': args.tag},
                                capture_output=True, text=True, timeout=20, check=True)
        return json.loads(result.stdout)

    scope = []

    def terminal_state():
        return [(s['ref'], s['selected']) for s in cli('list-pane-surfaces', *scope)['surfaces']]

    if args.tag:
        assert initial['bundleId'] == 'com.cmuxterm.app.debug.' + args.tag.replace('-', '.')
        initial_pane = cli('list-pane-surfaces')
        scope = ['--workspace', initial_pane['workspace_ref'], '--pane', initial_pane['pane_ref']]
        before = terminal_state()
    original = source.read_text()
    old, new = 'cmux-hot-reload-v1', 'cmux-hot-reload-v2'
    assert original.count(old) == 1 and initial['probe'] == old

    def wait_for(value, previous_revision):
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            os.kill(args.pid, 0)
            status = json.loads(status_path.read_text())
            if (status['pid'] == args.pid and status['probe'] == value
                    and status['revision'] > previous_revision):
                print(json.dumps(status), flush=True)
                return status
            time.sleep(0.2)
        raise TimeoutError(f'Running process did not inject {value}; last status: {status}')

    injected = None
    try:
        source.write_text(original.replace(old, new))
        injected = wait_for(new, initial['revision'])
    finally:
        source.write_text(original)
    if injected:
        wait_for(old, injected['revision'])
        print(f'PASS: changed and restored live code in PID {args.pid}; no restart', flush=True)
        if args.tag:
            assert terminal_state() == before, f'Injection changed tabs/selection: {before} -> {terminal_state()}'
            destination = cli('new-surface', *scope, '--focus', 'false')
            created = destination['surface_ref']
            workspace = destination['workspace_ref']
            marker = Path(tempfile.gettempdir()) / f'cmux-hot-reload-terminal-{args.pid}.txt'
            marker.unlink(missing_ok=True)
            try:
                cli('send', '--workspace', workspace, '--surface', created,
                    "printf '%s' cmux-hot-reload-terminal-ok > " + shlex.quote(str(marker)) + "\n")
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    os.kill(args.pid, 0)
                    if marker.exists() and marker.read_text() == 'cmux-hot-reload-terminal-ok':
                        break
                    time.sleep(0.2)
                else:
                    raise TimeoutError('New terminal could not execute a shell command after injection')
            finally:
                cli('close-surface', '--workspace', workspace, '--surface', created)
                marker.unlink(missing_ok=True)
            deadline = time.monotonic() + 3
            after = terminal_state()
            while after != before and time.monotonic() < deadline:
                time.sleep(0.1)
                after = terminal_state()
            assert after == before, f'Terminal creation changed tabs/focus: {before} -> {after}'
            print('PASS: tabs and focus preserved; new terminal executed a shell command', flush=True)


if __name__ == '__main__':
    main()
