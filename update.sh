#!/usr/bin/env bash
# update.sh — regenerate hashes.json with current SHA-256 hashes of the
# MetaTrader 5 and WebView2 installers.
#
# Usage:
#   ./update.sh           # updates hashes.json in-place
#   ./update.sh --check   # exits non-zero if hashes have changed (CI dry-run)
set -euo pipefail

HASHES_FILE="$(dirname "$0")/hashes.json"

URL_MT5="https://download.mql5.com/cdn/web/black.bull.group/mt5/blackbullmarkets5setup.exe"
URL_WEBVIEW="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

hash_url() {
  local url="$1"
  local tmpfile
  tmpfile=$(mktemp --suffix=.exe)
  trap 'rm -f "$tmpfile"' RETURN
  echo "  Downloading: $url" >&2
  curl -fsSL --retry 3 "$url" -o "$tmpfile"
  # nix-hash outputs a base32 SRI hash compatible with fetchurl
  nix hash file --type sha256 --base32 "$tmpfile"
}

echo "==> Hashing MetaTrader 5 installer..."
HASH_MT5=$(hash_url "$URL_MT5")
echo "    $HASH_MT5"

echo "==> Hashing WebView2 Runtime installer..."
HASH_WEBVIEW=$(hash_url "$URL_WEBVIEW")
echo "    $HASH_WEBVIEW"

NEW_JSON=$(cat <<EOF
{
  "mt5": {
    "url": "$URL_MT5",
    "hash": "sha256:$HASH_MT5"
  },
  "webview2": {
    "url": "$URL_WEBVIEW",
    "hash": "sha256:$HASH_WEBVIEW"
  }
}
EOF
)

if $CHECK_ONLY; then
  OLD_JSON=$(cat "$HASHES_FILE")
  if [ "$OLD_JSON" = "$NEW_JSON" ]; then
    echo "==> Hashes unchanged."
    exit 0
  else
    echo "==> Hashes have changed! Run ./update.sh to update hashes.json."
    diff <(echo "$OLD_JSON") <(echo "$NEW_JSON") || true
    exit 1
  fi
fi

echo "$NEW_JSON" > "$HASHES_FILE"
echo "==> hashes.json updated."
