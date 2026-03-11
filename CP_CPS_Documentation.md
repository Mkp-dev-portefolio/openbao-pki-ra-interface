# Energy Corp PKI: CP & CPS Documentation

## 1. Introduction & Concepts
This document unifies the **Certificate Policy (CP)** and **Certification Practice Statement (CPS)** for the Energy Corp Public Key Infrastructure (PKI).

- **CP (Certificate Policy)**: The "Law". Defines *what* certificates are for, *who* can get them, and *what* rules apply. (e.g., "Only Energy Corp devices can have certificates").
- **CPS (Certification Practice Statement)**: The "Implementation". Defines *how* the CP is enforced technically. (e.g., "We use OpenBao v2.4 running on Kubernetes to issue certificates").

---

## 2. Certificate Policy (CP) - The Rules

### 2.1 Overview
This PKI is established to secure internal communications for Energy Corp's IT and OT (Operational Technology) environments.

### 2.2 Identification & Authentication
- **Human Applicants**: Must be verified employees (Team Leads) authenticated via the corporate Identity Provider (simulated via `userpass`).
- **Device Applicants**: Must prove identity via automated protocols (ACME) or trusted provisioning scripts.
- **Naming Constraints**:
  - Organization (`O`) must be "Energy Corp".
  - Organizational Unit (`OU`) must match the assigned Division (e.g., "Solar Div").

### 2.3 Allowed Uses
- **Server Authentication**: TLS for internal web services and APIs.
- **Client Authentication**: Mutual TLS (mTLS) for microservices and smart meters.
- **Forbidden Uses**: Public internet trust (this is a private PKI), Code Signing (unless explicitly authorized).

---

## 3. Certification Practice Statement (CPS) - The Implementation

### 3.1 Architecture Review
The PKI is hierarchical, consisting of three active Certificate Authorities (CAs):

1.  **Energy Company Root CA**: The trust anchor.
2.  **K8s Intermediate CA (Online)**: High-volume, short-lived certificates for cloud workloads.
3.  **Offline-Signed Intermediate CA**: High-assurance certificates for sensitive/static infrastructure.

### 3.2 Service Endpoints (The URLs)
This section documents the specific technical endpoints configured in the system.

#### A. Energy Company Root CA (`pki_root`)
| Service | URL / Endpoint | Purpose |
| :--- | :--- | :--- |
| **Issuing CA** | `http://openbao.openbao.svc:8200/v1/pki_root/ca` | Download Root Cert |
| **CRL** | `http://openbao.openbao.svc:8200/v1/pki_root/crl` | Root Revocation List |

#### B. K8s Intermediate CA (`pki_int`) - *ACME Enabled*
| Service | URL / Endpoint | Purpose |
| :--- | :--- | :--- |
| **ACME Directory** | `http://openbao.openbao.svc:8200/v1/pki_int/acme/directory` | **Automated Issuance** |
| **CRL** | `http://openbao.openbao.svc:8200/v1/pki_int/crl` | Check Revocation (Batch) |
| **OCSP** | `http://openbao.openbao.svc:8200/v1/pki_int/ocsp` | Check Revocation (Real-time) |
| **AIA / Issuer** | `http://openbao.openbao.svc:8200/v1/pki_int` | Download Intermediate Cert |

#### C. Offline-Signed Intermediate CA (`pki_offline_int`)
| Service | URL / Endpoint | Purpose |
| :--- | :--- | :--- |
| **CRL** | `http://127.0.0.1:8200/v1/pki_offline_int/crl` | Revocation List |
| **OCSP** | `http://127.0.0.1:8200/v1/pki_offline_int/ocsp` | Revocation Responder |

*(Note: In the PoC, URLs use `openbao.openbao.svc` for internal K8s traffic or `127.0.0.1` for local testing. In Production, these would be `https://pki.energy.internal/...`)*

### 3.3 Lifecycle Procedures

#### Key Generation
- **Root CA**: Generated in software (OpenSSL), meant to be stored in an offline/air-gapped safe (Soft HSM). key size: RSA 4096.
- **Intermediates**: Generated on the OpenBao server (Software-backed). Key size: RSA 2048 or 4096.

#### Validation Methods
- **ACME (Automated)**:
  - We use `cert-manager` as the client.
  - OpenBao validates the request against defined `roles` (e.g., `project-solar`).
  - **Why?**: Speed and scale. Cloud workloads (Pods) spin up/down too fast for manual tickets.
- **Manual (SOP-002)**:
  - Used for the "Offline Int" or special requests.
  - Requires specific Governance approval (RA checks).

#### Revocation
- **Process**: Revocation is triggered via the API by an authorized Admin (`ra-operator`).
- **Publication**:
    - **CRLs**: Regenerated automatically by OpenBao on every revocation (or strictly rotated).
    - **OCSP**: Real-time lookups supported natively by the OpenBao backend.
- **Why?**: OCSP is preferred for modern clients to avoid downloading large CRL files.

---

## 4. Design Decisions (Why we did it this way)

### Why OpenBao for PKI?
 Traditional CAs (Microsoft AD CS, EJBCA) are complex to automate. OpenBao builds "PKI as a Service" natively, allowing us to expose **ACME** endpoints trivially. This bridges the gap between traditional Security (Compliance) and modern DevOps (Velocity).

### Why Split Online vs. Offline Intermediates?
- **Online (pki_int)**: Optimized for availability. If the key is compromised, we revoke the intermediate, but the Root remains safe. This CA issues certs with short TTLs (e.g., 24h) to minimize risk.
- **Offline (pki_offline_int)**: Optimized for stability. Used for things that change rarely (firewalls, routers). Only accessed when needed.

### Why ACME?
The **ACME Protocol** (RFC 8555) eliminates manual key handling.
- **Security**: Private keys are generated on the destination server (the K8s Pod), never transmitted over the network.
- **Reliability**: Certificates renew automatically before expiry, preventing outages.
