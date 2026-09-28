# DevOps Implementation Report

## 1. Overview

This repository demonstrates an end-to-end DevOps implementation for a full-stack application
using modern DevOps practices. The project covers infrastructure provisioning, containerization,
CI/CD automation, deployment, monitoring, and troubleshooting.

The application consists of:

- A Django REST API backend (with Prometheus metrics endpoint)
- A React (Vite + TypeScript) frontend
- Nginx as a reverse proxy
- Docker & Docker Compose for container orchestration
- GitHub Actions for CI/CD (lint → test → build → deploy)
- AWS EC2 provisioned using Terraform
- AWS S3 bucket for storage
- AWS IAM Role connecting EC2 to S3
- Prometheus + Grafana + Node Exporter for monitoring

---

## 2. Architecture Overview

### High-Level Architecture

```
User (Browser)
      │
      ▼
 Nginx (Port 80)              ← Frontend Container
      │
      ├──── /            → Serves React static files
      └──── /api/*       → Proxies to Django Backend
                                    │
                                    ▼
                          Django REST API (Port 8000)
                          django-prometheus (/metrics)
                                    │
                          Docker Bridge Network (appnet)
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         ▼                          ▼                          ▼
 Prometheus (9090)          Grafana (3000)         Node Exporter (9100)
 (scrapes metrics)          (dashboards)           (system metrics)
         │
         ▼
  AWS S3 Bucket ← IAM Role attached to EC2 (read/write access)
```

### Components

- **Frontend** — React + Vite, served via Nginx, proxies `/api/*` to backend
- **Backend** — Django REST API, exposes `/api/hello/` and `/metrics` endpoints
- **Prometheus** — scrapes metrics from backend and node-exporter every 15 seconds
- **Grafana** — visualizes Prometheus data as live dashboards
- **Node Exporter** — collects EC2 system metrics (CPU, RAM, Disk, Network)
- **Networking** — Docker bridge network (`appnet`), service-to-service via container names
- **Storage** — S3 bucket provisioned for future static asset storage
- **IAM** — EC2 instance attached with IAM role allowing S3 read/write

---

## 3. Containerization Strategy

### Docker Best Practices Used

- Separate Dockerfiles for frontend and backend
- Multi-stage builds to reduce image size
- Containers run as non-root users (`appuser`)
- `.dockerignore` used to exclude:
  - `.env` files
  - `node_modules`
  - Python cache files (`__pycache__`)

### Security Considerations

- Secrets are **never committed** to GitHub
- Environment variables injected at runtime via `docker-compose`
- No sensitive data baked into Docker images
- Non-root user inside every container

### Running Containers in Production

```
docker ps output on EC2:
┌──────────────┬──────────────────────────┬────────┬────────────────────┐
│ NAME         │ IMAGE                    │ STATUS │ PORTS              │
├──────────────┼──────────────────────────┼────────┼────────────────────┤
│ frontend     │ shravanvm/devops-frontend│ Up     │ 0.0.0.0:80->80     │
│ backend      │ shravanvm/devops-backend │ Up     │ 8000/tcp           │
│ prometheus   │ prom/prometheus          │ Up     │ 0.0.0.0:9090->9090 │
│ grafana      │ grafana/grafana          │ Up     │ 0.0.0.0:3000->3000 │
│ node-exporter│ prom/node-exporter       │ Up     │ 0.0.0.0:9100->9100 │
└──────────────┴──────────────────────────┴────────┴────────────────────┘
```

---

## 4. CI/CD Pipeline (GitHub Actions)

### Workflow Trigger

- Triggered on every push to `main` branch
- File: `.github/workflows/cicd-aws-ec2.yml`

### Pipeline Stages

The pipeline has **3 jobs** that run in sequence. If any job fails, the next one does not run.

```
Push to main
     │
     ▼
┌─────────────────────────────────┐
│         lint-and-test           │
│                                 │
│  Backend:                       │
│  • flake8 (Python style check)  │
│  • pytest (Django unit tests)   │
│                                 │
│  Frontend:                      │
│  • eslint (TypeScript linting)  │
└──────────────┬──────────────────┘
               │ only if lint+test pass
               ▼
┌─────────────────────────────────┐
│         build-and-push          │
│                                 │
│  • Build backend Docker image   │
│  • Build frontend Docker image  │
│  • Tag with latest + git SHA    │
│  • Push both to Docker Hub      │
└──────────────┬──────────────────┘
               │ only if build succeeds
               ▼
┌─────────────────────────────────┐
│            deploy               │
│                                 │
│  • SSH into EC2                 │
│  • docker login to Docker Hub   │
│  • docker compose pull          │
│  • docker compose up -d         │
│  • docker ps (verify)           │
└─────────────────────────────────┘
```

### Why Lint and Test First?

This is a core DevOps principle — **fail fast**. If code has style errors or
broken tests, we catch them before wasting time building Docker images or
deploying broken code to production.

### Required GitHub Secrets

| Secret | Description |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `EC2_HOST` | EC2 public IP address |
| `EC2_USER` | EC2 SSH username (`ubuntu`) |
| `EC2_SSH_PRIVATE_KEY` | Private SSH key content |

### Key Benefits

- Fully automated — zero manual intervention after `git push`
- Lint and test gates prevent broken code from reaching production
- Reproducible and consistent builds via Docker
- Rollback possible by redeploying a previous Docker image tag

---

## 5. Infrastructure as Code (Terraform)

### What Terraform Provisions

| Resource | Purpose |
| --- | --- |
| VPC + Subnet | Isolated network for EC2 |
| Internet Gateway | Allows EC2 to reach internet |
| Route Table | Routes traffic through IGW |
| Security Group | Firewall rules for EC2 |
| EC2 Instance | Ubuntu 22.04, t2.micro |
| SSH Key Pair | Secure SSH access |
| Elastic IP | Fixed public IP address |
| S3 Bucket | Storage layer |
| IAM Role | Allows EC2 to access S3 |
| IAM Policy | Grants S3 read/write permissions |
| IAM Instance Profile | Attaches IAM role to EC2 |

### Security Group Rules

| Port | Protocol | Purpose |
| --- | --- | --- |
| 22 | TCP | SSH access |
| 80 | TCP | HTTP (app) |
| 443 | TCP | HTTPS |
| 9090 | TCP | Prometheus UI |
| 3000 | TCP | Grafana UI |
| 9100 | TCP | Node Exporter |

### IAM Role — EC2 to S3 Connection

The EC2 instance is attached with an IAM role that grants it permission
to read and write to the S3 bucket. This is the AWS-recommended way to
give EC2 access to other services — without hardcoding any credentials.

```
EC2 Instance
    └── IAM Instance Profile
            └── IAM Role (devops-assessment-ec2-s3-role)
                    └── IAM Policy
                            └── S3 Actions: GetObject, PutObject,
                                           DeleteObject, ListBucket
                                on: devops-assessment-storage-*
```

### Terraform Outputs

```bash
ec2_public_ip  = "65.2.19.214"
s3_bucket_name = "devops-assessment-storage-e02faad2"
iam_role_name  = "devops-assessment-ec2-s3-role"
ssh_user       = "ubuntu"
```

### Cost-Saving Strategy

This project uses a **destroy-and-recreate pattern**:

```bash
# When done working — destroy everything (saves AWS costs)
terraform destroy

# When needed again — recreate in ~3 minutes
terraform apply
```

After each `terraform apply`, update:
1. `EC2_HOST` secret in GitHub with new IP
2. `.env` file on EC2 with new IP in `ALLOWED_HOSTS`

### Benefits

- Infrastructure is version-controlled alongside application code
- Easy to recreate or destroy environments in minutes
- Consistent cloud setup — no manual clicking in AWS Console
- Incremental apply — Terraform only changes what's different

---

## 6. Monitoring Setup

### Stack

| Tool | Role | Port |
| --- | --- | --- |
| Prometheus | Time-series metrics collection | 9090 |
| Grafana | Metrics visualization dashboard | 3000 |
| Node Exporter | EC2 system metrics (CPU/RAM/Disk) | 9100 |
| django-prometheus | Django app metrics endpoint | 8000/metrics |

### How It Works

```
Every 15 seconds:
Prometheus → scrapes → backend:8000/metrics     (Django app metrics)
Prometheus → scrapes → node-exporter:9100/metrics (System metrics)
Prometheus → scrapes → localhost:9090/metrics   (Self metrics)

Grafana → reads from → Prometheus
       → displays  → Live dashboards
```

### Prometheus Configuration (`deploy/prometheus.yml`)

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'backend'
    static_configs:
      - targets: ['backend:8000']
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```

### Django Prometheus Integration

Added `django-prometheus` library to expose Django metrics:

```python
# settings.py
INSTALLED_APPS = [
    'django_prometheus',  # Must be FIRST
    ...
]

# urls.py
path('', include('django_prometheus.urls')),  # adds /metrics endpoint
```

### Grafana Dashboard

- Dashboard ID: **1860** (Node Exporter Full)
- Data Source: Prometheus (`http://prometheus:9090`)
- Credentials: `admin / admin123`

Metrics visible in dashboard:
- CPU Usage (%)
- Memory Usage (%)
- Disk I/O
- Network Traffic
- System Uptime
- Running Processes

### Prometheus Targets (All UP)

```
http://<EC2_IP>:9090/targets

backend        → UP ✅ (Django app metrics)
node-exporter  → UP ✅ (System metrics)
prometheus     → UP ✅ (Self metrics)
```

---

## 7. Local Setup Guide

### Prerequisites

- Docker Desktop installed and running
- Git

### Run Locally

```bash
# Clone the repository
git clone https://github.com/shravanmungarwadi/Full-Stack-Deployment.git
cd Full-Stack-Deployment

# Start all containers
docker compose up --build

# Access
# Frontend → http://localhost
# Backend  → http://localhost:8000/api/hello/
```

---

## 8. Production Setup Guide

### Step 1 — Provision Infrastructure

```bash
cd infra/terraform
terraform init
terraform apply
# Note the EC2 IP, S3 bucket name from outputs
```

### Step 2 — Configure GitHub Secrets

```
GitHub → Repo → Settings → Secrets and variables → Actions

Add:
- DOCKERHUB_USERNAME
- DOCKERHUB_TOKEN
- EC2_HOST        → IP from terraform output
- EC2_USER        → ubuntu
- EC2_SSH_PRIVATE_KEY → contents of infra/terraform/keys/ec2_key
```

### Step 3 — Setup EC2

```bash
ssh -i infra/terraform/keys/ec2_key ubuntu@<EC2_IP>

sudo usermod -aG docker ubuntu
sudo systemctl restart docker
sudo mkdir -p /opt/devops-assessment
sudo chown ubuntu:ubuntu /opt/devops-assessment
exit
```

### Step 4 — Copy Files to EC2

```bash
scp -i infra/terraform/keys/ec2_key \
    deploy/docker-compose.prod.yml \
    ubuntu@<EC2_IP>:/opt/devops-assessment/

scp -i infra/terraform/keys/ec2_key \
    deploy/prometheus.yml \
    ubuntu@<EC2_IP>:/opt/devops-assessment/
```

### Step 5 — Create .env on EC2

```bash
ssh -i infra/terraform/keys/ec2_key ubuntu@<EC2_IP>
cd /opt/devops-assessment

cat > .env << EOF
DOCKERHUB_USERNAME=shravanmungarwadi
ALLOWED_HOSTS=<EC2_IP>,backend,localhost
EOF
exit
```

### Step 6 — Trigger Pipeline

```bash
git commit --allow-empty -m "trigger: redeploy after terraform apply"
git push origin main
```

### Step 7 — Verify Everything

```
App         → http://<EC2_IP>
Prometheus  → http://<EC2_IP>:9090/targets  (all 3 targets UP)
Grafana     → http://<EC2_IP>:3000          (admin/admin123)
```

---

## 9. Troubleshooting & Debugging Log

### Issue 1: Git Push Rejected Due to Large Files

**Cause:** `.terraform` directory committed accidentally before `.gitignore` was set up.

**Fix:**
```bash
echo ".terraform/" >> .gitignore
git rm -r --cached .terraform
git commit -m "fix: remove .terraform from tracking"
```

---

### Issue 2: GitHub Actions Not Starting Due to Billing Lock

**Symptoms:** Workflows did not start. Status showed *"Account is locked due to a billing issue"*.

**Root Cause:** International transactions were disabled on the linked debit card.
GitHub could not verify billing, temporarily locking Actions.

**Fix:** Enabled international transactions on the debit card.
Waited for GitHub verification, then manually re-ran the workflow.

---

### Issue 3: Docker Permission Denied on EC2

**Symptoms:** CI/CD deploy job failed with `permission denied while trying to connect to Docker daemon`.

**Root Cause:** EC2 `ubuntu` user was not in the `docker` group.

**Fix:**
```bash
sudo usermod -aG docker ubuntu
sudo systemctl restart docker
```

---

### Issue 4: Frontend Showing "Connection Failed" Despite Backend Running

**Symptoms:** Frontend loaded but API calls returned HTTP 400. Browser showed connection failed.

**Root Cause:** Django `ALLOWED_HOSTS` was empty. Nginx proxy requests were rejected.

**Fix:**
```yaml
# docker-compose.prod.yml
environment:
  - ALLOWED_HOSTS=*
```
```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate backend
curl http://localhost/api/hello/
# Returns: {"message": "Hello World from Django Backend!"}
```

---

### Issue 5: Flake8 Lint Failures in CI/CD Pipeline

**Symptoms:** `lint-and-test` job failed with E302, E303, E402, F401, W292 errors.

**Root Cause:** Python code didn't follow PEP8 style rules — imports in wrong place,
unused imports, missing blank lines, missing newline at end of file.

**Fix:** Moved `import os` to top of `settings.py`, removed unused imports,
added 2 blank lines before all function/class definitions, added newline at EOF.

**Lesson:** Run `flake8` locally before pushing to catch these early.

---

### Issue 6: AWS Security Group DependencyViolation (15-Minute Timeout)

**Symptoms:**
```
Error: DependencyViolation: resource sg-0d64a83c6abdab23d has a dependent object
```
Terraform timed out after 15 minutes trying to delete the security group.

**Root Cause:** Changed the `description` field of `aws_security_group` which is
an immutable field in AWS. This forced Terraform to destroy and recreate the SG.
But AWS couldn't delete the old SG while EC2 was still attached to it.

**Fix:**
1. Went to AWS Console → EC2 → Change Security Groups
2. Added the default SG temporarily (EC2 must always have at least 1 SG)
3. This freed the old SG from EC2
4. Ran `terraform apply` again — deleted in 1 second

**Lesson:** Never change the `description` of an existing `aws_security_group`.
Only add/remove rules using separate `aws_vpc_security_group_ingress_rule` resources.

---

### Issue 7: Prometheus Showing Backend as DOWN (value = 0)

**Symptoms:** `up{job="backend"} = 0` in Prometheus even though Django was running.

**Root Cause (two issues):**
1. Django had no `/metrics` endpoint — needed `django-prometheus` library
2. Django's `ALLOWED_HOSTS` rejected Prometheus scrape requests because
   `backend:8000` hostname wasn't in the allowed list

**Fix:**
```bash
# requirements.txt
django-prometheus==2.3.1

# settings.py — first item in INSTALLED_APPS
'django_prometheus',

# urls.py
path('', include('django_prometheus.urls')),

# .env on EC2
ALLOWED_HOSTS=65.2.19.214,backend,localhost
```

**Verification:**
```bash
docker exec prometheus wget -qO- http://backend:8000/metrics | head -3
# Returns: # HELP django_http_requests_total_by_method_total ...
```

---

### Issue 8: Grafana Dashboard Showing N/A for All Metrics

**Symptoms:** After importing dashboard ID 1860, all panels showed N/A or No data.

**Root Cause (two issues):**
1. `node-exporter` container was not added — dashboard requires it for system metrics
2. After adding node-exporter, Prometheus still used old config without the
   `node-exporter` scrape job — required a container restart to reload config

**Fix:**
```bash
# Added node-exporter to docker-compose.prod.yml
# Added node-exporter job to prometheus.yml
# Copied updated files to EC2
# Restarted prometheus container to reload config
docker compose -f docker-compose.prod.yml restart prometheus
```

---

### Issue 9: Internet Connection Drop During terraform apply

**Symptoms:**
```
dial tcp: lookup ec2.ap-south-1.amazonaws.com: no such host
```

**Root Cause:** Local WiFi dropped while Terraform was talking to AWS API.

**Fix:** Waited for internet to restore, ran `terraform apply` again.
Terraform resumed from where it left off using the state file.

**Lesson:** Terraform is stateful — always re-run `apply` after a network
interruption. Never manually edit `terraform.tfstate`.
