# 2.1 DATABASE MIGRATION STRATEGY

## 2.1.1 Scenario & Constraints

We are dealing with three production PostgreSQL databases:

* **OTC** – core trading / transactional system
* **GPS** – reporting / analytics or support system
* **ARP** – legacy, ~**200 GB**, unknown schema, hard-coded credentials in ~**15 applications**

Key constraints (from the assessment):

* **ARP credentials are unknown** or poorly managed.
* ARP has **tight availability** requirements – max **5 minutes downtime** is acceptable.
* Multiple upstream applications have **hardcoded passwords and connection strings**, some possibly outside our direct control.
* We need a migration strategy that is:

  * **Auditable**
  * **Reversible (rollbackable)**
  * **Compatible with a legacy system we cannot freely change initially**

The strategy must cover both:

1. **Data migration** (ARP → new ARP)
2. **Access & credential modernization** (hardcoded passwords → centralised secrets)

---

## 2.1.2 Selected Migration Strategy: Blue-Green with Optional CDC (Hybrid)

Instead of a single “big bang”, the proposed approach is:

> **Run a new ARP database in parallel (Green environment), keep the legacy ARP (Blue) as the source of truth, and perform cutover by switching application traffic once the new environment is validated.**

Optionally, when technically and politically feasible, we can add **CDC (Change Data Capture)** from the legacy ARP to the new ARP to minimise cutover delta.

### Why this is the primary choice

* **Minimises downtime** – we can keep ARP-legacy online while we:

  * Extract schema and data
  * Reconcile differences
  * Test and validate new ARP
* **Supports rollback** – if issues are detected post-cutover, we can route applications back to ARP-legacy within minutes.
* **Compatible with unknown schema** – we can iteratively discover ARP schema using exports/dumps without immediately changing the production system.
* **Supports staged app migration** – the 15 applications can be repointed in waves (or via routing/connection abstraction), not all at once.

---

## 2.1.3 Strategy Comparison (When to Use Each)

### 1. **Blue-Green Deployment (Chosen Default)**

**Use Blue-Green when:**

* You have **strict downtime limits** (≤ 5–10 minutes).
* You can afford **double infrastructure cost** temporarily.
* Your system allows **two live environments** (old and new) and a clear routing layer (DNS / load balancer / connection broker).
* You want a **clean rollback mechanism** (revert routing).

**Avoid Blue-Green when:**

* Storage/compute cost is ultra-constrained and duplicate infra is not acceptable.
* Apps cannot be easily pointed to a different endpoint (e.g., legacy binaries with hardcoded hostnames and no ability to patch).

---

### 2. **Big Bang Migration (Single Shot)**

**Use Big Bang only if:**

* You can secure a **maintenance window of several hours**.
* Schema is **well understood**, with low complexity.
* The blast radius is limited (few consumers, easy communication).
* The business explicitly accepts higher risk in exchange for simplicity.

**Not appropriate here because:**

* ARP is **200 GB** and **poorly understood**.
* 15 applications depend on it with unknown coupling.
* Downtime SLA is ~5 minutes, which big bang usually cannot guarantee safely.

---

### 3. **CDC-First / Zero-Downtime Migration**

**Use CDC-centric migration when:**

* You have strong operational capability (DBA team comfortable with logical replication, WAL streaming, Debezium, or DMS).
* You need **true zero downtime**, or near-zero RPO/RTO.
* Both source and target are under your control and allow replication setup.

**Why it’s “optional” here:**

* ARP credentials and configuration are not fully known initially.
* We might not immediately be able to enable logical replication or access WAL logs.
* Adding CDC on top of a legacy, unknown system may delay initial progress.

**Pragmatic approach:**
Start with **Blue-Green**, add **CDC later** if we confirm that:

* We have stable access to ARP.
* The platform can support logical replication.
* The migration needs to minimise delta at cutover (e.g., high write rate).

---

## 2.1.4 Phased Migration Plan (Blue-Green Hybrid)

### Phase 0 – Discovery & Access

* Identify ARP owner teams and infra contacts.
* Confirm:

  * Current hosting (on-prem / RDS / other)
  * Backup tooling (RMAN, pg_dump, snapshots)
  * Constraints (regulatory, data residency).
* Decide which of the three access options (below) is possible:

  1. **Direct DBA credentials** (ideal)
  2. **Indirect export** by platform/DBA team
  3. **Application-side extraction** (last resort)

### Phase 1 – Build Target Environment (Green ARP)

* Provision new ARP database in **Prod-Data Account** (AWS RDS or self-managed Postgres).
* Implement:

  * Proper **VPC isolation**, **security groups**, **KMS encryption**, and **IAM policies**.
  * **Secrets Manager** entries for ARP credentials.
  * **CloudWatch / Datadog dashboards** for performance, replication, and errors.
* Document the target schema baseline (even if initially identical to legacy).

### Phase 2 – Initial Data Load

Depending on what’s feasible:

* If we have ARP credentials → **pg_dump/pg_restore** or DMS full load.
* If we don’t have direct access → request **one-time schema + data export** from the platform team.
* Validate:

  * Row counts per critical table
  * Key constraints, foreign keys, indexes
  * Spot-check critical business flows (e.g., customer lookup, transaction history).

### Phase 3 – Optional CDC / Incremental Sync

If possible:

* Configure **logical replication / DMS ongoing replication** from ARP-legacy to ARP-green.
* Monitor replication lag and errors.
* Use this phase to:

  * Verify that new ARP remains consistent with legacy.
  * Rehearse cutover and rollback.

If CDC is **not** feasible, plan a **second (short) delta load** near cutover, with a short freeze window on writes.

### Phase 4 – Application Cutover

* Introduce **indirection for connection details** (e.g., DSNs via Secrets Manager, configuration layer, or service discovery).
* For each of the 15 applications:

  * Switch from hardcoded ARP credentials → secrets abstraction.
  * Update endpoint from ARP-legacy → ARP-green.
  * Roll out change in small batches if possible.
* Use feature flags or config toggles so you can switch back to ARP-legacy if required during early phases.

### Phase 5 – Post-Cutover Monitoring & Stabilization

* Intensively monitor:

  * Latency, error rates, slow queries, replication status (if CDC still running).
* Confirm data alignment between ARP-legacy and ARP-green for a defined period.
* Only when confident:

  * Decommission ongoing replication (if used).
  * Plan retirement of ARP-legacy or demotion to “emergency fallback only”.

---

## 2.1.5 Password & Secrets Management Strategy (ARP)

### Problem

* ARP password is **unknown or inconsistently managed**.
* 15 applications use **hardcoded credentials and static connection strings**.
* Any migration that doesn’t address secrets will leave a long-term security and operational risk.

### Strategy

We use a **gradual centralisation** approach:

#### Step 1 – Credential Discovery

Applicable in **any scenario**:

* Ask infra/DBA teams for official credentials and rotation policies.
* Scan:

  * Application configs
  * CI/CD variables
  * Old deployment scripts
  * Container definitions
* Log all findings in a **controlled, access-logged location** (e.g., password vault, not Confluence).

#### Step 2 – Introduce Central Secret Store

If the platform is primarily AWS:

* Use **AWS Secrets Manager** (or Parameter Store for lower-risk configs).

If the organisation is **multi-cloud or already deeply uses Vault**:

* Use **HashiCorp Vault** with dedicated AppRoles / namespaces for ARP.

Applications should be modified to **never embed ARP credentials directly**, but instead:

* Retrieve secrets at runtime via:

  * environment variables
  * sidecar
  * or direct API calls (depending on platform patterns)

#### Step 3 – Staged Rotation

* Initially, ARP-legacy keeps its **old password**, but the secret is stored both:

  * in the legacy format (for backward compatibility)
  * and as a proper secret in the vault.
* New ARP-green uses **a new strong password**, defined only in the secrets store.
* Over time:

  * Applications are migrated to use secrets from the vault.
  * Once all are confirmed migrated, **deprecate and revoke** the old hardcoded credentials.

---

## 2.1.6 Rollback Strategy (≤ 5 Minutes)

Rollback must be:

* **Deterministic** – clear steps, not ad-hoc.
* **Predictable** – tested in advance.
* **Fast** – under 5 minutes, target ≤ 3 minutes.

High-level rollback flow:

1. **Stop or divert new writes** to ARP-green.
2. Re-point traffic from ARP-green back to ARP-legacy:

   * Update service discovery / connection broker
   * Or flip feature flag / config setting used by the 15 applications
3. Confirm that:

   * Applications are able to write/read from ARP-legacy again
   * Error rates drop to baseline
4. Trigger **incident management**:

   * Declare an incident
   * Document timeline, symptoms, and suspected root cause
5. Preserve ARP-green state for investigation, but remove it from live traffic paths.

**When to design additional “data backfill” rollback:**
If ARP-green was live and accepted writes that ARP-legacy did not get, we will need a **backfill or reconciliation** plan (usually manual or scripted, with strong audit/error handling). This is scenario-dependent and must be designed per data model.

---

## 2.1.7 Handling “ARP Password Unknown”

We don’t assume success with a single approach. In practice, you often need to try multiple options, with clear risk handling.

### Option A – Cooperative Access via Platform / DB Team (Preferred)

**Use when:**

* There is an existing DBA/platform team with control over ARP.
* Compliance and governance favour clear responsibility and least privilege.

**Approach:**

* Request:

  * Direct ARP credentials
    **or**
  * Scheduled exports (schema and data)
  * Possibly secured DMS tasks configured by the DB team
* Agree on:

  * Time windows
  * Audit requirements
  * Encryption standards

### Option B – Read-Only Exports Only

**Use when:**

* You cannot be granted DB login rights.
* Platform team is willing to run **pg_dump** or equivalent on your behalf.

**Approach:**

* Ask for:

  * Full schema dump
  * Data dumps of critical tables
  * Incremental exports or WAL segments, if replication needed
* This is a **good compromise** when direct access is not allowed for security or separation-of-duties reasons.

### Option C – Application-Side Credential Extraction (Last Resort)

**Use only when:**

* There is **no cooperation** from platform/DB team.
* ARP is business-critical and a migration is mandatory.
* You have legal and compliance approvals.

**Approach:**

* Extract passwords from:

  * Cooked container images
  * Old deploy scripts or CI/CD variables
  * On-disk config files
* Every step must be:

  * Approved (e.g., CISO / Security)
  * Logged
  * Covered by a **data-handling SOP** (no personal copies, etc.)

In an interview context, it’s important to explicitly say:

> *“I would only use this path with formal approval and under strict audit requirements, as it touches sensitive and potentially regulated data.”*

---

## 2.1.8 Timeline (Indicative, Not Assumed)

Rather than assuming an exact company timeline, we use indicative ranges:

| Phase                             | Typical Duration (Indicative) |
| --------------------------------- | ----------------------------- |
| Access / Discovery                | 2–5 business days             |
| Initial schema + data assessment  | 2–3 days                      |
| Build target ARP-green infra      | 2–4 days                      |
| Initial data load                 | 1–3 days                      |
| Optional CDC / sync setup         | 3–5 days                      |
| Application integration & testing | 5–10 days                     |
| Cutover rehearsal                 | 1–2 days                      |
| Final cutover                     | ≤ 5 minutes live switch       |

In a real engagement, this would be refined after initial discovery.

---

# 2.2 TOOL SELECTION MATRIX (WITH SCENARIOS)

The assessment asks to compare paired options and justify choices. Instead of declaring a single “universal” winner, we describe **when each is appropriate** and what we’d choose in **this ARP migration context**.

## 2.2.1 Secrets Management — AWS Secrets Manager vs HashiCorp Vault

| Aspect               | AWS Secrets Manager                    | HashiCorp Vault                                       |
| -------------------- | -------------------------------------- | ----------------------------------------------------- |
| Best suited for      | AWS-centric, managed services          | Multi-cloud / hybrid, complex orgs                    |
| Ops overhead         | Low (managed)                          | Medium–High (cluster to deploy & maintain)            |
| Integration          | Native IAM/KMS, Lambda, RDS, ECS, EKS  | Very broad, plugins, dynamic secrets, PKI, DB engines |
| Use case fit for ARP | **Very strong** if we stay AWS-centric | Strong if company already standardized on Vault       |

**Choice for this assessment scenario:**

* If the expected target is **AWS multi-account** and we are not told otherwise, we document **AWS Secrets Manager** as the **primary choice** because:

  * Native integration with **RDS**, **IAM**, **KMS**
  * Easier adoption by teams who are not security-specialists
  * Fits well into the **Prod-Data Account** and central security services

**When we would choose Vault instead:**

* If the organisation:

  * Already runs Vault at scale
  * Is **multi-cloud**, or
  * Requires advanced workflows (e.g., database dynamic credentials, complex PKI, ephemeral tokens)

In an interview, you can explicitly say:

> *“For this ARP migration on AWS, I’d choose Secrets Manager. If the company had existing Vault investment or strong multi-cloud, I’d design around Vault instead.”*

---

## 2.2.2 Container Platform — ECS Fargate vs EKS

| Aspect                  | ECS Fargate                          | EKS (Kubernetes)                              |
| ----------------------- | ------------------------------------ | --------------------------------------------- |
| Ops complexity          | Low                                  | Higher – cluster lifecycle, upgrades, add-ons |
| Control / flexibility   | Medium                               | Very high                                     |
| Best for                | Simple microservices, batch, tasks   | Complex platform engineering / multi-tenant   |
| Cost model              | Simple (pay per task)                | More knobs; can be efficient at scale         |
| ARP migration relevance | Host bastions/automation jobs easily | Overkill purely for ARP unless already in use |

**Choice in this assessment’s context:**

* If this work is mainly to support **database migration, bastion, and small automation services**, **ECS Fargate** is a clean choice.
* If the organisation already runs **Kubernetes** and most services are on **EKS**, then aligning ARP-related services to EKS can reduce fragmentation.

**Rule of thumb:**

* New, AWS-only fintech without strong K8s culture → **ECS Fargate**.
* Mature platform with dedicated SRE & K8s → **EKS**, but only if we leverage it for more than ARP.

---

## 2.2.3 CI/CD — GitHub Actions vs GitLab CI

| Aspect              | GitHub Actions                    | GitLab CI                                     |
| ------------------- | --------------------------------- | --------------------------------------------- |
| Repo hosting        | GitHub                            | GitLab                                        |
| Deepest integration | With GitHub PRs, checks, security | With GitLab issues, MR, self-hosted pipelines |
| Setup effort        | Very low                          | Low–Medium                                    |
| Best for            | GitHub-hosted repos               | Organisations standardised on GitLab          |

**In this assessment:**

* The submission repo is on GitHub and the assignment explicitly calls out `.github/workflows/main.yml` as an acceptable path → we choose **GitHub Actions**.

**When we’d choose GitLab CI instead:**

* If the company’s main SCM/ALM is **GitLab**, and:

  * They use **self-hosted runners**
  * They want unified repo + issue + pipeline experience

---

## 2.2.4 Monitoring — CloudWatch vs Datadog

| Aspect   | CloudWatch                     | Datadog                                              |
| -------- | ------------------------------ | ---------------------------------------------------- |
| Scope    | AWS-native                     | Multi-cloud, SaaS, infra, apps, logs, APM            |
| Cost     | Generally cheaper for pure AWS | Higher per host / per metric, but more observability |
| Best for | AWS-only stacks                | Heterogeneous environments / advanced observability  |

**For ARP migration:**

* If ARP and related services are all inside AWS accounts, **CloudWatch** is sufficient for:

  * RDS performance
  * Lambda/ECS metrics
  * Logs, alarms, dashboards

**When Datadog makes sense:**

* If the company already has Datadog agents deployed network-wide.
* If they want unified visibility across **on-prem**, **K8s**, **multiple clouds**, and SaaS.

---

## 2.2.5 Backup — AWS Backup vs Custom Scripts

| Aspect     | AWS Backup                           | Custom Scripts (pg_dump, snapshots, etc.)         |
| ---------- | ------------------------------------ | ------------------------------------------------- |
| Management | Policy-based, managed                | You own logic, scheduling, retention              |
| Use case   | Standard RDS/EBS backups, compliance | Special flows, validation, custom restore testing |
| Best for   | Baseline + compliance coverage       | Additional verification or non-standard flows     |

**Recommended pattern:**

* Use **AWS Backup** for:

  * RDS instances
  * EBS volumes
  * Meeting basic retention and legal requirements
* **Augment with custom scripts** (like those in this assessment) to:

  * Validate backup integrity (e.g., ephemeral QA restores)
  * Test disaster recovery runbooks
  * Generate additional metadata/reports

---

# 2.3 AWS ACCOUNT & OU STRUCTURE

(Your original layout is good; this is just more formal and explicit about rationale and ARP placement.)

```text
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

### Rationale

* **Production OU**
  Isolate production workloads from non-production for:

  * Accidental modification risk
  * Stronger SCPs (e.g., preventing creation of certain services)
  * Easier audit scoping

* **Prod-Apps vs Prod-Data**
  Split to:

  * Apply stricter controls on data (KMS keys, IAM policies, SCPs)
  * Limit who can access or modify databases vs application code/infrastructure
  * Simplify data-centric monitoring and compliance reporting

* **Prod-Security Account**
  Host:

  * Central logging (CloudTrail org trails, Security Hub, GuardDuty)
  * Security tooling
  * Aggregated alerts

* **Non-Production OU**
  Dev and Stage accounts:

  * Lower blast radius
  * Freedom for testing / POCs with fewer restrictions
  * Still enforce foundational security (baseline guardrails)

* **Infrastructure OU**

  * **Shared-Services Account**: host AD/SSO integrations, CI/CD tooling, artifact registries.
  * **Networking Account**: Transit Gateway, central VPC peering, shared VPN/direct connect, CloudWAN if used.

* **Sandbox OU**

  * Isolated “playground” to allow experimentation without risk to regulated workloads.

### Where ARP Lives

* **ARP-legacy**:

  * Resides in **Prod-Data Account**, inside:

    * A dedicated **VPC**
    * Private subnets
    * **Tightly scoped security groups** (very small allowlist, ideally only from specific application tiers or bastions)

* **ARP-green (new)**:

  * Also in **Prod-Data Account**, but ideally in a:

    * Separate subnet group
    * Separate security group
  * This separation helps:

    * Run Blue-Green
    * Apply different parameter groups, backup policies, and monitoring.

* **Ephemeral QA environments**:

  * Live in **Stage Account**, in an isolated VPC.
  * Resources auto-created and auto-destroyed via CI/CD:

    * Test RDS / Postgres
    * Ephemeral ECS tasks / containers
  * This aligns with principle:

    > “Production-like testing in non-production accounts with similar security guardrails, but no live production data.”

---

# 2.4 RISK ASSESSMENT MATRIX (ENHANCED)

At least 7 risks were required; below is an expanded matrix with more depth per risk.

| #  | Risk                                      | Probability | Impact | Scenario / Trigger                                           | Mitigation                                                                                 | Owner           |
| -- | ----------------------------------------- | ----------- | ------ | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------ | --------------- |
| 1  | Data loss during ARP migration            | Medium      | High   | Migration script bug, CDC misconfig, or cutover error        | Pre/post row-count checks, checksums, backups before each step, Blue-Green rollback path.  | DBA Lead        |
| 2  | ARP password never obtained               | High        | High   | Platform team unresponsive, no authorised credentials shared | Escalate governance, explore read-only dumps, last-resort extraction with approvals.       | Migration PM    |
| 3  | Schema mismatch between legacy and target | Medium      | High   | Hidden constraints, data types, or triggers differ           | Schema diff tooling, test restores in QA, dry run migrations with representative data.     | Data Architect  |
| 4  | Hardcoded credentials in 15 apps          | High        | High   | Apps fail at cutover or cannot be rotated easily             | Centralised secrets, staged app updates, compatibility mode until all apps migrated.       | Dev Lead        |
| 5  | Performance regression on ARP-green       | Medium      | High   | Larger load, missing indexes, different instance sizing      | Load testing, A/B comparison, query tuning, instance right-sizing before full cutover.     | SRE / DBA       |
| 6  | Backup corruption or unusable backups     | Medium      | High   | Misconfigured backup jobs or bad storage                     | Automated backup verification via ephemeral QA restores, checksum checks, DR drills.       | SRE             |
| 7  | Cost spike from ephemeral environments    | Medium      | Medium | QA / test environments left running, high storage retention  | TTL-based auto-teardown, resource tagging + cost dashboards, scheduled cleanup jobs.       | DevOps          |
| 8  | Network misconfiguration                  | Low         | High   | Wrong SGs, routing issues, broken connectivity at cutover    | IaC templates + review, pre-cutover connectivity tests, change windows with rollback.      | Cloud Architect |
| 9  | Compliance issues from sensitive data use | Low–Medium  | High   | Using prod-like data in QA without masking                   | PII masking in QA, anonymisation, strict account boundaries, approvals for any exceptions. | Security Lead   |
| 10 | Operational overload on limited team      | Medium      | Medium | Too many parallel changes: ARP, apps, infra, tools           | Clear phasing, freeze windows, prioritisation, dedicated migration SWAT team.              | Eng Manager     |

---

