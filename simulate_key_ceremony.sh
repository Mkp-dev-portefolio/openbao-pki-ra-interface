#!/bin/bash
set -e

# Configuration
export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BINARY="/opt/homebrew/bin/bao"
SAFE_DIR="./offline_hsm"

echo "--> START: Key Ceremony Simulation (Client Auth & S/MIME)"

# 0. Check for Offline Root
if [ ! -f "$SAFE_DIR/root_ca.key" ]; then
    echo "   [Error] Offline Root Key not found in $SAFE_DIR. Please run simulate_offline_hsm.sh first."
    exit 1
fi

# 1. NEW Intermediate CA (Simulating HSM-backed CA)
# Mount path: pki_client_smime
echo "--> [Online] Enabling 'pki_client_smime'..."
$BINARY secrets enable -path=pki_client_smime pki || true
$BINARY secrets tune -max-lease-ttl=43800h pki_client_smime

# 2. Generate CSR (Simulating Step 4 of the Procedure)
# In a real HSM setup, 'type' would be 'kms' or 'existing'. Here we use 'internal' as the SoftHSM proxy.
echo "--> [Online] Generating CSR for Issuing CA..."
$BINARY write -format=json pki_client_smime/intermediate/generate/internal \
    common_name="Energy Corp Client & S/MIME CA" \
    ou="IT Security" \
    organization="Energy Corp" \
    | jq -r '.data.csr' > $SAFE_DIR/client_smime.csr

echo "   CSR exported to $SAFE_DIR/client_smime.csr"

# 3. Sign CSR with Offline Root (The "Ceremony")
echo "--> [Offline] Ceremony Administrator signing CSR..."

# Extensions for Issuing CA
cat > $SAFE_DIR/v3_issuing.cnf <<EOF
[v3_ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
extendedKeyUsage = clientAuth, emailProtection
EOF

openssl x509 -req -days 1825 -in $SAFE_DIR/client_smime.csr \
    -CA $SAFE_DIR/root_ca.crt -CAkey $SAFE_DIR/root_ca.key -CAcreateserial \
    -out $SAFE_DIR/client_smime.crt -sha256 \
    -extfile $SAFE_DIR/v3_issuing.cnf -extensions v3_ca \
    -passin pass:root-secret

echo "   Certificate Signed: $SAFE_DIR/client_smime.crt"

# 4. Import & Activate
echo "--> [Online] Importing Signed Certificate..."
# Bundle with Root
cat $SAFE_DIR/client_smime.crt $SAFE_DIR/root_ca.crt > $SAFE_DIR/client_smime_bundle.pem
$BINARY write pki_client_smime/intermediate/set-signed certificate=@$SAFE_DIR/client_smime_bundle.pem

# 5. Configure Roles for Use Cases
echo "--> [Online] Configuring Roles..."

# Role 1: Client Authentication (for mTLS)
echo "   Creating Role: client-auth-role"
$BINARY write pki_client_smime/roles/client-auth-role \
    allowed_domains="devices.energy.internal" \
    allow_subdomains=true \
    max_ttl="24h" \
    key_usage="DigitalSignature" \
    client_flag=true \
    server_flag=false

# Role 2: S/MIME (Email Signing)
echo "   Creating Role: email-signing-role"
$BINARY write pki_client_smime/roles/email-signing-role \
    allowed_domains="energy.corp" \
    allow_subdomains=false \
    max_ttl="720h" \
    key_usage="DigitalSignature,NonRepudiation" \
    email_protection_flag=true \
    client_flag=false \
    server_flag=false \
    require_cn=false \
    allowed_uri_sans="email:*"

echo "--> CEREMONY SIMULATION COMPLETE"
echo "   New CA 'pki_client_smime' is active and configured."
