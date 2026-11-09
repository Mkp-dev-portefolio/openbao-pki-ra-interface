#!/bin/bash
# Auto-unseal demo: a Raft-backed OpenBao node protects its root key with a Transit key
# held by another OpenBao (the "unsealer"), so it unseals itself whenever it restarts.
#
#   ./setup_auto_unseal.sh           set up, initialise with recovery keys, prove a restart unseals
#   ./setup_auto_unseal.sh restart   restart the node and show its seal status
#   ./setup_auto_unseal.sh stop      stop the node
set -euo pipefail

BAO_BIN="${BAO_BIN:-$(command -v bao 2>/dev/null || echo /opt/homebrew/bin/bao)}"
UNSEALER_ADDR="${UNSEALER_ADDR:-${BAO_ADDR:-http://127.0.0.1:8200}}"
UNSEALER_TOKEN="${UNSEALER_TOKEN:-${BAO_TOKEN:-root}}"
NODE_PORT="${NODE_PORT:-8300}"
NODE_ADDR="http://127.0.0.1:${NODE_PORT}"
WORK_DIR="${WORK_DIR:-./auto_unseal_lab}"

unsealer() { BAO_ADDR="$UNSEALER_ADDR" BAO_TOKEN="$UNSEALER_TOKEN" command "$BAO_BIN" "$@"; }
seal_node() { BAO_ADDR="$NODE_ADDR" BAO_TOKEN="" command "$BAO_BIN" "$@"; }

mkdir -p "$WORK_DIR/data"
chmod 700 "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

stop_node() {
    if [ -f "$WORK_DIR/node.pid" ] && kill -0 "$(cat "$WORK_DIR/node.pid")" 2>/dev/null; then
        kill "$(cat "$WORK_DIR/node.pid")"
        while kill -0 "$(cat "$WORK_DIR/node.pid")" 2>/dev/null; do sleep 1; done
    fi
    rm -f "$WORK_DIR/node.pid"
}

start_node() {
    BAO_TOKEN="$(cat "$WORK_DIR/unseal.token")" \
        nohup "$BAO_BIN" server -config="$WORK_DIR/node.hcl" >> "$WORK_DIR/node.log" 2>&1 &
    echo $! > "$WORK_DIR/node.pid"
    # status exits 1 while the API is down, 2 while sealed, 0 once unsealed
    for _ in $(seq 1 30); do
        local rc=0
        seal_node status >/dev/null 2>&1 || rc=$?
        [ "$rc" -ne 1 ] && return 0
        kill -0 "$(cat "$WORK_DIR/node.pid")" 2>/dev/null || break
        sleep 1
    done
    rm -f "$WORK_DIR/node.pid"
    return 1
}

wait_unsealed() {
    for _ in $(seq 1 "${1:-30}"); do
        [ "$(seal_node status -format=json 2>/dev/null | jq -r '.sealed')" = "false" ] && return 0
        sleep 1
    done
    return 1
}

# OpenBao reports type "shamir" here even with a Transit seal; recovery_seal=true marks auto-unseal
show_status() {
    seal_node status -format=json 2>/dev/null | jq -r '"   auto-unseal (recovery_seal): \(.recovery_seal), initialized: \(.initialized), sealed: \(.sealed), storage: \(.storage_type)"' || true
}

case "${1:-}" in
    stop)
        stop_node
        echo "Node stopped."
        exit 0
        ;;
    restart)
        stop_node
        if ! start_node; then
            echo "   Node could not start: it cannot reach the unsealer, so it cannot read its root key."
            echo "   $(grep -i 'seal configuration' "$WORK_DIR/node.log" | tail -1)"
            exit 1
        fi
        wait_unsealed 10 || true
        show_status
        exit 0
        ;;
esac

echo "--> START: Transit auto-unseal (unsealer $UNSEALER_ADDR, node $NODE_ADDR)"

echo "--> 1. Unsealer: Transit key 'autounseal' and a token that can only use it"
unsealer status >/dev/null || { echo "   [FAIL] Unsealer not reachable at $UNSEALER_ADDR"; exit 1; }
unsealer secrets enable transit >/dev/null 2>&1 || true
unsealer read transit/keys/autounseal >/dev/null 2>&1 || unsealer write -f transit/keys/autounseal >/dev/null
unsealer policy write autounseal - >/dev/null <<EOF
path "transit/encrypt/autounseal" { capabilities = ["update"] }
path "transit/decrypt/autounseal" { capabilities = ["update"] }
EOF
if [ ! -s "$WORK_DIR/unseal.token" ]; then
    unsealer token create -orphan -policy=autounseal -period=24h -field=token > "$WORK_DIR/unseal.token"
    chmod 600 "$WORK_DIR/unseal.token"
fi

echo "--> 2. Node configuration: Raft storage and seal \"transit\""
cat > "$WORK_DIR/node.hcl" <<EOF
storage "raft" {
  path    = "$WORK_DIR/data"
  node_id = "node1"
}

# TLS is off for this local demo only; a production listener terminates TLS
listener "tcp" {
  address         = "127.0.0.1:$NODE_PORT"
  cluster_address = "127.0.0.1:$((NODE_PORT + 1))"
  tls_disable     = true
}

api_addr     = "$NODE_ADDR"
cluster_addr = "https://127.0.0.1:$((NODE_PORT + 1))"

seal "transit" {
  address    = "$UNSEALER_ADDR"
  key_name   = "autounseal"
  mount_path = "transit/"
}
EOF

stop_node
start_node || { echo "   [FAIL] Node did not start; see $WORK_DIR/node.log"; exit 1; }

if [ "$(seal_node status -format=json 2>/dev/null | jq -r '.initialized')" = "false" ]; then
    echo "--> 3. Initialising: auto-unseal issues recovery keys, not unseal keys"
    seal_node operator init -recovery-shares="${RECOVERY_SHARES:-1}" \
        -recovery-threshold="${RECOVERY_THRESHOLD:-1}" -format=json > "$WORK_DIR/init.json"
    chmod 600 "$WORK_DIR/init.json"
    echo "   Recovery key and root token saved to $WORK_DIR/init.json (demo only; in production"
    echo "   encrypt them to named custodians with -recovery-pgp-keys and -root-token-pgp-key)"
else
    echo "--> 3. Node already initialised"
fi
wait_unsealed || { echo "   [FAIL] Node did not unseal after initialisation"; exit 1; }
show_status

echo "--> 4. Restarting the node: it must unseal with no key holders"
stop_node
start_node || { echo "   [FAIL] Node did not restart; see $WORK_DIR/node.log"; exit 1; }
if wait_unsealed; then
    echo "   [PASS] Unsealed by the Transit key after restart"
else
    echo "   [FAIL] Node stayed sealed after restart"
    exit 1
fi
show_status

echo "--> AUTO-UNSEAL VERIFIED. Node running at $NODE_ADDR"
echo "    Outage test: stop the unsealer. This node keeps serving while it runs, but '$0 restart'"
echo "    fails because OpenBao cannot start without its seal. A dev-mode unsealer keeps its key in"
echo "    memory, so stopping it loses the key for good: that is the key-loss case."
echo "    Stop the node with '$0 stop'."
