#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
xcodegen generate
xcodebuild \
  -project MemoryManager.xcodeproj \
  -scheme MemoryManager \
  -configuration Release \
  -derivedDataPath .build \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

mkdir -p dist
if [[ -e "dist/Memory Manager.app" ]]; then
  find "dist/Memory Manager.app" -depth -delete
fi
ditto ".build/Build/Products/Release/MemoryManager.app" "dist/Memory Manager.app"
