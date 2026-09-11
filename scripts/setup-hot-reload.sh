#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Packages/macOS/CmuxHotReloadRuntime"
DEVELOPER="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER/Platforms/MacOSX.platform/Developer/Library/Frameworks"
swift build --package-path "$PACKAGE" --configuration debug --force-resolved-versions --product CmuxHotReloadRuntime \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xcc -F -Xcc "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS"
RUNTIME="$PACKAGE/.build/debug/libCmuxHotReloadRuntime.dylib"
codesign --force --sign "${CMUX_HOT_RELOAD_SIGN_IDENTITY:-Apple Development: Albert Su (H559K3Z4TU)}" "$RUNTIME"
codesign --verify --strict "$RUNTIME"
echo "Hot-reload runtime ready. A Debug cmux built from this checkout loads it on its next launch."
