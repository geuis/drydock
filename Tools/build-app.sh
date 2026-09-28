#!/bin/bash
#
# Builds Drydock.app as a universal (Apple silicon + Intel) release build.
#
# Usage:
#   Tools/build-app.sh [--version 1.2.3] [--build-number 42] [--sign] [--notarize]
#
#   --sign      Sign the app with the Developer ID certificate in the keychain.
#   --notarize  Also package a DMG, sign it, notarize it with Apple, and staple
#               the result. Implies --sign.
#
# Environment:
#   SIGN_IDENTITY      Signing identity (default: "Developer ID Application").
#   NOTARY_PROFILE     notarytool keychain profile (default: drydock-notary).
#   NOTARY_KEY_PATH,   When all three are set, notarytool uses this App Store
#   NOTARY_KEY_ID,     Connect API key directly instead of the keychain
#   NOTARY_ISSUER_ID   profile. This is how CI logs in.
#
# Output goes to dist/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/Drydock.app"

VERSION="0.0.0-dev"
BUILD_NUMBER="1"
SHOULD_SIGN="false"
SHOULD_NOTARIZE="false"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-drydock-notary}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --sign)
            SHOULD_SIGN="true"
            shift
            ;;
        --notarize)
            SHOULD_SIGN="true"
            SHOULD_NOTARIZE="true"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

build_binary() {
    echo "==> Building universal release binary"
    cd "$REPO_ROOT"
    swift build -c release --arch arm64 --arch x86_64
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
}

assemble_app() {
    echo "==> Assembling $APP_DIR"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

    cp "$BIN_DIR/Drydock" "$APP_DIR/Contents/MacOS/Drydock"

    # Code signing only allows executables in Contents/MacOS, so the
    # resource bundle goes in Contents/Resources (see FieldSchema.resourceBundle).
    cp -R "$BIN_DIR/Drydock_Drydock.bundle" "$APP_DIR/Contents/Resources/"
    cp "$REPO_ROOT/Tools/AppIcon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

    sed -e "s/__VERSION__/$VERSION/" \
        -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/" \
        "$REPO_ROOT/Tools/Info.plist" > "$APP_DIR/Contents/Info.plist"
}

sign_app() {
    echo "==> Signing with \"$SIGN_IDENTITY\""

    # The hardened runtime and a secure timestamp are both required for
    # notarization.
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP_DIR"

    codesign --verify --strict --verbose=2 "$APP_DIR"
}

make_dmg() {
    echo "==> Packaging DMG"
    DMG_PATH="$DIST_DIR/Drydock-$VERSION.dmg"

    local staging_dir="$DIST_DIR/dmg-staging"
    rm -rf "$staging_dir" "$DMG_PATH"
    mkdir -p "$staging_dir"

    # The Applications link lets users drag the app straight to install it.
    cp -R "$APP_DIR" "$staging_dir/"
    ln -s /Applications "$staging_dir/Applications"

    hdiutil create -volname "Drydock" -srcfolder "$staging_dir" \
        -ov -format UDZO "$DMG_PATH"
    rm -rf "$staging_dir"

    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
}

notarize_dmg() {
    echo "==> Notarizing $DMG_PATH (this usually takes a few minutes)"

    if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
        xcrun notarytool submit "$DMG_PATH" --wait \
            --key "$NOTARY_KEY_PATH" \
            --key-id "$NOTARY_KEY_ID" \
            --issuer "$NOTARY_ISSUER_ID"
    else
        xcrun notarytool submit "$DMG_PATH" --wait \
            --keychain-profile "$NOTARY_PROFILE"
    fi

    # Attaches Apple's approval to the DMG so Gatekeeper can check it offline.
    xcrun stapler staple "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
}

build_binary
assemble_app

if [[ "$SHOULD_SIGN" == "true" ]]; then
    sign_app
fi

if [[ "$SHOULD_NOTARIZE" == "true" ]]; then
    make_dmg
    notarize_dmg
fi

echo "==> Done: $APP_DIR"
