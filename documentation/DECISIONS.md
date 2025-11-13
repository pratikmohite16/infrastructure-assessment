# **2.1 DATABASE MIGRATION STRATEGY**

## **Scenario Summary**

* 3 production databases: **OTC, GPS, ARP**
* ARP is **legacy**, **200GB**, **unknown schema**, **hardcoded passwords in 15 applications**, tolerates **max 5 minutes downtime**
* ARP credentials are **unknown**, cannot directly access

---

# ** Migration Approach Decision**

After evaluating all migration options, the chosen strategy is:

##  **Blue-Green Deployment (Recommended)**

### ✔ Why Blue-Green?

* Allows the new ARP database to run **in parallel** with the legacy one
* Zero-to-minimal downtime during final cutover
* Safe for a 200GB database
* Applications can be gradually pointed to the new password + new endpoint
* Allows rollback in seconds by switching traffic back
* Supports testing, validation, and user acceptance before migration

---

# ** Alternative Approaches Considered**

### **1. Big Bang Migration**

 **Rejected**
**Why:**

* High downtime risk
* No way to validate unknown ARP schema before cutover
* Hardcoded credentials across 15 apps make it unsafe
* Cannot meet 5 min downtime requirement

---

### **2. Gradual Migration with CDC (Change Data Capture)**

 **Possible but NOT chosen**
**Pros:**

* Zero downtime
* Ideal for large DBs
* Allows schema evolution

**Cons:**

* Requires logical replication setup on ARP
* Hard because original ARP credentials are unknown
* Requires access to WAL logs
* More complex than needed for this assessment

---

### **3. Shadow Writes / Dual-Writes**

 **Considered but impractical**
**Cons:**

* Requires modifying 15 apps simultaneously
* Risky for legacy environment

---

# ** Final Decision: Blue-Green + Selective CDC (Hybrid)**

Best balance between:

* Low downtime
* Safety
* Predictability
* Ability to operate without ARP credentials initially

---

# **2.1.1 PASSWORD MANAGEMENT STRATEGY**

### ❗ Problem:

ARP credentials are unknown, and 15 applications use **hardcoded passwords**.

### ✔ Solution: **Phased Password Rotation & Secrets Centralization**

### **Phase 1 — Discovery**

* Contact original ARP team for credentials
* Run credential rotation workshop
* Inventory all 15 applications

### **Phase 2 — Introduce Secrets Manager**

* Move all ARP credentials to **AWS Secrets Manager**
* Applications read passwords via environment variables

### **Phase 3 — Gradual Enforcement**

* Old hardcoded passwords remain valid temporarily
* Applications are updated one-by-one
* Each application switches to Secrets Manager
* Rotation every 30 days

### **Phase 4 — Hard Decommission**

* Remove legacy hardcoded password
* Enforce password rotation
* Enable audit trails

---

# **2.1.2 ROLLBACK STRATEGY**

Rollback must meet the 5-minute downtime requirement.

### ✔ Rollback Steps:

1. Immediately route traffic back to ARP-legacy endpoint
2. Pause replication to new ARP DB
3. Restore traffic in 15 applications to old credentials
4. Create high-severity incident ticket
5. Capture logs and metrics for RCA

### Rollback SLA: **< 3 minutes**

(Cloud workloads can switch endpoints instantly.)

---

# **2.1.3 ARP PASSWORD UNKNOWN — WHAT TO DO?**

### ### ❗ Critical blocker scenario:

You cannot access the database at all.

---

## ✔ Approach 1: **Negotiate With Original Team (Preferred)**

**Pros:**

* Direct access
* Fastest
* No reverse-engineering
* Full compliance

**Cons:**

* Depends on cooperation
* May delay migration

---

## ✔ Approach 2: **Read-Only Dump via Platform Team**

Ask infra team to export:

* Schema only
* Data-only dump
* WAL logs for replication

**Pros:**

* No full access needed
* Enables CDC
* Allows schema inspection

**Cons:**

* Not guaranteed
* Legacy team may not respond

---

## ✔ Approach 3: **Application Side Credential Extraction** (Last Resort)

Extract credentials from:

* 15 application config files
* Old deployment scripts
* Environment variables
* Containers

**Pros:**

* Almost guaranteed access
* No dependency on original team

**Cons:**

* May violate compliance
* Requires strict audit logging
* Very sensitive

---

# **2.1.4 TIMELINE ESTIMATE**

| Phase                          | Duration  |
| ------------------------------ | --------- |
| Discovery & Access Negotiation | 2–3 days  |
| Schema Extraction + Validation | 2 days    |
| CDC/Replication Setup          | 3 days    |
| Blue-Green Deployment Prep     | 1–2 days  |
| Application password updates   | 3–5 days  |
| Final Cutover                  | 5 minutes |

---

# **2.2 TOOL SELECTION MATRIX**

(from assessment) 

Below is the exact comparison table required.

| Requirement        | Option A            | Option B        | Your Choice             | Why?                                                               | Cost Impact |
| ------------------ | ------------------- | --------------- | ----------------------- | ------------------------------------------------------------------ | ----------- |
| Secrets Management | AWS Secrets Manager | HashiCorp Vault | **AWS Secrets Manager** | Native AWS integration, easier rotation, simpler for multi-account | Medium      |
| Container Platform | ECS Fargate         | EKS             | **ECS Fargate**         | Lower operational overhead, cheaper, easier to scale               | Low         |
| CI/CD              | GitHub Actions      | GitLab CI       | **GitHub Actions**      | Free runner, fast setup, secret scanning, fits repo submission     | Very Low    |
| Monitoring         | CloudWatch          | Datadog         | **CloudWatch**          | Native, cheaper, enough metrics for DB                             | Low         |
| Backup Solution    | AWS Backup          | Custom Scripts  | **AWS Backup (Hybrid)** | Automatic retention + custom verification scripts                  | Medium      |

---

# **2.3 ACCOUNT STRUCTURE DESIGN**

Assessment requires this exact structure:


```
Root Organization
├── Production OU
│   ├── Prod-Apps Account
│   ├── Prod-Data Account
│   └── Prod-Security Account
├── Non-Production OU
│   ├── Dev Account
│   └── Stage Account
├── Infrastructure OU
│   ├── Shared-Services Account
│   └── Networking Account
└── Sandbox OU
    └── Playground Account
```

---

# ** Justification**

### **Why separate prod and non-prod?**

* Prevent production data leaks
* ACIs, IAM roles, and VPCs stay isolated
* Auditors require strict separation

### **Why separate Prod-Apps vs Prod-Data?**

* Data needs tighter IAM
* Easier encryption & KMS key policies
* Clear ownership boundaries

### **Why Infra OU?**

* Central place for:

  * Logging
  * SSO
  * Landing Zone
  * Transit Gateway
  * Shared networking

### **Where does ARP legacy go?**

* Inside **Prod-Data Account (isolated subnet)**
* With restricted SG allowing minimal access

### **Where do ephemeral QA environments live?**

* In **Stage Account**
* Auto-created, auto-deleted
* No persistent resources

### **How implement Google SSO?**

* Use AWS IAM Identity Center
* Identity source = Google Workspace
* Map groups → AWS roles
* Mandatory MFA

---

# **2.4 RISK ASSESSMENT MATRIX**

Assessment requires at least 7 risks:


| Risk                        | Prob.  | Impact | Mitigation                            | Owner           | Trigger               |
| --------------------------- | ------ | ------ | ------------------------------------- | --------------- | --------------------- |
| Data loss during migration  | Medium | High   | Pre/post validation, PITR, Blue-Green | DBA Lead        | Backup failure        |
| ARP password never received | High   | High   | Use alternative extraction methods    | Migration PM    | No response in 48h    |
| Invalid schema differences  | Medium | High   | Schema diff automation, QA clone      | Data Architect  | Validation errors     |
| Hardcoded passwords in apps | High   | High   | Secrets Manager migration plan        | Dev Lead        | Deployment fails      |
| Disk usage spikes           | High   | Medium | Monitoring + autoscaling              | SRE Lead        | >80% usage            |
| Backup corruption           | Medium | High   | Daily validation + QA restore         | SRE             | Checksum failures     |
| Cost explosion from QA envs | Medium | Medium | TTL deletion + tagging                | DevOps          | Monthly billing spike |
| Network misconfiguration    | Low    | High   | IaC validation + static scanning      | Cloud Architect | Failed connectivity   |

---


Your choice.
