#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
module_cache="$project_root/.build/module-cache"
app_target="$project_root/dist/Codex 额度球.app"
icon_tmp="$(mktemp -d "${TMPDIR%/}/codex-orb-icon.XXXXXX")"

cleanup() {
  rm -rf "$icon_tmp"
}
trap cleanup EXIT

mkdir -p "$module_cache"

env \
  CLANG_MODULE_CACHE_PATH="$module_cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
  swift build \
  --package-path "$project_root" \
  --configuration release \
  --disable-sandbox

rm -rf "$app_target"
mkdir -p "$app_target/Contents/MacOS"
mkdir -p "$app_target/Contents/Resources"

cp "$project_root/.build/release/CodexOrb" \
  "$app_target/Contents/MacOS/CodexOrb"
cp "$project_root/Resources/Info.plist" \
  "$app_target/Contents/Info.plist"

swift \
  -module-cache-path "$module_cache" \
  "$project_root/scripts/make_icon.swift" \
  "$icon_tmp/AppIcon-1024.png"

iconset="$icon_tmp/AppIcon.iconset"
mkdir -p "$iconset"

sips -z 16 16 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_tmp/AppIcon-1024.png" --out "$iconset/icon_512x512.png" >/dev/null
cp "$icon_tmp/AppIcon-1024.png" "$iconset/icon_512x512@2x.png"

swift \
  -module-cache-path "$module_cache" \
  "$project_root/scripts/make_icns.swift" \
  "$iconset" \
  "$app_target/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$app_target" >/dev/null

echo "$app_target"
