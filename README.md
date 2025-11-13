# Infrastructure Assessment – README

## Overview
This repository contains a proof-of-concept multi-environment PostgreSQL setup with accompanying automation and CI/CD pipeline, designed to simulate the migration of three production databases (OTC, GPS, ARP) to a new AWS multi-account architecture. The project includes:
- Docker-based **local environment simulation** for dev, staging, and prod, each with isolated networks and a bastion host.
- Automation scripts for **backup**, **restore/QA environment creation**, **secrets rotation**, and **emergency backup**.
- A GitHub Actions **CI/CD pipeline** that runs scheduled backups, validates migrations in an ephemeral QA environment, performs migrations with rollback on failure, and scans for security issues.
- Security measures including network isolation (simulated via Docker networks and described via security groups), centralized logging of DB access, and scripts to enforce password rotation and auditing.

These instructions will help you set up and test the solution locally, and explain how to extend or deploy it to AWS.

## Prerequisites
- **Docker and Docker Compose:** Ensure Docker is installed and running. Docker Compose is used to bring up the multi-container environment.
- **Bash shell:** The automation scripts are written in Bash. They should run on any Unix-like system or Docker container that has the necessary tools (e.g., `docker` CLI, `gzip`, etc.).
- **GitHub account (optional):** if you want to test the GitHub Actions workflow, you can fork this repo to your GitHub and enable Actions. Otherwise, you can read the workflow file for understanding.

> **Security Note:** The repository does not contain any real secrets. Dummy passwords (e.g., `otc_dev_pass`) are present for local demo convenience. In a real setup, you should supply strong passwords via environment variables or secret management and **never commit real credentials**.

## Setup – Local Docker Environment
1. **Clone the Repository:**
   ```bash
   git clone https://github.com/pratikmohite16/infrastructure-assessment
   cd infrastructure-assessment
