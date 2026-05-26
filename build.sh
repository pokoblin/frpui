#!/usr/bin/env bash
#
# Build & code-sign the frpui macOS app using a certificate from the local keychain.
# Signing details are read from build_config.toml (see build_config.toml.example).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CONFIG_FILE="$ROOT/build_config.toml"
TEMPLATE_FILE="$ROOT/build_config.toml.example"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "error: build_config.toml not found." >&2
  echo "Create it from the template, then fill in your signing identity:" >&2
  echo "    cp build_config.toml.example build_config.toml" >&2
  exit 1
fi

# Minimal flat-TOML reader: read_toml <key> -> prints the (unquoted) value.
read_toml() {
  local key="$1" line val
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE" | head -n1 || true)"
  [ -z "$line" ] && return 0
  val="${line#*=}"      # strip up to first '='
  val="${val%%#*}"      # strip trailing comment
  val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')"  # trim
  val="${val#\"}"; val="${val%\"}"  # strip surrounding quotes
  printf '%s' "$val"
}

SIGNING_IDENTITY="$(read_toml signing_identity)"
TEAM_ID="$(read_toml team_id)"
CONFIGURATION="$(read_toml configuration)"
[ -z "$CONFIGURATION" ] && CONFIGURATION="Release"

if [ -z "$SIGNING_IDENTITY" ]; then
  echo "error: 'signing_identity' is empty in build_config.toml." >&2
  exit 1
fi

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
}

if [ ! -f "$ROOT/cli/frpc" ]; then
  echo "error: cli/frpc not found." >&2
  echo "The frpc binary is not committed to this repo. Download the build matching your" >&2
  echo "Mac from https://github.com/fatedier/frp/releases and place it at cli/frpc:" >&2
  echo "    cp frp_<version>_darwin_arm64/frpc cli/frpc && chmod +x cli/frpc" >&2
  echo "See README.md for details." >&2
  exit 1
fi

VERSION_FILE="$ROOT/VERSION"
[ -f "$VERSION_FILE" ] || echo "1.0.1" > "$VERSION_FILE"
VERSION="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: VERSION must look like 1.0.1 (found: '$VERSION')" >&2
  exit 1
fi

echo "==> Version          : $VERSION"
echo "==> Signing identity : $SIGNING_IDENTITY"
[ -n "$TEAM_ID" ] && echo "==> Team ID          : $TEAM_ID"
echo "==> Configuration    : $CONFIGURATION"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY"; then
  echo "warning: '$SIGNING_IDENTITY' was not found by 'security find-identity -v -p codesigning'." >&2
  echo "         Continuing; codesign will fail later if the identity is wrong." >&2
fi

echo "==> Generating Xcode project (xcodegen)"
xcodegen generate

echo "==> Building (xcodebuild)"
xcode_args=(
  -project frpui.xcodeproj
  -scheme frpui
  -configuration "$CONFIGURATION"
  -derivedDataPath build
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  MARKETING_VERSION="$VERSION"
)
[ -n "$TEAM_ID" ] && xcode_args+=( DEVELOPMENT_TEAM="$TEAM_ID" )

xcodebuild "${xcode_args[@]}" clean build

APP="$ROOT/build/Build/Products/$CONFIGURATION/frpui.app"
FRPC="$APP/Contents/Resources/frpc"

[ -d "$APP" ] || { echo "error: build product not found at $APP" >&2; exit 1; }

# Re-sign the bundled frpc with the same identity, then re-seal the app bundle.
echo "==> Code-signing bundled frpc"
codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$FRPC"
echo "==> Code-signing app bundle"
codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Copying to dist/"
DIST="$ROOT/dist"
mkdir -p "$DIST"
rm -rf "$DIST/frpui.app"
ditto "$APP" "$DIST/frpui.app"   # ditto preserves the code signature and xattrs

echo ""
echo "Build complete (v$VERSION):"
echo "  $DIST/frpui.app"
echo "Open it with: open \"$DIST/frpui.app\""

# Bump the patch version for next time (only reached on a fully successful build).
MAJOR="${VERSION%%.*}"; REST="${VERSION#*.}"; MINOR="${REST%%.*}"; PATCH="${REST##*.}"
NEXT="$MAJOR.$MINOR.$((PATCH + 1))"
printf '%s\n' "$NEXT" > "$VERSION_FILE"
echo "==> Version bumped to $NEXT for the next build."
