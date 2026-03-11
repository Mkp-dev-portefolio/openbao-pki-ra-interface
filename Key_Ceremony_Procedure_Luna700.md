# Key Ceremony Procedure: Thales Luna 700 HSM

## 1. Overview
This document defines the formal procedure for generating a Cryptographic Key Pair for an Issuing Certificate Authority (CA) using a **Thales Luna 700 Series Network HSM**.

**Objective**: Securely generate the RSA 4096-bit key pair within the HSM boundary and export a Certificate Signing Request (CSR).

## 2. Roles & Quorums
To ensure 'Two-Person Integrity', the following roles must be present:

| Role | Responsibility | Auth Token (PED Key) |
| :--- | :--- | :--- |
| **Ceremony Administrator** | Runs commands, manages the laptop. | N/A |
| **HSM Security Officer (SO)** | Administer the HSM, create partitions. | **Blue Key** |
| **Partition Owner (PO)** | Initialize partition, manage access. | **Red Key** (or Black) |
| **Crypto Officer (CO)** | Create keys, sign objects. | **Red Key** |
| **Domain Manager** | Manage cloning domain (backups). | **Red Key** (Domain) |
| **Witnesses (2)** | Observe and log the ceremony. | N/A |

## 3. Preparation
1.  **Safe Retrieval**: Retrieve the HSM PED Keys and Admin Smartcards from the safe.
2.  **Air Gap**: Ensure the Ceremony Laptop is disconnected from all external networks (except the direct HSM link or Management VLAN).
3.  **Remote Connect**: Ensure `pedserver` is running on the local laptop with the Remote PED connected via USB.

## 4. Procedure Steps

### Phase 0: Remote PED Connection
1.  **Start Local PED Server**:
    ```bash
    # On Admin Laptop
    pedserver mode start
    pedserver -mode show  # Verify listening IP/Port
    ```
2.  **Bind HSM to Remote PED**:
    ```bash
    lunacm:> hsm ped connect -ip <Laptop_IP> -port 1503
    ```
    *Verification*: HSM confirms connection to Remote PED.

### Phase 1: Partition Creation (SO Action)
1.  **Login**:
    ```bash
    lunacm:> hsm login
    # Insert BLUE PED Key into REMOTE PED
    ```

2.  **Create Partition**:
    ```bash
    lunacm:> partition create -partition IssuingCA_Part -label "Issuing CA Partition"
    ```
3.  **Logout**:
    ```bash
    lunacm:> hsm logout
    ```

### Phase 2: Partition Initialization (PO Action)
1.  **Select Partition**:
    ```bash
    lunacm:> slot set -slot <slot_id>
    ```
2.  **Initialize**:
    ```bash
    lunacm:> partition init -label "IssuingCA"
    # Insert RED Key into REMOTE PED (to create new PO auth)
    # Insert RED Domain Key into REMOTE PED (to set cloning domain)
    ```
3.  **Login as Partition SO**:
    ```bash
    lunacm:> role login -name po
    # Insert RED Key into REMOTE PED
    ```
4.  **Create Crypto Officer (CO)**:
    ```bash
    lunacm:> role create -name co
    # Assign password/challenge
    ```

### Phase 3: Key Generation (CO Action)
1.  **Login as CO**:
    ```bash
    lunacm:> role login -name co
    ```
2.  **Generate Key Pair**:
    ```bash
    lunacm:> cmu gen -modulus 4096 -publicExp 65537 -sign -verify -label "EnergyCorp_IssuingCA_v1"
    ```
    *Witness Verification*: Confirm `Success` message and Key Handle ID.

### Phase 4: CSR Creation (Integration)
1.  **OpenBao Configuration**: Use the PKCS#11 library to point OpenBao to the HSM slot.
2.  **Generate CSR (via OpenBao)**:
    ```bash
    bao write pki/intermediate/generate/exported type=existing key_ref="EnergyCorp_IssuingCA_v1" ...
    ```
    *Note: The private key NEVER leaves the HSM. OpenBao asks the HSM to sign the CSR.*

3.  **Save CSR**: Copy `issuing_ca.csr` to a USB drive for transport to the Root CA.

## 5. Teardown
1.  **Backup**: Execute Key Backup procedure (Token Backup).
2.  **Log**: Witnesses sign the Ceremony Log.
3.  **Secure Storage**: Return PED Keys to the safe.
