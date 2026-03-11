#!/bin/bash
set -e

# Configuration
export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BINARY="/opt/homebrew/bin/bao"
SAFE_DIR="./offline_hsm"

echo "--> START: Simulating Offline Root CA (Soft HSM)"

# 1. Setup 'Safe' Directory (Offline Environment)
mkdir -p $SAFE_DIR
chmod 700 $SAFE_DIR

# 2. Generate Offline Root CA (OpenSSL)
echo "--> [Offline] Generating Root Key & Cert in $SAFE_DIR..."
# Generating encrypted key (passphrase: "root-secret")
openssl genrsa -aes256 -passout pass:root-secret -out $SAFE_DIR/root_ca.key 4096
# Generating Self-Signed Root Cert
openssl req -new -x509 -days 3650 -key $SAFE_DIR/root_ca.key -sha256 \
    -extensions v3_ca \
    -passin pass:root-secret \
    -out $SAFE_DIR/root_ca.crt \
    -subj "/C=US/O=Energy Corp/CN=Offline Root CA"

echo "   Success: Root CA created."

# 3. Setup NEW Intermediate CA in OpenBao (pki_offline_int)
# We use a new mount to demonstrate the clean break from the previous 'pki_root'
echo "--> [Online] Enabling new Intermediate CA mount 'pki_offline_int'..."
$BINARY secrets enable -path=pki_offline_int pki || true
$BINARY secrets tune -max-lease-ttl=43800h pki_offline_int

echo "--> [Online] Generating CSR for Intermediate CA..."
$BINARY write -format=json pki_offline_int/intermediate/generate/internal \
    common_name="Energy Corp Offline-Signed Intermediate" \
    | jq -r '.data.csr' > $SAFE_DIR/pki_int.csr

# 4. Sign CSR with Offline Root (The "Ceremony")
echo "--> [Offline] Signing Intermediate CSR..."
# Create extfile for V3 extensions (CA:TRUE)
cat > $SAFE_DIR/extensions.cnf <<EOF
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

openssl x509 -req -days 1825 -in $SAFE_DIR/pki_int.csr \
    -CA $SAFE_DIR/root_ca.crt -CAkey $SAFE_DIR/root_ca.key -CAcreateserial \
    -out $SAFE_DIR/intermediate.crt -sha256 \
    -extfile $SAFE_DIR/extensions.cnf -extensions v3_ca \
    -passin pass:root-secret

echo "   Success: Intermediate Certificate Signed."

# 5. Import Signed Cert to OpenBao
echo "--> [Online] Importing Signed Certificate..."
# We need to act carefully here: OpenBao expects the chain.
# Concatenate Intermediate + Root for the bundle? usually set-signed just takes the cert if we provide the chain separate?
# Let's try just the cert first, or append root.
cat $SAFE_DIR/intermediate.crt $SAFE_DIR/root_ca.crt > $SAFE_DIR/bundle.pem
$BINARY write pki_offline_int/intermediate/set-signed certificate=@$SAFE_DIR/bundle.pem

echo "--> [Online] Success! pki_offline_int is now active and rooted by the Offline CA."
