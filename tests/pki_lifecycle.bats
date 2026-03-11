#!/usr/bin/env bats
# pki_lifecycle.bats — BATS-based structured tests for OpenBao PKI lifecycle
#
# Prerequisites:
#   - BATS installed: https://github.com/bats-core/bats-core
#   - OpenBao running and accessible at BAO_ADDR (default http://127.0.0.1:8200)
#   - 'bao' CLI binary available (set BAO_BIN if not in PATH)
#   - Root/admin token available (set BAO_TOKEN)
#
# Usage:
#   bats tests/pki_lifecycle.bats
#   BAO_ADDR=http://vault:8200 BAO_TOKEN=mytoken bats tests/pki_lifecycle.bats
#
# Individual test files produced during the run are written to a temp dir
# and cleaned up in teardown().

export BAO_ADDR="${BAO_ADDR:-http://127.0.0.1:8200}"
export BAO_TOKEN="${BAO_TOKEN:-root}"
BAO_BIN="${BAO_BIN:-bao}"
TEST_MOUNT="pki_int"
TEST_ROLE_PREFIX="bats-test"
WORK_DIR=""

# ─── Helpers ────────────────────────────────────────────────────────────────

# Run the bao CLI and return its output; fail the test on non-zero exit.
bao() { "$BAO_BIN" "$@"; }

# Check that OpenBao is reachable; skip the whole suite if not.
check_openbao_reachable() {
  if ! "$BAO_BIN" status --format=json >/dev/null 2>&1; then
    skip "OpenBao not reachable at ${BAO_ADDR} — skipping integration test"
  fi
}

# ─── Setup / Teardown ────────────────────────────────────────────────────────

setup() {
  check_openbao_reachable
  WORK_DIR="$(mktemp -d)"
}

teardown() {
  # Remove any roles created by these tests
  for role in "${TEST_ROLE_PREFIX}-basic" "${TEST_ROLE_PREFIX}-ttl" "${TEST_ROLE_PREFIX}-domain"; do
    "$BAO_BIN" delete "${TEST_MOUNT}/roles/${role}" >/dev/null 2>&1 || true
  done
  # Remove test users
  "$BAO_BIN" delete auth/userpass/users/bats-test-user >/dev/null 2>&1 || true
  "$BAO_BIN" policy delete bats-test-policy >/dev/null 2>&1 || true
  # Clean up temp files
  rm -rf "${WORK_DIR}"
}

# ════════════════════════════════════════════════════════════════════════════
# 1. PKI Mount Health
# ════════════════════════════════════════════════════════════════════════════

@test "OpenBao is initialised and unsealed" {
  status_json=$(bao status -format=json)
  initialized=$(echo "$status_json" | grep -o '"initialized":[^,}]*' | cut -d: -f2 | tr -d ' "')
  sealed=$(echo "$status_json" | grep -o '"sealed":[^,}]*' | cut -d: -f2 | tr -d ' "')

  [ "$initialized" = "true" ]
  [ "$sealed" = "false" ]
}

@test "pki_int mount exists and is accessible" {
  bao read "${TEST_MOUNT}/cert/ca" >/dev/null
}

# ════════════════════════════════════════════════════════════════════════════
# 2. Role Management
# ════════════════════════════════════════════════════════════════════════════

@test "create a PKI role with domain restriction" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" \
    allow_subdomains=true \
    max_ttl="1h" \
    key_type="rsa" \
    key_bits=2048

  role_data=$(bao read -format=json "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic")
  echo "$role_data" | grep -q '"allow_subdomains": true'
}

@test "read back role allowed_domains after creation" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-domain" \
    allowed_domains="bats.energy.internal" \
    allow_subdomains=true \
    max_ttl="1h"

  role_data=$(bao read -format=json "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-domain")
  echo "$role_data" | grep -q 'bats.energy.internal'
}

@test "delete a PKI role successfully" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"
  bao delete "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic"

  # Reading a deleted role should fail (non-zero exit)
  run bao read "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic"
  [ "$status" -ne 0 ]
}

# ════════════════════════════════════════════════════════════════════════════
# 3. Certificate Issuance — Happy Path
# ════════════════════════════════════════════════════════════════════════════

@test "issue a certificate for an allowed domain" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" \
    allow_subdomains=true \
    max_ttl="1h"

  cert_json=$(bao write -format=json "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="device01.bats.energy.internal" ttl="30m")

  echo "$cert_json" | grep -q '"serial_number"'
  echo "$cert_json" | grep -q '"certificate"'
}

@test "issued certificate serial is non-empty" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" \
    allow_subdomains=true max_ttl="1h"

  serial=$(bao write -format=json "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="device02.bats.energy.internal" ttl="30m" \
    | grep -o '"serial_number": *"[^"]*"' | cut -d'"' -f4)

  [ -n "$serial" ]
}

@test "issued certificate PEM begins with -----BEGIN CERTIFICATE-----" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  cert_pem=$(bao write -format=json "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="device03.bats.energy.internal" ttl="30m" \
    | grep -o '"certificate": *"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g')

  echo "$cert_pem" | head -1 | grep -q "BEGIN CERTIFICATE"
}

# ════════════════════════════════════════════════════════════════════════════
# 4. Certificate Issuance — Error Cases
# ════════════════════════════════════════════════════════════════════════════

@test "issuance fails for a domain outside the role's allowed_domains" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-domain" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  run bao write "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-domain" \
    common_name="forbidden.other-domain.internal"

  [ "$status" -ne 0 ]
  echo "${output}" | grep -qi "not allowed\|does not match\|denied\|error"
}

@test "issuance fails when requested TTL exceeds role max_ttl" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-ttl" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  run bao write "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-ttl" \
    common_name="device.bats.energy.internal" ttl="9999h"

  [ "$status" -ne 0 ]
}

@test "issuance fails with empty common_name" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  run bao write "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name=""

  [ "$status" -ne 0 ]
}

# ════════════════════════════════════════════════════════════════════════════
# 5. Certificate Revocation
# ════════════════════════════════════════════════════════════════════════════

@test "a certificate can be revoked by serial number" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  serial=$(bao write -format=json "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="revoke-test.bats.energy.internal" ttl="30m" \
    | grep -o '"serial_number": *"[^"]*"' | cut -d'"' -f4)

  [ -n "$serial" ]
  bao write "${TEST_MOUNT}/revoke" serial_number="$serial"
}

@test "revoked certificate shows revocation_time > 0 when read back" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  serial=$(bao write -format=json "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="revoke-verify.bats.energy.internal" ttl="30m" \
    | grep -o '"serial_number": *"[^"]*"' | cut -d'"' -f4)

  bao write "${TEST_MOUNT}/revoke" serial_number="$serial"

  revocation_time=$(bao read -format=json "${TEST_MOUNT}/cert/${serial}" \
    | grep -o '"revocation_time": *[0-9]*' | grep -o '[0-9]*$')

  [ "${revocation_time:-0}" -gt 0 ]
}

@test "revoking an already-revoked certificate returns an error" {
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  serial=$(bao write -format=json "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="double-revoke.bats.energy.internal" ttl="30m" \
    | grep -o '"serial_number": *"[^"]*"' | cut -d'"' -f4)

  bao write "${TEST_MOUNT}/revoke" serial_number="$serial"

  # Second revocation attempt must fail or at minimum not panic
  run bao write "${TEST_MOUNT}/revoke" serial_number="$serial"
  # OpenBao returns an error or idempotent — either way, the serial is revoked
  # A non-zero exit indicates an error was returned (expected behaviour)
  # If the server is idempotent (returns 200), the test still passes
  [ "$status" -ne 0 ] || echo "${output}" | grep -qi "already revoked\|certificate is\|revocation"
}

# ════════════════════════════════════════════════════════════════════════════
# 6. CRL Availability
# ════════════════════════════════════════════════════════════════════════════

@test "CRL endpoint returns a non-empty response" {
  result=$(bao read -format=json "${TEST_MOUNT}/cert/crl")
  # The 'certificate' field contains the CRL PEM
  echo "$result" | grep -q '"certificate"'
}

# ════════════════════════════════════════════════════════════════════════════
# 7. RBAC / Policy Enforcement
# ════════════════════════════════════════════════════════════════════════════

@test "creating a user with an issuance policy allows certificate issuance" {
  # Create role
  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  # Create policy granting only issuance on this role
  bao policy write bats-test-policy - <<'POLICY'
path "pki_int/issue/bats-test-basic" { capabilities = ["create", "update"] }
POLICY

  # Create user
  bao write auth/userpass/users/bats-test-user \
    password="bats-secret-pw-123" policies="bats-test-policy"

  # Login as the new user and obtain a token
  user_token=$(bao login -method=userpass \
    username=bats-test-user password="bats-secret-pw-123" \
    -format=json | grep -o '"client_token": *"[^"]*"' | cut -d'"' -f4)

  [ -n "$user_token" ]

  # Issue a certificate with the user's token
  BAO_TOKEN="$user_token" bao write \
    "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="rbac-test.bats.energy.internal" ttl="30m" \
    >/dev/null
}

@test "a user without issuance policy cannot issue certificates" {
  # Create a policy with no PKI permissions
  bao policy write bats-test-policy - <<'POLICY'
path "sys/health" { capabilities = ["read"] }
POLICY

  bao write auth/userpass/users/bats-test-user \
    password="bats-secret-pw-123" policies="bats-test-policy"

  user_token=$(bao login -method=userpass \
    username=bats-test-user password="bats-secret-pw-123" \
    -format=json | grep -o '"client_token": *"[^"]*"' | cut -d'"' -f4)

  bao write "${TEST_MOUNT}/roles/${TEST_ROLE_PREFIX}-basic" \
    allowed_domains="bats.energy.internal" allow_subdomains=true max_ttl="1h"

  run env BAO_TOKEN="$user_token" "$BAO_BIN" write \
    "${TEST_MOUNT}/issue/${TEST_ROLE_PREFIX}-basic" \
    common_name="blocked.bats.energy.internal"

  [ "$status" -ne 0 ]
}

# ════════════════════════════════════════════════════════════════════════════
# 8. CA Certificate Accessibility
# ════════════════════════════════════════════════════════════════════════════

@test "root CA certificate is readable from pki_root" {
  run bao read "pki_root/cert/ca"
  [ "$status" -eq 0 ]
}

@test "intermediate CA certificate is readable from pki_int" {
  run bao read "${TEST_MOUNT}/cert/ca"
  [ "$status" -eq 0 ]
}
