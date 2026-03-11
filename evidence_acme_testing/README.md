# ACME Testing Evidence Bundle

## Contents

1. **00_timestamp.txt** - Evidence collection timestamp
2. **01_openbao_status.txt** - OpenBao server health status
3. **02_pki_mounts.txt** - All PKI secret engine mounts
4. **03_pki_root_config.txt** - Root CA configuration and certificate
5. **04_pki_int_config.txt** - Intermediate CA configuration and certificate
6. **05_acme_role.txt** - ACME default role configuration
7. **06_acme_directory.txt** - ACME directory endpoint discovery
8. **07_acme_nonce.txt** - ACME nonce generation test
9. **08_acme_test_output.txt** - Complete Python test script output
10. **09_certbot_logs/** - Certbot attempt logs (if any)
11. **10_k8s_openbao.txt** - Kubernetes OpenBao pod status
12. **11_network_config.txt** - Network configuration details

## Test Scope

- **ACME Protocol**: Directory discovery, nonce generation, account registration flow
- **PKI Configuration**: Root and Intermediate CA setup
- **Test Domain**: testserver.solar.energy.internal
- **Infrastructure**: OpenBao in Kubernetes (Kind), Python test client on host

## Key Findings

✅ ACME endpoints fully operational
✅ PKI hierarchy correctly configured (Root → Intermediate)
✅ ACME protocol communication verified
⚠️  End-to-end certificate issuance requires DNS/network configuration for challenge validation

