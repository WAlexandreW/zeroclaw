#!/usr/bin/env bash
set -euo pipefail

# --- Config (override via environment or .deploy-pi.env) ---
if [ -f "$(dirname "$0")/.deploy-pi.env" ]; then
    # shellcheck source=/dev/null
    source "$(dirname "$0")/.deploy-pi.env"
fi

PI_USER="${PI_USER:?Set PI_USER in .deploy-pi.env or environment}"
PI_HOST="${PI_HOST:?Set PI_HOST in .deploy-pi.env or environment}"
PI_BIN="${PI_BIN:-/home/${PI_USER}/.local/bin/zeroclaw}"
TARGET="${TARGET:-arm-unknown-linux-musleabihf}"
BRANCH="${BRANCH:-pi-deploy}"
MERGE_BRANCHES="${MERGE_BRANCHES:-}"

# --- Cross-compile ---
echo "==> Checking out $BRANCH..."
git checkout "$BRANCH"

if [ -n "$MERGE_BRANCHES" ]; then
    echo "==> Merging updates from configured branches..."
    for b in $MERGE_BRANCHES; do
        echo "  -> Merging $b..."
        git merge "$b" --no-edit || { echo "Merge conflict with $b! Aborting."; exit 1; }
    done
fi


echo "==> Cross-compiling for $TARGET (release)..."
CARGO_TARGET_ARM_UNKNOWN_LINUX_MUSLEABIHF_LINKER=arm-unknown-linux-musleabihf-gcc \
CC_arm_unknown_linux_musleabihf=arm-unknown-linux-musleabihf-gcc \
cargo build --target "$TARGET" --release

BINARY="target/${TARGET}/release/zeroclaw"
echo "==> Built: $(ls -lh "$BINARY" | awk '{print $5}') — $(file "$BINARY" | cut -d: -f2)"

# --- Deploy ---
echo "==> Uploading binary to ${PI_USER}@${PI_HOST}..."
scp "$BINARY" "${PI_USER}@${PI_HOST}:/tmp/zeroclaw-new"

echo "==> Installing and restarting service..."
ssh "${PI_USER}@${PI_HOST}" bash -s <<REMOTE
set -euo pipefail
chmod +x /tmp/zeroclaw-new
mv /tmp/zeroclaw-new ${PI_BIN}
systemctl --user restart zeroclaw
sleep 2
systemctl --user status zeroclaw --no-pager
echo "==> Deployed: \$(zeroclaw --version 2>/dev/null || echo 'version check not supported')"
REMOTE

echo "==> Done!"
