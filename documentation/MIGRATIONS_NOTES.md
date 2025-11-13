There 3 strategies are:

# **✔ Strategy 1 — AWS DMS (Full Load + CDC) + RDS Blue/Green Cutover**

# **✔ Strategy 2 — RDS Snapshot + Restore + Final Delta Sync**

# **✔ Strategy 3 — EBS Snapshot → EC2 Recovery → RDS Migration (For Unknown-PW ARP)**

# 📄 MIGRATION STRATEGIES — AWS Database Migration (Top 3 Approaches)

## For OTC, GPS & ARP Databases

# 🟦 **STRATEGY 1 — AWS DMS (Full Load + CDC) + RDS Blue/Green Deployment**

⚡ **Best Overall Strategy**
⚡ **Lowest downtime**
⚡ **Most reliable for ARP**
⚡ **Uses AWS-native migration patterns**

---

## **1.1 Why This Strategy?**

This is the **industry-standard** AWS migration approach for:

* Large databases
* Unknown schema
* Legacy systems
* Low-downtime cutover
* Multi-application dependency databases

Your ARP DB (200GB, unknown password, schema not documented, critical for 15 apps) fits PERFECTLY into DMS + Blue/Green.

---

## **1.2 Migration Steps (End-to-End)**

### **Step 1 — Analyse Source Database**

* Identify ARP server location (EC2, VM, on-prem)
* Check if PostgreSQL WAL/Logical replication is enabled
* Request read access / replication role if password is available
* If not available, request infra team to expose ARP as Read Replica or allow access for DMS

---

### **Step 2 — Prepare AWS RDS Target**

Create an RDS PostgreSQL instance:

* Engine: PostgreSQL 14/15
* Instance: db.m5.large (temporary, upgrade later)
* Storage: gp3
* Backups: PITR enabled
* Encryption: KMS

Store DB credentials in **Secrets Manager**.

---

### **Step 3 — Configure AWS DMS**

Create:

✔ **DMS Source Endpoint** (ARP DB)
✔ **DMS Target Endpoint** (New RDS)
✔ **DMS Replication Instance**
✔ **DMS Task** with:

* **Full Load** (initial migration)
* **CDC (Change Data Capture)** to sync ongoing changes

DMS will copy:

* All tables
* Indexes
* Data
* LOBs
* Sequences

And keep syncing new changes.

---

### **Step 4 — Build RDS Blue/Green Deployment**

AWS RDS has native Blue/Green deployments:

* Green = new RDS
* Blue = legacy
* Data sync maintained via DMS
* Green validated in Stage account
* Read-only analytics possible

---

### **Step 5 — Test Migration in QA (Stage Account)**

1. Share snapshot across accounts
2. Restore snapshot into Stage RDS
3. Validate schema + row counts
4. Run application test suite
5. Run PII masking (for QA data)
6. Approve for production

---

### **Step 6 — Final Cutover**

When CDC lag = 0:

1. Freeze writes for 2–5 minutes
2. Promote Green DB (one-click RDS Blue/Green switch)
3. Update Secrets Manager value
4. All 15 apps fetch new password automatically
5. Enable writes on new DB
6. Monitor CloudWatch metrics

Downtime achieved: **2–4 minutes**

---

### **Step 7 — Post-Migration**

* Disable logical replication
* Delete old ARP DB only after 7–14 days
* Continue daily backups
* Enable RDS Enhanced Monitoring

---

## **1.3 Rollback**

Rollback is instant:

✔ Switch back to Blue DB
✔ Disable RDS Green traffic
✔ Re-enable ARP legacy DB writes
✔ Re-enable DMS sync if needed

---

## **1.4 When To Use This Strategy**

Best for:

* ARP (200GB)
* Unknown schema
* Hardcoded passwords
* High-availability apps
* Must meet 5-minute downtime rule

---

# 🟩 **STRATEGY 2 — RDS Snapshot Restore + Final Delta Sync (Simple & Reliable)**

⚡ **Best for OTC & GPS**
⚡ **Simple to execute**
⚡ **Good for planned downtime**

---

## **2.1 Why This Strategy?**

OTC & GPS are normal PostgreSQL databases.

They:

* Have fewer unknowns
* Are smaller
* Easier to backup and restore
* Less critical than ARP

Snapshot → Restore → Validate → Cutover is perfect.

---

## **2.2 Migration Steps (End-to-End)**

### **Step 1 — Export Source Databases**

Take a full backup using:

```
pg_dump -Fc -Z9 -f otc.dump otc
pg_dump -Fc -Z9 -f gps.dump gps
```

Upload to S3 bucket:

```
aws s3 cp otc.dump s3://migration-backup/
aws s3 cp gps.dump s3://migration-backup/
```

---

### **Step 2 — Import into RDS**

```bash
aws rds restore-db-instance-from-s3 \
  --db-instance-identifier otc-rds \
  --source-engine postgresql \
  --s3-bucket-name migration-backup \
  --s3-prefix otc.dump \
  --engine-version 14.7
```

Same for GPS.

---

### **Step 3 — Validate in Stage Account**

1. Copy RDS snapshot to Stage
2. Restore snapshot to Stage
3. Compare schema
4. Compare row counts
5. Run test suite
6. Approve for production

---

### **Step 4 — Final Sync Before Cutover**

Take a final delta dump:

```
pg_dump -Fc --data-only --exclude-table=logs ... 
```

Restore delta into RDS.

---

### **Step 5 — Update Secrets & Application**

* Store new passwords in Secrets Manager
* Update Lambda / ECS / EC2 apps via environment variable reload

---

### **Step 6 — Production Cutover**

* Pause writes for 10–15 minutes
* Apply delta
* Flip application endpoints
* Monitor

---

## **2.3 Rollback**

* Restore snapshot
* Re-point apps to old DB
* Perform PITR if required

---

## **2.4 When To Use This Strategy**

Best for:

✔ OTC
✔ GPS
✔ Environments where 10–20 min downtime is acceptable

---

# 🟥 **STRATEGY 3 — EBS Snapshot Recovery → EC2 PostgreSQL → RDS Migration**

⚡ **Best when ARP password is truly unknown**
⚡ **Works even when DB is corrupted**
⚡ **Used when no DB access exists**

---

## **3.1 Why This Strategy?**

The assessment says:

* ARP password is not known
* Schema not documented
* 15 applications depend on it
* Legacy, 200GB
* Could be on VM / EC2 / unknown platform

**If you cannot connect to ARP at all, DMS cannot be used.**

The ONLY way to extract data is:

1. **Get an EBS snapshot** of the server
2. **Mount it on EC2**
3. **Recover the PostgreSQL data folder manually**

This approach is realistic and used often in fintech migrations.

---

## **3.2 Migration Steps (End-to-End)**

### **Step 1 — Request Source Snapshot**

Ask infra team for either:

* EBS snapshot
* VM snapshot
* Full disk backup

Mount snapshot to EC2:

```
aws ec2 attach-volume --volume-id vol-xxxx --instance-id i-xxxx --device /dev/xvdf
```

---

### **Step 2 — Recover PostgreSQL data directory**

Mount filesystem:

```
sudo mkdir /mnt/arp
sudo mount /dev/xvdf1 /mnt/arp
```

Locate PostgreSQL data:

```
/mnt/arp/var/lib/postgresql/12/main
```

Copy locally:

```
sudo cp -R /mnt/arp/var/lib/postgresql/12/main /recovery/
```

---

### **Step 3 — Start Temporary PostgreSQL**

Start ARP in recovery mode:

```
pg_ctl -D /recovery/main start
```

You now have:

* schema
* data
* old passwords
* old roles
* WAL logs

---

### **Step 4 — Extract Clean Dump**

```
pg_dumpall > arp-clean.sql
```

Upload to S3.

---

### **Step 5 — Restore into AWS RDS**

```
aws s3 cp arp-clean.sql s3://migration-backups/
```

Restore:

```
psql -h arp-rds... < arp-clean.sql
```

---

### **Step 6 — Prepare QA RDS & Validate**

Follow same QA flow as above.

---

### **Step 7 — Final Cutover**

If password extracted → update Secrets Manager
If not → reset password on new RDS and update 15 apps

---

## **3.3 Rollback**

Rollback = recreate EC2 PostgreSQL from snapshot.

---

## **3.4 When To Use This Strategy**

Best for:

✔ ARP database with no password
✔ Server admins unavailable
✔ DMS cannot connect
✔ DB is heavily corrupted

---

# ⭐ **FINAL RECOMMENDATION**

| DB                                    | Best Strategy                       |
| ------------------------------------- | ----------------------------------- |
| OTC                                   | Strategy 2 (Snapshot + Restore)     |
| GPS                                   | Strategy 2 (Snapshot + Restore)     |
| ARP                                   | Strategy 1 (DMS + CDC + Blue/Green) |
| ARP (if password unknown & no access) | Strategy 3 (EBS Snapshot Recovery)  |
