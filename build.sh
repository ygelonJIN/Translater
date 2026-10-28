#!/bin/bash
# 重新编译并签名 Translater.app
set -e
cd "$(dirname "$0")"
IDENTITY="Apple Development: 8618019432615 (XU8MNRY4CV)"
mkdir -p .modcache Translater.app/Contents/MacOS
swiftc -O -target arm64-apple-macos26.0 \
  -module-cache-path "$PWD/.modcache" \
  -Xcc -fmodules-cache-path="$PWD/.modcache" \
  Sources/*.swift \
  -o Translater.app/Contents/MacOS/Translater
codesign --force --deep --sign "$IDENTITY" Translater.app
echo "构建完成：Translater.app"
