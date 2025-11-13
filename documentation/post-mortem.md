### *Post-Incident Report – Production Backup Failure & ARP Legacy Authentication Issue*

**Incident Date:** 14 Feb 2025
**Incident Start:** 02:00 AM
**Incident End:** 03:42 AM
**Prepared By:** DevSecOps Engineer
**Severity:** **SEV-1** (Production Data Protection Risk)

This post-mortem covers the **failed nightly production backup**, caused by **disk pressure** and **legacy ARP authentication failure**, requiring an emergency streamed backup and credential recovery.

---

# **1. Summary**

At 02:00 AM, the scheduled production backup job failed due to:

1. **Disk usage exceeding 95%**, preventing normal pg_dump operations.
2. **ARP legacy database authentication failure**, caused by unknown/invalid password.

The system triggered multiple errors:

```
[ERROR] Disk usage at 96% – unsafe for backup
[ERROR] Unable to authenticate to ARP database
[FAIL] Nightly production backup aborted
```

The on-call engineer executed the **emergency backup script** (`emergency-backup.sh`) and **ARP recovery script** (`secrets-management.sh recover-arp`), restoring service integrity.

---

# **2. Impact**

### **Systems Affected**

* Production OTC / GPS / ARP databases (backup workflows)
* Bastion logs
* CI/CD nightly pipeline
* Backup validation process

### **Customer Impact**

* **No customer-facing downtime**
* No data corruption
* Backup window missed by **92 minutes**
* Increased operational risk during the outage window

### **Data Risk**

* Temporary risk of **incomplete backups**
* ARP authentication failures prevented ARP dumps
* High disk usage threatened backup success & container stability

---

# **3. Timeline (Detailed)**

| Time         | Event                                                           |
| ------------ | --------------------------------------------------------------- |
| **02:00 AM** | Nightly backup job started                                      |
| **02:01 AM** | Backup script detects **96% disk usage** → aborts normal backup |
| **02:02 AM** | ARP backup fails due to **authentication error**                |
| **02:04 AM** | On-call engineer receives alert                                 |
| **02:08 AM** | Deployment freeze applied                                       |
| **02:10 AM** | Engineer runs `emergency-backup.sh` for OTC & GPS               |
| **02:14 AM** | Emergency streamed backup completed for OTC                     |
| **02:19 AM** | Emergency streamed backup completed for GPS                     |
| **02:21 AM** | ARP still failing due to unknown credentials                    |
| **02:23 AM** | Engineer executes `secrets-management.sh recover-arp`           |
| **02:27 AM** | ARP password recovered & rotated                                |
| **02:29 AM** | ARP emergency backup completed                                  |
| **02:32 AM** | Disk cleanup done using `docker system prune -a`                |
| **02:40 AM** | Full backup/restore validation performed                        |
| **02:42 AM** | System stabilized, incident resolved                            |

---

# **4. Root Cause Analysis (RCA)**

RCA is performed using the **5 Whys** approach.

### **4.1 Why did the production backup fail?**

Because the disk usage reached **96%**, preventing normal pg_dump from writing output.

### **4.2 Why was disk usage above threshold?**

Old backup artifacts had not been cleaned due to a retention misconfiguration.

### **4.3 Why did ARP backup also fail?**

ARP authentication was failing due to an unknown/incorrect stored password.

### **4.4 Why was ARP password unknown?**

The legacy ARP system uses **restricted legacy network constraints** and does not expose secrets via standard methods.

### **4.5 Why was ARP not rotated earlier?**

ARP had not been included in the automated secrets rotation cycle because of unknown initial state.

---

# **Primary Root Cause:**

**Disk pressure + ARP legacy authentication mismatch.**

# **Secondary Root Cause:**

**Lack of automated retention policy for old backups.**

# **Contributing Factors:**

* The ARP legacy network has special constraints, making credential recovery harder.
* The backup job does not auto-prune old backup directories.
* No continuous disk capacity monitoring alerts existed before the incident.

---

# **5. Corrective Actions (Immediate)**

✔ Execute emergency streamed backup
✔ Recover ARP credentials
✔ Clean unused Docker layers & old backups
✔ Validate emergency restore
✔ Re-run nightly backup manually
✔ Document the incident
✔ Freeze deployments until validation done

---

# **6. Preventive Actions (Long-Term Fixes)**

### **6.1 Backup & Retention Improvements**

* Add automated retention policy: keep last 7 daily backups only
* Add weekly full backup archival
* Introduce backup size & checksum monitoring

### **6.2 Disk Capacity Monitoring**

* Add threshold alerts at **70%**, **85%**, and **95%**
* Add `docker system prune --filter "until=24h"` as automated cleanup

### **6.3 ARP Legacy Hardening**

* Add ARP password recovery check to secrets rotation
* Add ARP schema validation job
* Implement fallback modes for ARP-only failures

### **6.4 CI/CD Guardrails**

* Block database migrations when backup fails
* Block deployments during backup window
* Add pipeline unit test for secret existence

### **6.5 Operational Improvements**

* Add on-call runbook specific to ARP recovery
* Add “dry-run backup” job every 6 hours
* Improve incident alert formatting

---

# **7. Lessons Learned**

### **What went well**

* Emergency backup succeeded
* ARP recovery script worked as designed
* Rollback and validation procedures functioned correctly
* No data loss
* Incident resolved quickly

### **What could be improved**

* Disk usage should never reach critical thresholds
* ARP credential drift must be continuously checked
* Backup retention was not being enforced
* Alerts did not fire early enough

### **What we will do differently**

* Enforce strict retention & disk monitoring
* Add ARP-specific validation workflows
* Improve CI/CD checks around database operations
* Strengthen incident alerting channels

---

# **8. Final Status**

✔ Backup restored
✔ ARP password recovered
✔ System stable
✔ Disk usage dropped to 56%
✔ Monitoring enabled
✔ RCA completed
✔ Preventive tasks assigned

**Incident closed at 03:42 AM.**

