#!/bin/bash
# Builds Halo.app. Pass --install to copy it into /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Halo.app"

# Checked before anything builds, so a mistyped --install fails rather than quietly not installing.
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *)
            echo "==> ERROR: unknown option \"$arg\" (the only one is --install)" >&2
            exit 1
            ;;
    esac
done

echo "==> Compiling"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Brighter"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Halo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc is enough: the app asks for no folder or privacy access, so there is no grant for a
# changing code hash to invalidate.
echo "==> Signing ad-hoc"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "==> Built $APP"

if [[ "$INSTALL" == 1 ]]; then
    echo "==> Installing to /Applications"
    # By bundle ID, so this also quits a copy installed before the rename to Halo.
    osascript -e 'quit app id "dev.kennyb.Brighter"' 2>/dev/null || true
    for _ in $(seq 1 30); do
        pgrep -x Halo >/dev/null 2>&1 || pgrep -x Brighter >/dev/null 2>&1 || break
        sleep 0.1
    done
    pkill -9 -x Halo 2>/dev/null || true
    pkill -9 -x Brighter 2>/dev/null || true
    # Copied beside the old copy first, so a failed copy leaves it installed. Not named *.app, so
    # nothing registers the half-copied bundle.
    STAGED="/Applications/.Halo-installing"
    rm -rf "$STAGED"
    cp -R "$APP" "$STAGED"
    rm -rf /Applications/Halo.app
    mv "$STAGED" /Applications/Halo.app
    open /Applications/Halo.app
    echo "==> Launched."
fi
