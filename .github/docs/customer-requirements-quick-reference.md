# Customer Requirements Input - MVP Questionnaire

**Purpose**: Collect customer infrastructure requirements in 5 minutes.

> **Note**: For customers with existing Architecture Decision Records (ADR), see [adr-to-hub-extraction-guide.md](./adr-to-hub-extraction-guide.md) instead.

---

## ⚡ Customer Input Form (5 Minutes)

Ask customer these 9 questions in order:

```
┌──────────────────────────────────────────────────────┐
│ CUSTOMER REQUIREMENTS QUESTIONNAIRE                   │
└──────────────────────────────────────────────────────┘

1️⃣  Is your AKS cluster accessible from the internet?
    □ Yes (public)  □ No (private)

2️⃣  Should all outbound traffic be filtered/controlled?
    □ No (direct internet)  □ Yes (via firewall)

3️⃣  INGRESS ARCHITECTURE (4-part question)

    3a. Where will traffic to the AKS cluster originate?
        □ Public internet (external customers)
        □ Azure internal only (other Azure services)
        □ On-premises (ExpressRoute/VPN)
        □ Hybrid (multiple sources)

    3b. Do you need a public internet-facing entry point?
        □ Yes - public endpoints required
        □ No - internal/private access only
        □ Future - plan for it but not now

    3c. If public access needed, which Tier 1 (external entry) service?
        □ Azure Front Door (global CDN + WAF)
        □ Azure Application Gateway (regional L7 + WAF)
        □ None / N/A (skip if 3b was "No")

    3d. Which Tier 2 (AKS ingress) controller do you need?
        □ Application Gateway for Containers (AGFC)
        □ NGINX Ingress Controller
        □ Istio / Service Mesh
        □ Azure Application Gateway (AGIC)
        □ Kubernetes Service LoadBalancer
        □ None

4️⃣  How many pods do you need per node?
    □ ~110 pods (Standard CNI)  □ ~250+ pods (Overlay)

5️⃣  Do you want advanced network security (Cilium/eBPF)?
    □ No  □ Yes

6️⃣  Who controls the network infrastructure?
    □ App teams (Scenario 1)  □ Platform team (Scenario 2)
    □ Hybrid (Scenario 3)  □ Security-first (Scenario 4)

7️⃣  What environment is this?
    □ Development  □ Staging  □ Production

8️⃣  Are there compliance requirements?
    □ None  □ PCI-DSS  □ HIPAA  □ SOC 2  □ Other: ________

9️⃣  Will the hub and spoke be deployed to different Azure subscriptions?
    □ Same subscription (default)
    □ Different subscriptions (hub in connectivity, spoke in application)
    □ Different tenants (requires special cross-tenant configuration)
    
    If "Different subscriptions" selected:
    • Hub Subscription ID: ________________________________
    • Spoke Subscription ID: ________________________________
    • Confirm Network Contributor role on hub subscription: □ Yes
      (Required for cross-subscription VNet peering)
```

---

## 📋 Next Steps

1. **Collect answers** to the 9 questions above
2. **Pass to Agent Skills** workflow (Option A)
3. Agent Skills will:
   - Extract configuration requirements
   - Map to tfvars base file
   - Validate for contradictions
   - Generate Hub infrastructure code
   - Generate Spoke AKS code

---

## 🔄 Workflow

```
Customer Answers Questionnaire (5 min)
         ↓
Passes to Agent Skills (Option A)
         ↓
Agent Skills Extracts Configuration (automated)
         ↓
Agent Skills Validates for Contradictions (automated)
         ↓
Hub + Spoke Code Generated (automated)
```

---

## 📚 Reference Documents

- **ADR Input?** → [adr-to-hub-extraction-guide.md](./adr-to-hub-extraction-guide.md)
- **Need Help Answering Questions?** → [aks-configuration-decisions.md](./aks-configuration-decisions.md) (reference)
- **Governance Models?** → [deployment-scenarios.md](./deployment-scenarios.md) (reference)

---

**Ready?** Have the customer answer the 9 questions and pass the answers to the Agent Skills workflow (Option A).
