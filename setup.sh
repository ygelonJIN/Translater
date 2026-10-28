#!/bin/bash
# 一键编译 + 签名 Translater.app
# 用法：
#   ./setup.sh                 自动选签名身份（没有就自建一张自签证书）
#   ./setup.sh --ad-hoc        不签名身份，用临时签名（每次重编译要重新授权）
#   SIGN_IDENTITY="证书名" ./setup.sh   指定证书

set -uo pipefail
cd "$(dirname "$0")" || exit 1

APP="Translater.app"
CERT_NAME="Translater Local Signing"
CERT_DAYS=3650

say() { printf "\033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[33m%s\033[0m\n" "$*"; }
die() { printf "\033[31m%s\033[0m\n" "$*"; exit 1; }

# ---------- 1. 工具链 ----------
if ! command -v swiftc >/dev/null 2>&1; then
  die "缺少 Swift 编译器。请先运行：xcode-select --install"
fi
say "Swift: $(swiftc --version 2>/dev/null | head -1)"

# ---------- 2. 选签名身份 ----------
if [ "${1:-}" = "--ad-hoc" ]; then
  IDENTITY="-"
else
  IDENTITY="${SIGN_IDENTITY:-}"
  if [ -z "$IDENTITY" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
      IDENTITY="$CERT_NAME"
    else
      FIRST=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | head -1)
      if [ -n "$FIRST" ]; then
        IDENTITY="$FIRST"
      fi
    fi
  fi

  # 一个可用身份都没有 → 现场生成一张自签证书
  if [ -z "$IDENTITY" ]; then
    say "没有找到代码签名身份，正在生成自签证书「$CERT_NAME」…"
    TMP=$(mktemp -d)
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$TMP/k.pem" -out "$TMP/c.pem" -days "$CERT_DAYS" \
      -subj "/CN=$CERT_NAME" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1 \
      || die "openssl 生成证书失败"

    # macOS 的 security 只认旧式 PKCS12，OpenSSL 3 需要 -legacy
    openssl pkcs12 -export -legacy -out "$TMP/c.p12" -inkey "$TMP/k.pem" -in "$TMP/c.pem" -passout pass:translater >/dev/null 2>&1 \
      || openssl pkcs12 -export -out "$TMP/c.p12" -inkey "$TMP/k.pem" -in "$TMP/c.pem" -passout pass:translater >/dev/null 2>&1

    security import "$TMP/c.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
      -P translater -T /usr/bin/codesign -A >/dev/null 2>&1 \
      || die "导入证书失败（可以试试 ./setup.sh --ad-hoc）"

    rm -rf "$TMP"
    IDENTITY="$CERT_NAME"
    warn "自签证书已建好。这张证书只在本机有效，但能让系统授权在重编译后保留。"
  fi
fi

say "签名身份：$IDENTITY"

# ---------- 3. 编译 ----------
mkdir -p .modcache "$APP/Contents/MacOS" || die "无法创建构建目录"
say "正在编译…"
swiftc -O -target arm64-apple-macos26.0 \
  -module-cache-path "$PWD/.modcache" \
  -Xcc -fmodules-cache-path="$PWD/.modcache" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Translater" || die "编译失败"

# ---------- 4. 签名 ----------
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && say "已用临时签名（ad-hoc）"
else
  if codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1; then
    say "已签名：$IDENTITY"
  else
    warn "用「$IDENTITY」签名失败，退回临时签名"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1
  fi
fi

# ---------- 5. 完成 ----------
say "构建完成：$APP"
echo
echo "下一步："
echo "  open $APP          # 启动"
echo "  或者把 $APP 拖进「应用程序」文件夹"
