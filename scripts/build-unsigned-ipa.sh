#!/usr/bin/env bash
# Compile l'app et produit une IPA NON SIGNÉE (à signer avec Sideloadly/AltStore).
# Nécessite macOS + Xcode + Homebrew (xcodegen) + Rust (rustup).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"

"$ROOT/scripts/build-core.sh"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen introuvable. Installe-le avec : brew install xcodegen" >&2
  exit 1
fi

echo "==> Génération du projet Xcode"
cd "$ROOT/ios"
xcodegen generate

ARCHIVE="$OUT_DIR/MP3Tagger.xcarchive"
mkdir -p "$OUT_DIR"

echo "==> Archive (sans signature)"
xcodebuild \
  -project MP3Tagger.xcodeproj \
  -scheme MP3Tagger \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM=""

APP="$ARCHIVE/Products/Applications/MP3Tagger.app"
test -d "$APP"

echo "==> Création de l'IPA"
rm -rf "$OUT_DIR/ipa"
mkdir -p "$OUT_DIR/ipa/Payload"
cp -R "$APP" "$OUT_DIR/ipa/Payload/"
cd "$OUT_DIR/ipa"
zip -qry MP3Tagger-unsigned.ipa Payload

echo "IPA : $OUT_DIR/ipa/MP3Tagger-unsigned.ipa"
