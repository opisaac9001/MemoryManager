#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
./build.sh

app_path="dist/Memory Manager.app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MemoryManager/Info.plist)"
dmg_path="dist/Memory Manager ${version}.dmg"
stage_path="dist/dmg-stage"

if [[ -n "${MEMORY_MANAGER_DEVELOPER_ID:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "$MEMORY_MANAGER_DEVELOPER_ID" "$app_path"
fi

if [[ -e "$stage_path" ]]; then
  find "$stage_path" -depth -delete
fi
mkdir -p "$stage_path"
ditto "$app_path" "$stage_path/Memory Manager.app"
ln -s /Applications "$stage_path/Applications"
hdiutil create -quiet -volname "Memory Manager" -srcfolder "$stage_path" -ov -format UDZO "$dmg_path"

if [[ -n "${MEMORY_MANAGER_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$MEMORY_MANAGER_NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_path"
fi

find "$stage_path" -depth -delete
echo "$dmg_path"
