#!/bin/bash
set -e

# Configuration
export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BINARY="/opt/homebrew/bin/bao"

echo "Using OpenBao at $BAO_ADDR with token $BAO_TOKEN"

# 1. Enable PKI Engine for Root CA
echo "--> Enabling PKI engine for Root CA at pki_root..."
$BINARY secrets enable -path=pki_root pki || true
$BINARY secrets tune -max-lease-ttl=87600h pki_root

# 2. Generate Root CA
echo "--> Generating Internal Root CA..."
$BINARY write -field=certificate pki_root/root/generate/internal \
    common_name="Energy Company Root CA" \
    ttl=87600h > root_ca.crt

# 3. Configure Root CA URL
echo "--> Configuring Root CA URLs..."
$BINARY write pki_root/config/urls \
    issuing_certificates="$BAO_ADDR/v1/pki_root/ca" \
    crl_distribution_points="$BAO_ADDR/v1/pki_root/crl"

# 4. Enable PKI Engine for Intermediate CA
echo "--> Enabling PKI engine for Intermediate CA at pki_int..."
$BINARY secrets enable -path=pki_int pki || true
$BINARY secrets tune -max-lease-ttl=43800h pki_int

# 5. Generate CSR for Intermediate CA
echo "--> Generating CSR for Intermediate CA..."
$BINARY write -format=json pki_int/intermediate/generate/internal \
    common_name="Energy Company Operations Intermediate CA" \
    | jq -r '.data.csr' > pki_int.csr

# 6. Sign Intermediate CA with Root CA
echo "--> Signing Intermediate CA CSR with Root CA..."
$BINARY write -format=json pki_root/root/sign-intermediate \
    csr=@pki_int.csr \
    format=pem_bundle \
    ttl=43800h \
    | jq -r '.data.certificate' > intermediate.crt

# 7. Import Signed Certificate back to Intermediate CA
echo "--> Importing signed Intermediate CA certificate..."
$BINARY write pki_int/intermediate/set-signed certificate=@intermediate.crt

# 8. Configure Intermediate CA Role - Smart Meter
echo "--> Creating 'smart-meter' role..."
$BINARY write pki_int/roles/smart-meter \
    allowed_domains="meter.energy.internal" \
    allow_subdomains=true \
    max_ttl=720h \
    client_flag=true \
    server_flag=true

# 9. Configure Intermediate CA Role - SCADA System
echo "--> Creating 'scada-system' role..."
$BINARY write pki_int/roles/scada-system \
    allowed_domains="scada.energy.internal" \
    allow_subdomains=true \
    max_ttl=720h \
    client_flag=true \
    server_flag=true

# 10. Configure Intermediate CA Role - Corporate User
echo "--> Creating 'corporate-user' role..."
$BINARY write pki_int/roles/corporate-user \
    allowed_domains="corp.energy.internal" \
    allow_subdomains=true \
    max_ttl=24h \
    client_flag=true \
    server_flag=false

echo "--> Setup Complete!"
