#!/bin/bash
# Transit demo: encryption as a service, key rotation and rewrap, data keys, HMAC,
# signing, and a least-privilege policy for the application that uses the key.
set -euo pipefail

export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BAO_BIN="${BAO_BIN:-$(command -v bao 2>/dev/null || echo /opt/homebrew/bin/bao)}"
MOUNT="${TRANSIT_MOUNT:-transit}"
KEY="ra-approvals"
SIGN_KEY="ra-signing"

bao() { command "$BAO_BIN" "$@"; }
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
unb64() { printf '%s' "$1" | base64 --decode; }
pass() { echo "   [PASS] $*"; }
fail() { echo "   [FAIL] $*"; exit 1; }

# Recreate a key so every run starts from version 1
fresh_key() {
    if bao read "$MOUNT/keys/$1" >/dev/null 2>&1; then
        bao write "$MOUNT/keys/$1/config" deletion_allowed=true >/dev/null
        bao delete "$MOUNT/keys/$1" >/dev/null
    fi
    bao write "$MOUNT/keys/$1" type="$2" >/dev/null
}

echo "--> START: Transit demo against $BAO_ADDR"
PLAINTEXT='{"request":"A1B2C3D4","cn":"api.blue.energy.internal","approved_by":"ra-operator-2"}'

echo "--> 1. Key '$KEY' (aes256-gcm96), rotated every 30 days, not deletable, not exportable"
bao secrets enable -path="$MOUNT" transit >/dev/null 2>&1 || true
fresh_key "$KEY" aes256-gcm96
bao write "$MOUNT/keys/$KEY/config" auto_rotate_period=720h deletion_allowed=false >/dev/null
[ "$(bao read -field=exportable "$MOUNT/keys/$KEY")" = "false" ] && pass "key cannot be exported" || fail "key is exportable"

echo "--> 2. Encrypt and decrypt: the application never sees the key"
CT1=$(bao write -field=ciphertext "$MOUNT/encrypt/$KEY" plaintext="$(b64 "$PLAINTEXT")")
echo "   ciphertext: ${CT1:0:40}..."
[[ "$CT1" == *:v1:* ]] && pass "ciphertext is tagged with key version 1" || fail "expected a v1 ciphertext"
[ "$(unb64 "$(bao write -field=plaintext "$MOUNT/decrypt/$KEY" ciphertext="$CT1")")" = "$PLAINTEXT" ] \
    && pass "decrypts back to the original" || fail "decrypted text differs"

echo "--> 3. Rotate, rewrap, then retire version 1"
bao write -f "$MOUNT/keys/$KEY/rotate" >/dev/null
CT2=$(bao write -field=ciphertext "$MOUNT/encrypt/$KEY" plaintext="$(b64 "$PLAINTEXT")")
[[ "$CT2" == *:v2:* ]] && pass "new encryptions use version 2" || fail "expected a v2 ciphertext"
bao write "$MOUNT/decrypt/$KEY" ciphertext="$CT1" >/dev/null && pass "old v1 ciphertext still decrypts" || fail "v1 no longer decrypts"
REWRAPPED=$(bao write -field=ciphertext "$MOUNT/rewrap/$KEY" ciphertext="$CT1")
[[ "$REWRAPPED" == *:v2:* ]] && pass "rewrap moved v1 ciphertext to v2 without exposing the plaintext" || fail "rewrap failed"
bao write "$MOUNT/keys/$KEY/config" min_decryption_version=2 >/dev/null
if bao write "$MOUNT/decrypt/$KEY" ciphertext="$CT1" >/dev/null 2>&1; then
    fail "v1 ciphertext still decrypts after min_decryption_version=2"
fi
pass "v1 ciphertext is refused after min_decryption_version=2"
[ "$(unb64 "$(bao write -field=plaintext "$MOUNT/decrypt/$KEY" ciphertext="$REWRAPPED")")" = "$PLAINTEXT" ] \
    && pass "rewrapped ciphertext still decrypts" || fail "rewrapped ciphertext does not decrypt"

echo "--> 4. Data key for envelope encryption of large data"
DATAKEY=$(bao write -format=json -f "$MOUNT/datakey/plaintext/$KEY")
DK_PLAIN=$(jq -r '.data.plaintext' <<<"$DATAKEY")
DK_WRAPPED=$(jq -r '.data.ciphertext' <<<"$DATAKEY")
[ "$(bao write -field=plaintext "$MOUNT/decrypt/$KEY" ciphertext="$DK_WRAPPED")" = "$DK_PLAIN" ] \
    && pass "encrypt locally with the plaintext key, store only the wrapped key" || fail "data key does not unwrap"

echo "--> 5. HMAC for integrity"
HMAC=$(bao write -field=hmac "$MOUNT/hmac/$KEY" input="$(b64 "$PLAINTEXT")")
[ "$(bao write -field=valid "$MOUNT/verify/$KEY" input="$(b64 "$PLAINTEXT")" hmac="$HMAC")" = "true" ] \
    && pass "HMAC verifies" || fail "HMAC does not verify"

echo "--> 6. Signing with '$SIGN_KEY' (ecdsa-p256)"
fresh_key "$SIGN_KEY" ecdsa-p256
SIG=$(bao write -field=signature "$MOUNT/sign/$SIGN_KEY" input="$(b64 "$PLAINTEXT")")
[ "$(bao write -field=valid "$MOUNT/verify/$SIGN_KEY" input="$(b64 "$PLAINTEXT")" signature="$SIG")" = "true" ] \
    && pass "signature verifies" || fail "signature does not verify"
[ "$(bao write -field=valid "$MOUNT/verify/$SIGN_KEY" input="$(b64 "${PLAINTEXT}tampered")" signature="$SIG")" = "false" ] \
    && pass "a tampered message is rejected" || fail "tampered message accepted"

echo "--> 7. Least privilege: an application token that can only encrypt and decrypt"
bao policy write ra-console-transit - >/dev/null <<EOF
path "$MOUNT/encrypt/$KEY" { capabilities = ["update"] }
path "$MOUNT/decrypt/$KEY" { capabilities = ["update"] }
EOF
APP_TOKEN=$(bao token create -policy=ra-console-transit -ttl=15m -field=token)
BAO_TOKEN="$APP_TOKEN" bao write "$MOUNT/encrypt/$KEY" plaintext="$(b64 "$PLAINTEXT")" >/dev/null \
    && pass "application token can encrypt" || fail "application token cannot encrypt"
if BAO_TOKEN="$APP_TOKEN" bao write -f "$MOUNT/keys/$KEY/rotate" >/dev/null 2>&1; then
    fail "application token rotated the key"
fi
pass "application token cannot rotate the key"
if BAO_TOKEN="$APP_TOKEN" bao read "$MOUNT/keys/$KEY" >/dev/null 2>&1; then
    fail "application token read the key configuration"
fi
pass "application token cannot read the key configuration"

echo "--> TRANSIT DEMO COMPLETE"
