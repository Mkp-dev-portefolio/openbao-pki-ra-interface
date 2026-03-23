# OpenBAO PKI Registration Authority Interface

A complete Registration Authority (RA) implementation for [OpenBAO](https://github.com/openbao/openbao) (the open-source HashiCorp Vault fork), covering the full certificate lifecycle from issuance to revocation — with HSM integration, ACME automation, Kubernetes deployment, and automated monitoring.

Built and validated as part of a production PKI deployment for IoT and enterprise environments.

---

## What This Is

In a PKI hierarchy, the Registration Authority sits between end entities and the issuing CA — it validates certificate requests, enforces policy, and delegates signing to the CA without exposing the CA directly. This repo implements that layer on top of OpenBAO's PKI secrets engine.

**Core capabilities:**

- RA web interface for certificate request management
- HSM integration: BouncyHSM (dev/test) and Luna 700 (production)
- ACME protocol support for automated certificate enrollment (certbot, k8s cert-manager)
- Certificate lifecycle monitoring with daily alerting
- Key ceremony procedures for offline and HSM-backed root CAs
- Kubernetes deployment manifests (client, test server, solar rollout scenario)
- Revocation (CRL) management and verification
- Pytest test suite covering onboarding and ACME enrollment flows

---

## Architecture

```
End Entities (servers, devices, users)
         |
   ACME / manual requests
         |
    RA Interface  <-- this repo
         |
   OpenBAO PKI Engine  (Intermediate CA)
         |
   Root CA (offline / HSM-backed)
         |
   Luna 700 HSM / BouncyHSM
```

Key architecture documents in this repo:
- `pki_architecture_archimate.md` — full ArchiMate PKI architecture
- `CP_CPS_Documentation.md` — Certificate Policy and CPS

---

## Repository Structure

```
ra-interface/          # Web RA interface (JS/CSS/HTML)
k8s_acme_client.yaml   # Kubernetes ACME cert-manager config
k8s_testserver.yaml    # Kubernetes TLS test server
k8s_poc_setup.sh       # K8s POC setup script
pki_poc_setup.sh       # Full PKI POC setup
setup_pki_fresh.sh     # Fresh environment setup
pki_governance_setup.sh # CA governance and policy setup
monitor_certificate_lifecycle.sh  # Daily cert monitoring
simulate_key_ceremony.sh          # Key ceremony simulation
simulate_offline_ceremony.py      # Offline CA ceremony (air-gapped)
simulate_offline_hsm.sh           # HSM ceremony simulation
test_acme_enrollment.py           # ACME enrollment test
test_onboarding_flow.sh           # End-to-end onboarding test
tests/                            # Pytest test suite
Key_Ceremony_Procedure_Luna700.md # Luna 700 key ceremony SOP
pki_sops.md                       # SOPS secrets management integration
```

---

## Quick Start

### Prerequisites

- OpenBAO running (see [openbao.org](https://openbao.org))
- Docker (for BouncyHSM dev environment)
- Python 3.9+ and pytest for tests
- kubectl + a running cluster for K8s deployment

### 1. Set up the PKI stack

```bash
# Fresh environment
./setup_pki_fresh.sh

# Or full POC setup (includes governance and policy)
./pki_poc_setup.sh
```

### 2. Start the RA interface

```bash
cd ra-interface
npm install
npm start
```

### 3. Run the test suite

```bash
pip install -r requirements-test.txt
pytest tests/
```

### 4. Enable certificate monitoring

```bash
# Install daily monitoring cron job
./setup_monitoring_cron.sh

# Or run manually
./monitor_certificate_lifecycle.sh
```

---

## HSM Integration

This repo has been tested with two HSM backends:

| HSM | Use case | Setup |
|---|---|---|
| **BouncyHSM** | Development and CI | Auto-configured via setup scripts |
| **Luna 700** | Production | See `Key_Ceremony_Procedure_Luna700.md` |

Key ceremony procedures follow a dual-control, split-knowledge model and are documented in `Key_Ceremony_Procedure_Luna700.md` and `pki_ceremony_architecture.archimate`.

---

## ACME Support

Certificate automation via ACME (RFC 8555) is supported for:

- Certbot (standard TLS certs)
- Kubernetes cert-manager (cluster-wide automation)
- Custom ACME clients (see `acme_testing_guide.md`)

ACME test evidence is archived in `acme_testing_evidence_20260207_014612.tar.gz`.

---

## License

MIT

---

*Part of the [MYKEYPAIR](https://mykeypair.be) PKI infrastructure toolkit.*
