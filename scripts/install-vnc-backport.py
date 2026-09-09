#!/usr/bin/env python3
"""Install the tested local VNC backport without restarting the user's app."""
from pathlib import Path
import datetime
import plistlib
import shutil
import subprocess
import tempfile
import zlib

repo = Path(__file__).resolve().parent.parent
installed = Path("/Applications/cmux (Albert's version).app")
built = Path.home() / "Library/Developer/Xcode/DerivedData/cmux-installed-vnc-links/Build/Products/Debug/cmux DEV installed-vnc-links.app"
stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
stage = Path(tempfile.mkdtemp(prefix="cmux-vnc-install-"))
ready = stage / installed.name
backup = installed.with_name(f"cmux (Albert's version) backup-vnc-terminal-{stamp}.app")


def run(*args):
    return subprocess.check_output(args, text=True).strip()


old = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
assert old["CMUXInstalledCommit"] == "17aea6575fb79df443db156e7f6fab5bcd5a454f", "Installed version changed; do not overwrite"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(built)], check=True)
subprocess.run(["cp", "-cRp", str(built), str(ready)], check=True)
plist = ready / "Contents/Info.plist"
info = plistlib.loads(plist.read_bytes())
for key in ("CFBundleIdentifier", "CFBundleName", "CFBundleDisplayName", "CFBundleURLTypes", "CMUXSidebarExtensionPointIdentifier"):
    if key in old:
        info[key] = old[key]
info["CMUXInstalledCommit"] = run("git", "-C", str(repo), "rev-parse", "HEAD")
info["CMUXInstalledGhosttyCommit"] = run("git", "-C", str(repo / "ghostty"), "rev-parse", "HEAD")
info.pop("LSEnvironment", None)
info.pop("SUFeedURL", None)
info["SUEnableAutomaticChecks"] = False
plist.write_bytes(plistlib.dumps(info))
extensions = ready / "Contents/Extensions"
if extensions.exists():
    for point in extensions.glob("*.appextensionpoint"):
        point.unlink()
    for point in (installed / "Contents/Extensions").glob("*.appextensionpoint"):
        shutil.copy2(point, extensions / point.name)
relative = Path("markdown-viewer/webviews-app/chunks/agentSessionSurface.mjs")
source = repo / "Resources" / relative
asset = ready / "Contents/Resources" / relative
asset.with_name(asset.name + ".deflate").write_bytes(zlib.compress(source.read_bytes(), 9))
entitlements = stage / "entitlements.plist"
entitlements.write_bytes(plistlib.dumps({"com.apple.security.get-task-allow": True}))
subprocess.run(["codesign", "--force", "-s", "Apple Development: Albert Su (H559K3Z4TU)", "--entitlements", str(entitlements), str(ready)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(ready)], check=True)
assert plistlib.loads((installed / "Contents/Info.plist").read_bytes())["CMUXInstalledCommit"] == old["CMUXInstalledCommit"]
installed.rename(backup)
try:
    ready.rename(installed)
except Exception:
    backup.rename(installed)
    raise
print(f"Installed: {installed}\nBackup: {backup}\nSource: {info['CMUXInstalledCommit']}\nGhostty: {info['CMUXInstalledGhosttyCommit']}\nNo restart performed.")
