#!/usr/bin/env bash
# Build a self-contained, ad-hoc-signed GingerPaw.app and zip it for a GitHub release.
# Usage: scripts/release.sh   (run from repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

DD="./dd-release"
APP="$DD/Build/Products/Release/GingerPaw.app"

echo "▸ Staging bundled WhisperKit model (so voice works offline)…"
SRC_MODEL="models/whisperkit-coreml/openai_whisper-base"
DST_MODEL="App/Resources/Models/whisper/openai_whisper-base"
if [ -d "$SRC_MODEL" ] && [ -f "$SRC_MODEL/TextDecoder.mlmodelc/weights/weight.bin" ]; then
  rm -rf App/Resources/Models && mkdir -p "$(dirname "$DST_MODEL")"
  cp -R "$SRC_MODEL" "$DST_MODEL"
  echo "  staged $(du -sh "$DST_MODEL" | cut -f1)"
else
  echo "  ⚠ complete model not found at $SRC_MODEL — building WITHOUT bundled model (downloads at runtime)."
fi

echo "▸ Generating project…"
xcodegen generate >/dev/null

echo "▸ Building Release (MLX needs the Metal toolchain)…"
xcodebuild -project GingerPaw.xcodeproj -scheme GingerPaw \
  -configuration Release -derivedDataPath "$DD" build | tail -2

echo "▸ Ad-hoc signing the bundle (unsigned release)…"
codesign --force --deep --sign - "$APP"
codesign -dv "$APP" 2>&1 | head -3 || true

echo "▸ Zipping…"
mkdir -p dist
rm -f dist/GingerPaw.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/GingerPaw.zip"

echo "▸ Building DMG (drag-to-Applications)…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/GingerPaw.dmg
hdiutil create -volname "GingerPaw" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "dist/GingerPaw.dmg" >/dev/null
rm -rf "$STAGE"

echo "▸ Sanity checks:"
echo "  bundled CLI: $([ -f "$APP/Contents/MacOS/gingerpaw-cli" ] && echo present || echo MISSING)"
echo "  app icon:    $([ -f "$APP/Contents/Resources/AppIcon.icns" ] && echo present || echo MISSING)"
echo "  zip size:    $(du -h dist/GingerPaw.zip | cut -f1)"
echo "✓ dist/GingerPaw.zip ready"
