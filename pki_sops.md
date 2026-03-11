# PKI Standard Operating Procedures (SOP)

## SOP-001: New Team Onboarding (RA Action)
**Objective**: Onboard a new internal team ("The Team") to the PKI system, enabling them to request certificates for their specific domain.

**Role Required**: Registration Authority (RA) / `ra-admin-policy`

**Steps**:
1. **Verify Identity**:
   - Confirm the request comes from an authorized Team Lead.
   - Verify the Team Name (e.g., "Team Blue") and Domain (e.g., `blue.energy.internal`).
2. **Define Role**:
   - Determine strict constraints:
     - `ou`: Must match Team Name.
     - `allowed_domains`: Must be strict subset of Team Domain.
     - `ttl`: Standard is 24h.
3. **Execute Onboarding (CLI)**:
   ```bash
   # Log in as RA
   bao login -method=userpass username=ra-operator
   
   # Create Role
   bao write pki_int/roles/team-blue \
       allowed_domains="blue.energy.internal" \
       allow_subdomains=true \
       organization="Energy Corp" \
       ou="Team Blue" \
       max_ttl="24h" \
       key_usage="DigitalSignature,KeyEncipherment" \
       client_flag=true \
       server_flag=true
   ```
4. **Create Access Policy**:
   - Create a policy allowing `update` on `pki_int/issue/team-blue`.
   - Create a user/token for the Team Lead attached to this policy.
5. **Notify Team**:
   - Securely transmit credentials to the Team Lead.

---

## SOP-002: Requesting a Certificate (Team Action)
**Objective**: Obtain a TLS certificate for a service.

**Role Required**: Team Member / `team-policy`

**Prerequisites**:
- You must have received onboarding credentials.
- You must have a CSR (Certificate Signing Request) generated on your server, OR allow OpenBao to generate the key (if permitted).

**Steps (CSR Method)**:
1. **Generate CSR (OpenSSL)**:
   ```bash
   openssl req -new -newkey rsa:2048 -nodes -keyout service.key -out service.csr \
     -subj "/C=US/O=Energy Corp/OU=Team Blue/CN=api.blue.energy.internal"
   ```
   *Note: Subject O and OU MUST match the Role definition or issuance will fail.*

2. **Submit to OpenBao**:
   ```bash
   # Log in
   bao login -method=userpass username=team-blue-lead
   
   # Write CSR
   bao write pki_int/sign/team-blue \
       csr=@service.csr \
       common_name="api.blue.energy.internal" \
       format=pem_bundle > cert_bundle.pem
   ```
   *Note: Use `sign` endpoint for CSRs, `issue` endpoint for auto-generation.*

---

## SOP-003: Identity Verification Checklist
**Objective**: Ensure only legitimate entities receive certificates.

| Check Item | Description | Pass/Fail |
| :--- | :--- | :--- |
| **Requester Auth** | Is the requester authenticated via a trusted method (SSO/Userpass)? | [ ] |
| **Domain Ownership** | Does the team "own" the requested subdomain in the internal DNS registry? | [ ] |
| **Naming Standard** | Does the CN follow `[service].[team].energy.internal`? | [ ] |
| **Organization** | Is `O=Energy Corp`? | [ ] |
| **Unit** | Is `OU=[Team Name]`? | [ ] |

If any check fails, **REJECT** the request.
