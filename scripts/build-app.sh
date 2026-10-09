#!/bin/zsh
# Builds Pith.app: the SwiftUI app with the TypeScript core in its Resources.
# Requires Node.js 24+ at runtime. Usage: scripts/build-app.sh [--open]
set -euo pipefail
ROOT=${0:A:h:h}
OUT="$ROOT/build/Pith.app"

echo "→ core: installing runtime dependencies"
(cd "$ROOT/core" && npm install --silent)

echo "→ app: compiling (release)"
(cd "$ROOT/app" && swift build -c release --quiet)
BIN="$(cd "$ROOT/app" && swift build -c release --show-bin-path)/Pith"

[[ -f "$ROOT/assets/Pith.icns" ]] || swift "$ROOT/scripts/make-icon.swift" "$ROOT/assets/Pith.icns"

echo "→ bundle: $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/Pith"
cp "$ROOT/assets/Pith.icns" "$OUT/Contents/Resources/Pith.icns"
rsync -a --delete \
  --exclude test --exclude sim --exclude tsconfig.json \
  --exclude node_modules/typescript --exclude 'node_modules/@typescript' --exclude 'node_modules/@types' \
  "$ROOT/core/" "$OUT/Contents/Resources/core/"

VERSION=$(node -p "require('$ROOT/core/package.json').version")
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pith</string>
  <key>CFBundleDisplayName</key><string>Pith</string>
  <key>CFBundleIdentifier</key><string>app.pith.Pith</string>
  <key>CFBundleExecutable</key><string>Pith</string>
  <key>CFBundleIconFile</key><string>Pith</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || true
echo "✓ built $OUT"
[[ "${1:-}" == "--open" ]] && open "$OUT"
