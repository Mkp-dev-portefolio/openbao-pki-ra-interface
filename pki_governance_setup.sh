#!/bin/bash
set -e

# Configuration
export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BINARY="/opt/homebrew/bin/bao"

echo "Using OpenBao at $BAO_ADDR"

# 1. Enable Userpass Auth Method
echo "--> Enabling Userpass Auth Method..."
$BINARY auth enable userpass || true

# 2. Create RA Admin Policy
echo "--> Creating 'ra-admin-policy'..."
$BINARY policy write ra-admin-policy - <<EOF
# Manage PKI Roles (Onboard new teams)
path "pki_int/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Sign Intermediates (if needed, usually higher level, but RA might rotate)
path "pki_int/root/sign-intermediate" {
  capabilities = ["create", "update"]
}

# Revoke Certificates
path "pki_int/revoke" {
  capabilities = ["create", "update"]
}

# Read PKI Config
path "pki_int/config/*" {
  capabilities = ["read"]
}

# List Certificates
path "pki_int/certs" {
  capabilities = ["list"]
}
path "pki_int/cert/*" {
  capabilities = ["read"]
}

# Manage Access Policies (Required to onboard new teams)
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage Users (Required to give teams access)
path "auth/userpass/users/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# 3. Create Team Policy Template (Example for a generic team)
# This allows a team to issuance certs ONLY from their specific role
echo "--> Creating 'team-red-policy'..."
$BINARY policy write team-red-policy - <<EOF
# Request certificates from their role
path "pki_int/issue/team-red" {
  capabilities = ["create", "update"]
}

# Read their own certs? (Optional, usually they just get the response)
EOF

# 4. Create RA Admin User
echo "--> Creating user 'ra-operator' (password: ra-secret)..."
$BINARY write auth/userpass/users/ra-operator \
    password="ra-secret" \
    policies="ra-admin-policy"

# 5. Create Team Red User (Simulating an onboarded team lead)
echo "--> Creating user 'team-red-lead' (password: red-secret)..."
$BINARY write auth/userpass/users/team-red-lead \
    password="red-secret" \
    policies="team-red-policy"

echo "--> Governance Setup Complete!"
