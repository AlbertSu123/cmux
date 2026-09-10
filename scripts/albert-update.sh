#!/usr/bin/env bash
# Update "/Applications/cmux (Albert's version).app" from this fork.
#
# Pipeline: require committed source -> optionally rebase onto origin/main ->
# sync submodules + prebuilt GhosttyKit -> tagged build -> rebadge and sign ->
# push branch and immutable source tag to GitHub -> replace the single app.
#
# The install identity is the original remote-click tagged build this app
# grew out of: keeping the bundle id preserves session state, settings, and
# closed-item history across updates. The rebadge also strips the tagged
# build's LSEnvironment (localhost dev endpoints) and Sparkle feed (upstream
# releases would overwrite this fork's patches).
#
# Run from anywhere; operates on the repo containing this script.
# Pass --rebase to update main from upstream before building.
# Every installation requires a successful push; --no-rebase is the default.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

BRANCH=""
UPSTREAM_REMOTE="origin"
FORK_REMOTE="fork"
BUILD_TAG="albert-update"
# Release needs project signing work first: its configuration is CODE_SIGN_STYLE
# Manual with an empty DEVELOPMENT_TEAM, so the build fails on the app's
# get-task-allow entitlement. Pass --configuration Release once that is sorted.
CONFIGURATION="Debug"
INSTALL_APP="/Applications/cmux (Albert's version).app"
INSTALL_NAME="cmux (Albert's version)"
INSTALL_BUNDLE_ID="com.cmuxterm.app.debug.remote.click"
SIGN_IDENTITY="Apple Development: Albert Su (H559K3Z4TU)"

REBASE=0
for arg in "$@"; do
  case "$arg" in
    --rebase) REBASE=1 ;;
    --no-rebase|--build-only) REBASE=0 ;;
    *) echo "error: unknown option $arg (expected --rebase or --no-rebase; pushing is required)" >&2; exit 1 ;;
  esac
done

cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty; commit or stash first" >&2
  exit 1
fi
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "error: check out a branch before installing" >&2
  exit 1
}
if [[ "$REBASE" -eq 1 && "$BRANCH" != main ]]; then
  echo "error: --rebase requires the main branch" >&2
  exit 1
fi

if [[ "$REBASE" -eq 1 ]]; then
  echo "==> Fetching $UPSTREAM_REMOTE"
  git fetch "$UPSTREAM_REMOTE" main

  behind="$(git rev-list --count "HEAD..${UPSTREAM_REMOTE}/main")"
  echo "==> $behind new upstream commit(s)"
  if [[ "$behind" -gt 0 ]]; then
    echo "==> Rebasing $BRANCH onto ${UPSTREAM_REMOTE}/main"
    if ! git rebase "${UPSTREAM_REMOTE}/main"; then
      echo "error: rebase conflict — resolve manually (git rebase --continue), then re-run" >&2
      exit 1
    fi
  fi
else
  echo "==> Skipping upstream rebase (--no-rebase); building $(git rev-parse --short HEAD)"
fi

SOURCE_COMMIT="$(git rev-parse HEAD)"

echo "==> Syncing submodules + GhosttyKit"
git submodule update --init --recursive
"$SCRIPT_DIR/ensure-ghosttykit.sh"

echo "==> Building (tag: $BUILD_TAG, configuration: $CONFIGURATION)"
"$SCRIPT_DIR/reload.sh" --tag "$BUILD_TAG" --configuration "$CONFIGURATION"

BUILT_APP="$HOME/Library/Developer/Xcode/DerivedData/cmux-${BUILD_TAG}/Build/Products/${CONFIGURATION}/cmux DEV ${BUILD_TAG}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: built app not found at $BUILT_APP" >&2
  exit 1
fi

echo "==> Rebadging to install identity"
STAGE="$(mktemp -d /tmp/albert-update.XXXXXX)"
ROLLBACK=""
cleanup() {
  if [[ -n "$ROLLBACK" && -d "$ROLLBACK/previous.app" ]]; then
    rm -rf "$INSTALL_APP"
    mv "$ROLLBACK/previous.app" "$INSTALL_APP"
  fi
  [[ -z "$ROLLBACK" ]] || rmdir "$ROLLBACK"
  rm -rf "$STAGE"
}
trap cleanup EXIT
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
# Stamp the source commit so tooling can tell what the installed app contains;
# the version string alone does not move between builds.
plutil -replace CMUXInstalledCommit -string "$SOURCE_COMMIT" "$PLIST"
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

# Refuse to install a build if another process changed its source meanwhile.
if [[ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" || -n "$(git status --porcelain)" ]]; then
  echo "error: source changed during build; commit changes and rebuild" >&2
  exit 1
fi
# The immutable tag retains each installed revision even after later rebases.
echo "==> Preserving source on $FORK_REMOTE"
git push --atomic "$FORK_REMOTE" \
  "$SOURCE_COMMIT:refs/heads/$BRANCH" \
  "$SOURCE_COMMIT:refs/tags/albert-installed/$SOURCE_COMMIT"
REMOTE_COMMIT="$(git ls-remote "$FORK_REMOTE" "refs/tags/albert-installed/$SOURCE_COMMIT" | awk '{print $1}')"
[[ "$REMOTE_COMMIT" == "$SOURCE_COMMIT" ]] || {
  echo "error: could not verify installed source on GitHub" >&2
  exit 1
}

echo "==> Installing"
# Keep rollback data only during replacement, outside application search paths.
ROLLBACK="$(mktemp -d /Applications/.cmux-install.XXXXXX)"
if [[ -d "$INSTALL_APP" ]]; then
  mv "$INSTALL_APP" "$ROLLBACK/previous.app"
fi
ditto "$STAGED_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
rm -rf "$ROLLBACK/previous.app"
rmdir "$ROLLBACK"
ROLLBACK=""

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INSTALL_APP/Contents/Info.plist")"
echo
echo "==> Done: ${INSTALL_NAME} ${VERSION} ($(git rev-parse --short HEAD)) installed."
echo "    Quit and relaunch cmux to finish the update, source history is preserved on GitHub."
