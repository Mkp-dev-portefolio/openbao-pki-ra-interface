#!/bin/bash
set -e

# Configuration
export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BINARY="/opt/homebrew/bin/bao"

# Hostname for OCSP access (needs to be reachable by openssl command)
# In local dev, localhost:8200 is fine.
OCSP_URL="$BAO_ADDR/v1/pki_offline_int/ocsp"
CRL_URL="$BAO_ADDR/v1/pki_offline_int/crl"

echo "--> START: Revocation Configuration & Verification"

# 1. Configure CRL and OCSP URLs
echo "--> Configuring Revocation URLs..."
$BINARY write pki_offline_int/config/urls \
    issuing_certificates="$BAO_ADDR/v1/pki_offline_int/ca" \
    crl_distribution_points="$CRL_URL" \
    ocsp_servers="$OCSP_URL"

# 2. Issue a Test Certificate
echo "--> Creating Role 'test-revocation'..."
$BINARY write pki_offline_int/roles/test-revocation \
    allowed_domains="revocation.test" \
    allow_subdomains=true \
    max_ttl="24h"

echo "--> Issuing Certificate to be revoked..."
# Capture Serial Number
CERT_JSON=$($BINARY write -format=json pki_offline_int/issue/test-revocation common_name="victim.revocation.test")
SERIAL=$(echo $CERT_JSON | jq -r '.data.serial_number')
echo $CERT_JSON | jq -r '.data.certificate' > victim.crt
echo $CERT_JSON | jq -r '.data.issuing_ca' > issuer.crt

echo "   Issued Serial: $SERIAL"

# 3. Revoke the Certificate
echo "--> Revoking Certificate..."
$BINARY write pki_offline_int/revoke serial_number=$SERIAL

# 4. Verify CRL
echo "--> Verifying CRL..."
# Force CRL rotation/build to ensure immediate update? OpenBao usually auto-rebuilds or we can trigger.
# Sometimes 'rotate' or just wait. 
# Fetches the CRL
curl -s $CRL_URL > revocation.crl
# Check if serial is present (grep might fail if binary/DER, openssl parse is safer)
# OpenBao CRL is usually PEM or DER? PEM by default on the endpoint unless ?format=der
# Default is often DER (binary). Let's start by trying openssl crl -inform DER
if openssl crl -inform DER -in revocation.crl -text -noout 2>/dev/null | grep -q "$SERIAL"; then
    echo "   [PASS] Serial found in DER CRL."
elif openssl crl -inform PEM -in revocation.crl -text -noout 2>/dev/null | grep -q "$SERIAL"; then
    echo "   [PASS] Serial found in PEM CRL."
else
    echo "   [FAIL] Serial NOT found in CRL."
    # We won't exit, we try OCSP.
fi

# 5. Verify OCSP
echo "--> Verifying OCSP..."
# We use openssl ocsp client
# Needs issuer cert and the cert to check.
echo "   Querying OCSP Responder..."
OPENSSL_OCSP_OUT=$(openssl ocsp -issuer issuer.crt -cert victim.crt -url $OCSP_URL -text 2>&1)

if echo "$OPENSSL_OCSP_OUT" | grep -q "Cert Status: revoked"; then
    echo "   [PASS] OCSP reports: REVOKED"
else
    echo "   [FAIL] OCSP did not report revoked."
    echo "$OPENSSL_OCSP_OUT"
    exit 1
fi

echo "--> REVOCATION VERIFIED SUCCESSFUL"
