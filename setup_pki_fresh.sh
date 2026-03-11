#!/bin/bash
set -e

# Config
export PAGER=cat
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
# OpenBao helper
alias bao="/opt/homebrew/bin/bao"

echo "--> Checking status..."
bao status || { echo "OpenBao not running?"; exit 1; }

echo "--> Mounting PKI Root..."
bao secrets enable -path=pki_root pki || echo "Already mounted?"
bao secrets tune -max-lease-ttl=87600h pki_root

echo "--> Generating Root CA..."
bao write -field=certificate pki_root/root/generate/internal \
    common_name="Energy Company Root CA" ttl=87600h > root_ca.crt

echo "--> Configuring Root URLs..."
bao write pki_root/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki_root/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki_root/crl"

echo "--> Mounting PKI Int..."
bao secrets enable -path=pki_int pki || echo "Already mounted pki_int?"
bao secrets tune -max-lease-ttl=43800h pki_int

echo "--> Generating Int CSR..."
bao write -format=json pki_int/intermediate/generate/internal \
    common_name="Energy Company K8s Intermediate CA" | jq -r '.data.csr' > pki_int.csr

echo "--> Signing Int CSR..."
bao write -format=json pki_root/root/sign-intermediate \
    csr=@pki_int.csr format=pem_bundle ttl=43800h | jq -r '.data.certificate' > intermediate.crt

echo "--> Setting Signed Int Cert..."
bao write pki_int/intermediate/set-signed certificate=@intermediate.crt

echo "--> Configuring Int URLs..."
bao write pki_int/config/cluster \
    path="$VAULT_ADDR/v1/pki_int" \
    aia_path="$VAULT_ADDR/v1/pki_int"

echo "--> Enabling ACME (The Critical Step)..."
# Tuning headers for ACME
bao write sys/mounts/pki_int/tune \
    allowed_response_headers="Last-Modified,Location,Replay-Nonce,Link" \
    passthrough_request_headers="Authorization"

# Enable ACME config
bao write pki_int/config/acme enabled=true allowed_cidrs="*"

echo "--> Creating ACME Role..."
bao write pki_int/roles/acme-default \
    allowed_domains="*" \
    allow_subdomains=true \
    allow_any_name=true \
    max_ttl=720h \
    no_store=false

echo "--> Setup Complete. Verifying ACME Directory..."
curl -s "$VAULT_ADDR/v1/pki_int/acme/directory" | jq .
