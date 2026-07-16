#!/usr/bin/env bash
# Update "/Applications/cmux (Albert's version).app" from this fork.
#
# Pipeline: fetch upstream -> rebase albert/patches onto origin/main ->
# sync submodules + prebuilt GhosttyKit -> tagged Debug build -> rebadge the
# app to Albert's install identity -> sign -> install with a timestamped
# backup -> push the branch to the fork.
#
# The install identity is the original remote-click tagged build this app
# grew out of: keeping the bundle id preserves session state, settings, and
# closed-item history across updates. The rebadge also strips the tagged
# build's LSEnvironment (localhost dev endpoints) and Sparkle feed (upstream
# releases would overwrite this fork's patches).
#
# Run from anywhere; operates on the repo containing this script.
# Pass --no-push to skip pushing to the fork.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

BRANCH="albert/patches"
UPSTREAM_REMOTE="origin"
FORK_REMOTE="fork"
BUILD_TAG="albert-update"
INSTALL_APP="/Applications/cmux (Albert's version).app"
INSTALL_NAME="cmux (Albert's version)"
INSTALL_BUNDLE_ID="com.cmuxterm.app.debug.remote.click"
SIGN_IDENTITY="Apple Development: Albert Su (H559K3Z4TU)"

PUSH=1
if [[ "${1:-}" == "--no-push" ]]; then PUSH=0; fi

cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty; commit or stash first" >&2
  exit 1
fi
if [[ "$(git rev-parse --abbrev-ref HEAD)" != "$BRANCH" ]]; then
  echo "error: expected to be on $BRANCH (currently $(git rev-parse --abbrev-ref HEAD))" >&2
  exit 1
fi

echo "==> Fetching $UPSTREAM_REMOTE"
git fetch "$UPSTREAM_REMOTE" 2>&1 | grep -v "not our ref" || true

behind="$(git rev-list --count "HEAD..${UPSTREAM_REMOTE}/main")"
echo "==> $behind new upstream commit(s)"
if [[ "$behind" -gt 0 ]]; then
  echo "==> Rebasing $BRANCH onto ${UPSTREAM_REMOTE}/main"
  if ! git rebase "${UPSTREAM_REMOTE}/main"; then
    echo "error: rebase conflict — resolve manually (git rebase --continue), then re-run" >&2
    exit 1
  fi
fi

echo "==> Syncing submodules + GhosttyKit"
git submodule update --init --recursive
"$SCRIPT_DIR/ensure-ghosttykit.sh"

echo "==> Building (tag: $BUILD_TAG)"
"$SCRIPT_DIR/reload.sh" --tag "$BUILD_TAG"

BUILT_APP="$HOME/Library/Developer/Xcode/DerivedData/cmux-${BUILD_TAG}/Build/Products/Debug/cmux DEV ${BUILD_TAG}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: built app not found at $BUILT_APP" >&2
  exit 1
fi

echo "==> Rebadging to install identity"
STAGE="$(mktemp -d /tmp/albert-update.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="$STAGE/${INSTALL_NAME}.app"
ditto "$BUILT_APP" "$STAGED_APP"
PLIST="$STAGED_APP/Contents/Info.plist"

plutil -replace CFBundleIdentifier -string "$INSTALL_BUNDLE_ID" "$PLIST"
plutil -replace CFBundleName -string "$INSTALL_NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$INSTALL_NAME" "$PLIST"
plutil -replace CFBundleURLTypes.0.CFBundleURLName -string "${INSTALL_BUNDLE_ID}.web" "$PLIST"
plutil -replace CFBundleURLTypes.1.CFBundleURLName -string "${INSTALL_BUNDLE_ID}.auth" "$PLIST"
plutil -replace CFBundleURLTypes.1.CFBundleURLSchemes.0 -string "cmux-dev" "$PLIST"
plutil -replace CMUXSidebarExtensionPointIdentifier -string "${INSTALL_BUNDLE_ID}.cmux.sidebar" "$PLIST"
plutil -remove LSEnvironment "$PLIST" 2>/dev/null || true
plutil -remove SUFeedURL "$PLIST" 2>/dev/null || true
plutil -replace SUEnableAutomaticChecks -bool false "$PLIST"

EP_DIR="$STAGED_APP/Contents/Extensions"
BUILD_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$BUILT_APP/Contents/Info.plist")"
if [[ -e "$EP_DIR/${BUILD_BUNDLE_ID}.cmux.sidebar.appextensionpoint" ]]; then
  sed "s/$(printf '%s' "$BUILD_BUNDLE_ID" | sed 's/\./\\./g')/${INSTALL_BUNDLE_ID}/g" \
    "$EP_DIR/${BUILD_BUNDLE_ID}.cmux.sidebar.appextensionpoint" \
    > "$EP_DIR/${INSTALL_BUNDLE_ID}.cmux.sidebar.appextensionpoint"
  rm "$EP_DIR/${BUILD_BUNDLE_ID}.cmux.sidebar.appextensionpoint"
fi

echo "==> Signing"
ENT="$STAGE/ent.xml"
cat > "$ENT" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
ENTITLEMENTS
codesign --force -s "$SIGN_IDENTITY" --entitlements "$ENT" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

echo "==> Installing"
if [[ -d "$INSTALL_APP" ]]; then
  BACKUP="/Applications/${INSTALL_NAME} backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$INSTALL_APP" "$BACKUP"
  echo "    previous app kept at: $BACKUP"
fi
ditto "$STAGED_APP" "$INSTALL_APP"

if [[ "$PUSH" -eq 1 ]]; then
  echo "==> Pushing $BRANCH to $FORK_REMOTE"
  git push --force-with-lease "$FORK_REMOTE" "$BRANCH"
  git push "$FORK_REMOTE" "${UPSTREAM_REMOTE}/main:refs/heads/main" || true
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INSTALL_APP/Contents/Info.plist")"
echo
echo "==> Done: ${INSTALL_NAME} ${VERSION} ($(git rev-parse --short HEAD)) installed."
echo "    Quit and relaunch cmux to finish the update, then delete the backup app."
