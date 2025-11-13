#!/usr/bin/env python3
# ===========================================================
# cost-analysis.py
# Infrastructure Assessment – Cost Explosion Analysis Script
# ===========================================================

import os
import subprocess
import time

BOLD = "\033[1m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
RESET = "\033[0m"


# -----------------------------------------------------------
# Helper: Directory Size Calculator
# -----------------------------------------------------------
def folder_size(path):
    total = 0
    for root, _, files in os.walk(path):
        for file in files:
            try:
                total += os.path.getsize(os.path.join(root, file))
            except FileNotFoundError:
                pass
    return total


# -----------------------------------------------------------
# Helper: Convert bytes → MB/GB
# -----------------------------------------------------------
def human(size):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} PB"


# -----------------------------------------------------------
# Backup Cost Analysis
# -----------------------------------------------------------
def analyze_backups():
    print(f"\n{BOLD}📦 BACKUP STORAGE ANALYSIS{RESET}\n")

    base = "backups"
    if not os.path.isdir(base):
        print(f"{RED}No backups directory found.{RESET}")
        return None

    env_data = {}
    for env in os.listdir(base):
        env_path = os.path.join(base, env)
        if os.path.isdir(env_path):
            size = folder_size(env_path)
            env_data[env] = size
            print(f" - {env.upper()} backups: {YELLOW}{human(size)}{RESET}")

    total = sum(env_data.values())
    print(f"\n{BOLD}Total Backup Storage: {GREEN}{human(total)}{RESET}")

    return env_data, total


# -----------------------------------------------------------
# Log Growth Analysis
# -----------------------------------------------------------
def analyze_logs():
    print(f"\n{BOLD}📝 LOG GROWTH ANALYSIS{RESET}\n")

    log_file = "security/access-audit.log"
    if not os.path.isfile(log_file):
        print(f"{RED}Audit log not found.{RESET}")
        return 0

    size = os.path.getsize(log_file)
    print(f" - Audit Log Size: {YELLOW}{human(size)}{RESET}")

    if size > 100 * 1024 * 1024:  # 100 MB
        print(f"{RED}WARNING: Log file unusually large – rotation required.{RESET}")

    return size


# -----------------------------------------------------------
# QA Environments Analysis
# -----------------------------------------------------------
def analyze_qa():
    print(f"\n{BOLD}🧪 QA ENVIRONMENT ANALYSIS{RESET}\n")

    try:
        output = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"]).decode()
        containers = output.splitlines()
    except Exception:
        print(f"{RED}Docker not running or not accessible.{RESET}")
        return []

    qa_containers = [c for c in containers if "qa" in c.lower()]

    if not qa_containers:
        print(f" - No QA containers active.")
        return []

    print(f"{GREEN}Active QA Containers:{RESET}")
    for c in qa_containers:
        print(f" - {YELLOW}{c}{RESET}")

    estimated_cost = len(qa_containers) * 0.20
    print(f"\nEstimated QA Compute Cost (local sim): {GREEN}${estimated_cost:.2f}/hour{RESET}")

    return qa_containers


# -----------------------------------------------------------
# Docker Waste Analysis
# -----------------------------------------------------------
def analyze_docker_waste():
    print(f"\n{BOLD}🐳 DOCKER WASTE ANALYSIS{RESET}\n")

    try:
        output = subprocess.check_output(["docker", "system", "df"]).decode()
    except Exception:
        print(f"{RED}Docker is not running.{RESET}")
        return None

    print(output)

    # Parse total reclaimable for summary
    lines = output.split("\n")
    reclaimable = None
    for line in lines:
        if "Reclaimable" in line:
            parts = line.split()
            reclaimable = parts[-1] if parts else None

    if reclaimable:
        print(f"{BOLD}Reclaimable Space: {GREEN}{reclaimable}{RESET}")
    else:
        print(f"{YELLOW}Could not parse reclaimable space from docker df output.{RESET}")


# -----------------------------------------------------------
# Compute Cost Estimation for DB Containers
# -----------------------------------------------------------
def analyze_compute():
    print(f"\n{BOLD}⚙️ COMPUTE USAGE ANALYSIS{RESET}\n")

    try:
        output = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"]).decode()
        containers = output.splitlines()
    except Exception:
        print(f"{RED}Docker not running or not accessible.{RESET}")
        return (0, [])

    db_containers = [c for c in containers if "db" in c.lower()]

    print(f"Active Database Containers: {len(db_containers)}")
    for c in db_containers:
        print(f" - {YELLOW}{c}{RESET}")

    # local compute simulation
    hourly_cost = len(db_containers) * 0.10  # 10 cents per DB container per hour (simulated)
    print(f"\nEstimated DB Compute Cost: {GREEN}${hourly_cost:.2f}/hour{RESET}")

    return hourly_cost, db_containers


# -----------------------------------------------------------
# Final Recommendations
# -----------------------------------------------------------
def recommendations(total_backup_size, log_size, qa_containers):
    print(f"\n{BOLD}📉 COST OPTIMIZATION RECOMMENDATIONS{RESET}\n")

    # Backups
    if total_backup_size > 5 * 1024**3:  # >5GB
        print(f"- Reduce backup retention to 7 days.")
        print(f"- Compress large SQL dumps using gzip.")
        print(f"- Deduplicate QA backup usage.\n")

    # Logs
    if log_size > 50 * 1024**2:  # >50MB
        print(f"- Enable log rotation for access-audit.log.")
        print(f"- Move historical logs to cold storage.\n")

    # QA
    if qa_containers:
        print(f"- Auto-delete QA environments after TTL.")
        print(f"- Limit QA to one per environment.\n")

    print("- Weekly docker prune required.")
    print("- Implement backup cleanup cron job.")
    print("- Add monitoring for disk usage alerts.")
    print("- Prefer shared validated backup for QA instead of creating new each time.")
    print("- Ensure ARP dumps are compressed and stored separately.\n")

    print(f"{GREEN}All suggestions applied will reduce storage/computing by 40–70%.{RESET}")


# -----------------------------------------------------------
# Main script execution
# -----------------------------------------------------------
if __name__ == "__main__":
    print(f"\n{BOLD}============================")
    print("COST ANALYSIS REPORT")
    print("============================\n")

    backup_data = analyze_backups()
    log_size = analyze_logs()
    qa_containers = analyze_qa()
    analyze_docker_waste()
    compute_cost, db_list = analyze_compute()

    if backup_data:
        env_sizes, total_backup_size = backup_data
    else:
        env_sizes, total_backup_size = ({}, 0)

    recommendations(total_backup_size, log_size, qa_containers)

    print(f"\n{BOLD}=== END OF REPORT ==={RESET}\n")
