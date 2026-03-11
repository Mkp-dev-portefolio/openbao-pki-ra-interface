# PKI Architecture (Archimate View)

This document visualizes the Energy Corp PKI using Archimate notation (via Mermaid).

```mermaid
graph TD
    %% Styling - Archimate Colors approximation
    classDef business fill:#ffff99,stroke:#d4a017,stroke-width:2px;
    classDef app fill:#b3e0ff,stroke:#0073e6,stroke-width:2px;
    classDef tech fill:#ccffcc,stroke:#248f24,stroke-width:2px;

    %% Business Layer (Yellow)
    subgraph Business["Business Layer"]
        RA_Actor("Registration Authority (RA)"):::business
        HSM_SO("HSM Security Officer"):::business
        Process_Onboard("Process: Onboarding (SOP-001)"):::business
        Process_Ceremony("Process: Key Ceremony"):::business
        Policy("Policy: Strict X.509"):::business
    end

    %% Application Layer (Blue)
    subgraph Application["Application Layer"]
        Svc_RA_Int("Service: RA Interface"):::app
        Svc_PKI_Int("Service: OpenBao PKI (Online)"):::app
        Svc_ACME("Service: ACME Protocol"):::app
        App_CertManager("Client: Cert-Manager"):::app
    end

    %% Technology Layer (Green)
    subgraph Technology["Technology Layer"]
        Node_K8s("Node: Kubernetes (Kind)"):::tech
        Node_Offline("Node: Offline Safe"):::tech
        Dev_HSM("Device: Luna 700 (Remote PED)"):::tech
    end

    %% Relations
    RA_Actor -->|Executes| Process_Onboard
    HSM_SO -->|Executes| Process_Ceremony
    
    Process_Onboard -->|Uses| Svc_RA_Int
    Process_Ceremony -->|Operates| Dev_HSM
    
    Svc_RA_Int -->|Configures| Svc_PKI_Int
    Svc_RA_Int -.->|Enforces| Policy
    
    App_CertManager -->|Consumes| Svc_ACME
    Svc_ACME -->|Interface Of| Svc_PKI_Int
    
    Svc_PKI_Int -->|Hosted On| Node_K8s
    Dev_HSM -->|Signs Keys For| Svc_PKI_Int
    Node_Offline -->|Root Trust For| Svc_PKI_Int

```

## Interpretation
1.  **Business Layer**: The **RA** executes the **Onboarding Process**, translating business requirements into technical policies. The **HSM SO** executes the **Key Ceremony**.
2.  **Application Layer**: **OpenBao** serves as the central PKI engine, exposing **ACME** for automation (consumed by `cert-manager`) and API endpoints for RA management.
3.  **Technology Layer**: The system rests on **Kubernetes**, but relies on the physical **Luna 700 HSM** (accessed via Remote PED) and the **Offline Root** (Safe) for high-assurance trust anchors.
