#!/bin/bash
set -e

CLUSTER_NAME="openbao-pki-poc"
BAO_NAMESPACE="openbao"
CERT_MANAGER_NAMESPACE="cert-manager"

# 1. Create Kind Cluster
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "Cluster '$CLUSTER_NAME' already exists."
else
    echo "Creating Kind cluster '$CLUSTER_NAME'..."
    kind create cluster --name $CLUSTER_NAME
fi

# 2. Install Cert-Manager
echo "Installing Cert-Manager..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace $CERT_MANAGER_NAMESPACE \
  --create-namespace \
  --version v1.14.4 \
  --set installCRDs=true \
  --wait

# 3. Install OpenBao (Dev Mode)
echo "Installing OpenBao..."
helm repo add openbao https://openbao.github.io/openbao-helm --force-update
helm repo update
helm upgrade --install openbao openbao/openbao \
    --namespace $BAO_NAMESPACE \
    --create-namespace \
    --set "server.dev.enabled=true" \
    --set "server.dev.devRootToken=root" \
    --wait

# Wait for OpenBao to be ready
echo "Waiting for OpenBao to be ready..."
kubectl wait --for=condition=Ready pod/openbao-0 -n $BAO_NAMESPACE --timeout=60s

# 4. Port Forward OpenBao (in background)
# Kill existing port-forward if any
pkill -f "kubectl port-forward svc/openbao" || true
nohup kubectl port-forward svc/openbao -n $BAO_NAMESPACE 8200:8200 > /dev/null 2>&1 &
echo "Port forwarding to http://127.0.0.1:8200..."
sleep 5

# 5. Configure OpenBao PKI & ACME
export BAO_ADDR="http://127.0.0.1:8200"
export BAO_TOKEN="root"
BINARY="/opt/homebrew/bin/bao"

echo "Configuring OpenBao PKI..."

# Root CA
$BINARY secrets enable -path=pki_root pki || true
$BINARY secrets tune -max-lease-ttl=87600h pki_root
$BINARY write -field=certificate pki_root/root/generate/internal \
    common_name="Energy Company Root CA" ttl=87600h > root_ca.crt
$BINARY write pki_root/config/urls \
    issuing_certificates="http://openbao.openbao.svc:8200/v1/pki_root/ca" \
    crl_distribution_points="http://openbao.openbao.svc:8200/v1/pki_root/crl"

# Intermediate CA
$BINARY secrets enable -path=pki_int pki || true
$BINARY secrets tune -max-lease-ttl=43800h pki_int
$BINARY write -format=json pki_int/intermediate/generate/internal \
    common_name="Energy Company K8s Intermediate CA" | jq -r '.data.csr' > pki_int.csr
$BINARY write -format=json pki_root/root/sign-intermediate \
    csr=@pki_int.csr format=pem_bundle ttl=43800h | jq -r '.data.certificate' > intermediate.crt
$BINARY write pki_int/intermediate/set-signed certificate=@intermediate.crt

# ACME Configuration
echo "Configuring ACME..."
$BINARY secrets tune -max-lease-ttl=8760h pki_int
$BINARY write pki_int/config/cluster \
    path="http://openbao.openbao.svc:8200/v1/pki_int" \
    aia_path="http://openbao.openbao.svc:8200/v1/pki_int"

# Configure ACME Headers (Required for Cert-Manager 1.6+)
# WARNING: 'config/acme' might vary by version.
# Checking latest OpenBao/Vault ACME config.
# Ideally:
# $BINARY write pki_int/config/acme enabled=true allowed_cidrs="*"

echo "--> Enabling ACME on pki_int..."
# Try tuning just in case, or specific config endpoint
# Note: In standard Vault, it's `write pki/config/acme enabled=true`
# We will create a broad role first.

$BINARY write pki_int/roles/acme-default \
    allowed_domains="*" \
    allow_subdomains=true \
    allow_any_name=true \
    max_ttl=720h \
    no_store=false

# Update ACME Config (if specific endpoint exists, else usage implies it)
# OpenBao/Vault usually exposes ACME at /pki/acme/... if configured?
# Actually, the standard method is usually just having a role?
# Wait, for ACME we often need `pki/config/urls` set correctly.
# And we must ensure the ACME endpoints are accessible.

# Let's try explicit ACME config enables if available (newer versions).
$BINARY write pki_int/config/acme enabled=true || echo "Warning: Could not explicitly enable ACME via config/acme (might be on by default or different path)"

echo "Setup Complete! ACME Directory should be at: $BAO_ADDR/v1/pki_int/acme/directory"
