#!/bin/bash
# Builds, signs and packages Halo for a GitHub release, then adds it to the Sparkle appcast.
#
#   ./release.sh                          Developer ID sign and verify
#   ./release.sh --notarize               ... then notarize and staple (needs NOTARY_PROFILE)
#   ./release.sh --adhoc                  ad-hoc sign, for releasing without a Developer ID
#   VERSION=1.2.0 BUILD=34 ./release.sh   stamp a version into the bundle and Resources/Info.plist
#
# An ad-hoc download is flagged by Gatekeeper, so its first launch needs right-click > Open or
# `xattr -cr`. Sparkle's EdDSA signature works the same in every mode.
#
# CODESIGN_IDENTITY picks the certificate when the keychain has several Developer IDs.
# NOTARY_PROFILE names a credential stored with `xcrun notarytool store-credentials`.
# APPCAST_URL, if set, is the published feed to extend when build/releases has none.
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Halo.app"
ZIP="build/Halo.zip"
NOTARIZE=0
ADHOC=0
case "${1:-}" in
    --notarize) NOTARIZE=1 ;;
    --adhoc) ADHOC=1 ;;
    "") ;;
    *)
        echo "==> ERROR: unknown option \"$1\" (expected --notarize, --adhoc or nothing)" >&2
        exit 1
        ;;
esac

if [[ "$ADHOC" == "1" ]]; then
    IDENTITY="-"
else
    # By common name, so a renewed certificate still matches.
    IDENTITY="${CODESIGN_IDENTITY:-}"
    if [[ -z "$IDENTITY" ]]; then
        FOUND=$(security find-identity -v -p codesigning \
            | grep "Developer ID Application" \
            | sed -E 's/.*"(.*)".*/\1/' || true)
        if [[ "$(printf '%s' "$FOUND" | grep -c . || true)" -gt 1 ]]; then
            echo "==> ERROR: several Developer ID certificates found, pick one with CODESIGN_IDENTITY:" >&2
            printf '%s\n' "$FOUND" | sed 's/^/      /' >&2
            exit 1
        fi
        IDENTITY="$FOUND"
    fi
    if [[ -z "$IDENTITY" ]]; then
        echo "==> ERROR: no \"Developer ID Application\" certificate in the keychain." >&2
        echo "    Release without one: ./release.sh --adhoc" >&2
        exit 1
    fi
fi
echo "==> Release identity: $IDENTITY"

# Notarizing needs the hardened runtime and a timestamp. Ad-hoc gains nothing from either, and has
# no signing service to timestamp with.
HARDENED=1
[[ "$ADHOC" == "1" ]] && HARDENED=0

# Written into the tracked plist too, so the tree records what was last shipped. perl rather than
# PlistBuddy, which rewrites the whole file and drops its comments.
stamp_template() {
    local key="$1" value="$2"
    KEY="$key" VALUE="$value" perl -0pi -e \
        's{(<key>\Q$ENV{KEY}\E</key>\s*<string>)[^<]*(</string>)}{$1$ENV{VALUE}$2}' \
        Resources/Info.plist
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" Resources/Info.plist)" != "$value" ]]; then
        echo "==> ERROR: could not stamp $key=$value into Resources/Info.plist" >&2
        exit 1
    fi
}
[[ -n "${VERSION:-}" ]] && stamp_template CFBundleShortVersionString "$VERSION"
[[ -n "${BUILD:-}" ]] && stamp_template CFBundleVersion "$BUILD"

CODESIGN_IDENTITY="$IDENTITY" HARDENED="$HARDENED" RELEASE=1 UNIVERSAL=1 ./build.sh

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=4 "$APP" 2>&1 \
    | grep -E "Authority|TeamIdentifier|Timestamp|Runtime Version|Identifier" || true

if [[ "$ADHOC" != "1" && "$NOTARIZE" != "1" ]]; then
    echo "==> Built and signed: $APP"
    echo "    Not notarized, so Gatekeeper refuses it on other Macs. Re-run with --notarize."
    exit 0
fi

# ditto, not zip: it keeps the framework's symlinks, which the notary service and the signature
# both need.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$NOTARIZE" == "1" ]]; then
    if [[ -z "${NOTARY_PROFILE:-}" ]]; then
        echo "==> ERROR: NOTARY_PROFILE is not set. Store credentials once with:" >&2
        echo "      xcrun notarytool store-credentials \"Halo\" \\" >&2
        echo "        --apple-id you@example.com --team-id TEAMID --password <app-specific-password>" >&2
        exit 1
    fi
    echo "==> Submitting to Apple (this takes a few minutes)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    # Stapled so the app opens on a Mac that can't reach Apple, then zipped again to carry the
    # ticket.
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type exec --verbose=4 "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

RELEASES="build/releases"
APPCAST="$RELEASES/appcast.xml"
STAGING="build/appcast-staging"
GENERATE_APPCAST="$(find .build/artifacts -type f -name generate_appcast -perm -u+x -print -quit || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "==> ERROR: generate_appcast not found, run 'swift package resolve'" >&2
    exit 1
fi

# Versioned names, because generate_appcast tells archives apart by filename.
STAMPED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHIVE="Halo-$STAMPED_VERSION.zip"
mkdir -p "$RELEASES"
cp "$ZIP" "$RELEASES/$ARCHIVE"

# A failed fetch stops the release. Carrying on would publish a feed listing only this version,
# and installs more than one version behind would never see an update again.
if [[ -n "${APPCAST_URL:-}" && ! -f "$APPCAST" ]]; then
    echo "==> Fetching the published appcast"
    if ! curl -fsSL "$APPCAST_URL" -o "$APPCAST"; then
        rm -f "$APPCAST"
        echo "==> ERROR: could not fetch $APPCAST_URL. Unset APPCAST_URL for the first release." >&2
        exit 1
    fi
fi

# generate_appcast only sees this release's zip and the feed so far. Given older zips too, it
# re-points their items at this release's download URL, where those files don't exist.
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp "$RELEASES/$ARCHIVE" "$STAGING/"
[[ -f "$APPCAST" ]] && cp "$APPCAST" "$STAGING/appcast.xml"

echo "==> Generating appcast"
DOWNLOAD_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/kdbaustert/Halo/releases/download/v$STAMPED_VERSION/}"
"$GENERATE_APPCAST" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --maximum-versions 0 \
    --maximum-deltas 0 \
    "$STAGING"
cp "$STAGING/appcast.xml" "$APPCAST"

echo "==> Appcast written: $APPCAST"
echo "    Upload $RELEASES/$ARCHIVE to the v$STAMPED_VERSION release and $APPCAST to gh-pages."
