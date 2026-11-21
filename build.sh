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

# release.sh sets UNIVERSAL so Intel Macs get a build too. generate_appcast reads the slices and
# marks an arm64-only bundle as Apple Silicon only in the feed.
ARCH_ARGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
    echo "==> Compiling (universal: arm64 + x86_64)"
else
    echo "==> Compiling"
fi
# The `+` form because macOS bash 3.2 calls an empty array unbound under `set -u`.
swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)/Brighter"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Halo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM links Sparkle but doesn't put it in a bundle assembled by hand. Without the copy and
# the rpath, the app dies at launch with dyld "Library not loaded".
SPARKLE_XC="$(find .build/artifacts -type d -name 'Sparkle.xcframework' -print -quit)"
if [[ -z "$SPARKLE_XC" ]]; then
    echo "==> ERROR: Sparkle.xcframework not found, run 'swift package resolve' first" >&2
    exit 1
fi
# Found rather than hardcoded: the slice's name lists its architectures and can change in a bump.
SPARKLE_FW="$(find "$SPARKLE_XC" -maxdepth 2 -type d -name 'Sparkle.framework' -path '*macos*' -print -quit)"
if [[ -z "$SPARKLE_FW" ]]; then
    echo "==> ERROR: no macOS slice inside $SPARKLE_XC" >&2
    exit 1
fi
echo "==> Embedding Sparkle"
mkdir -p "$APP/Contents/Frameworks"
# -R keeps the framework's Versions symlinks, which its signature depends on.
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
# install_name_tool refuses a duplicate rpath, so add it only when missing. No `grep -q`: under
# pipefail an early exit can fail the pipeline with SIGPIPE.
if ! otool -l "$APP/Contents/MacOS/Halo" | grep -F -- '@executable_path/../Frameworks' >/dev/null; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Halo"
fi

# Stamped into the built copy only, so a release leaves Resources/Info.plist untouched.
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi

# A local build keeps no feed, or it would see the published version as newer and replace itself.
# Updater.isConfigured reads this to grey out the update controls.
if [[ "${RELEASE:-0}" != "1" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Ad-hoc by default. Halo asks for no folder or privacy access, so there's no grant for a changing
# code hash to invalidate. release.sh passes a Developer ID and HARDENED=1 for notarizing.
IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "${HARDENED:-0}" == "1" ]]; then
    # The notary service rejects code without the hardened runtime, and the timestamp keeps the
    # signature valid after the certificate expires.
    SIGN_ARGS+=(--options runtime --timestamp)
fi
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -F -- "$IDENTITY" >/dev/null; then
    echo "==> ERROR: signing identity \"$IDENTITY\" not found in the keychain" >&2
    exit 1
fi

# Inside-out, since each seal covers the code inside it. Loose helpers like Autoupdate first, then
# bundles deepest first. Every item is re-signed: Sparkle ships them ad-hoc, which notarizing
# rejects. `! -type l` skips the framework's symlinked copies of the same bundles.
echo "==> Signing as \"$IDENTITY\""
while IFS= read -r item; do
    codesign "${SIGN_ARGS[@]}" "$item"
done < <(find "$APP/Contents/Frameworks" -type f -perm -u+x ! -path '*/Contents/MacOS/*' -exec sh -c 'file -b "$1" | grep -q "Mach-O.*executable"' _ {} \; -print)
while IFS= read -r item; do
    codesign "${SIGN_ARGS[@]}" "$item"
done < <(find "$APP/Contents/Frameworks" -depth \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) ! -type l -print)
codesign "${SIGN_ARGS[@]}" "$APP"
# --deep catches nested code signed in the wrong order, which otherwise shows up as a notarizing
# rejection.
codesign --verify --deep --strict "$APP"

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
