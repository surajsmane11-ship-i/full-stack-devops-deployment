# 🚀 DevOps Assessment – Full Stack Deployment

A complete end-to-end DevOps implementation of a "Hello World" full-stack application using
industry-standard practices including containerization, CI/CD automation, cloud deployment,
Infrastructure as Code, and monitoring.

---

## 🌐 Live Demo

> ⚠️ **Note:** This project uses AWS EC2 with Elastic IP. Infrastructure is brought up on demand
> to save costs. URLs below are updated each time the project is redeployed.

| Service | URL |
| --- | --- |
| Frontend | http://\<ELASTIC_IP\> |
| Backend API | http://\<ELASTIC_IP\>/api/hello/ |
| Prometheus | http://\<ELASTIC_IP\>:9090 |
| Grafana | http://\<ELASTIC_IP\>:3000 |

> 📌 **Current IP:** Update this after every `terraform apply` with the new Elastic IP shown in the terminal output.

---

## 🧰 Tech Stack

| Category | Technology |
| --- | --- |
| Frontend | React, Vite, TypeScript |
| Backend | Django 6.0, Django REST Framework |
| Web Server | Nginx (reverse proxy) |
| Containerization | Docker, Docker Compose |
| CI/CD | GitHub Actions |
| Cloud | AWS EC2 (ap-south-1) |
| Infrastructure as Code | Terraform |
| Container Registry | Docker Hub |
| Storage | AWS S3 |
| IAM | AWS IAM Role + Policy |
| Monitoring | Prometheus, Grafana, Node Exporter |

---

## 🏗️ Architecture Overview

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
                               Docker Network (appnet)
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
      Prometheus (9090)      Grafana (3000)     Node Exporter (9100)
              │
              ▼
         AWS S3 Bucket ← IAM Role attached to EC2
```

---

## 📁 Project Structure

```
Full-Stack-Deployment/
├── backend/                    # Django REST API
│   ├── config/                 # Django settings & URLs
│   ├── core/                   # App with /api/hello/ endpoint
│   ├── Dockerfile              # Multi-stage backend Docker image
│   ├── requirements.txt        # Production dependencies
│   ├── requirements-dev.txt    # Dev + testing dependencies
│   ├── pytest.ini              # Pytest configuration
│   └── .dockerignore
│
├── frontend/                   # React + Vite + TypeScript
│   ├── src/                    # React source code
│   ├── Dockerfile              # Multi-stage frontend Docker image
│   ├── nginx.conf              # Nginx reverse proxy config
│   └── .dockerignore
│
├── deploy/
│   ├── docker-compose.prod.yml # Production compose (used on EC2)
│   └── prometheus.yml          # Prometheus scrape configuration
│
├── infra/
│   └── terraform/              # AWS infrastructure as code
│       ├── main.tf             # EC2, VPC, SG, EIP, S3, IAM
│       ├── variables.tf        # Configurable variables
│       ├── outputs.tf          # EC2 IP, S3 bucket, IAM role outputs
│       ├── provider.tf         # AWS provider config
│       ├── versions.tf         # Terraform version constraints
│       └── keys/               # SSH key pair (ec2_key.pub)
│
├── .github/
│   └── workflows/
│       └── cicd-aws-ec2.yml    # GitHub Actions CI/CD pipeline
│
├── screenshots/                # Project screenshots for submission
├── docker-compose.yml          # Local development compose
├── DEVOPS.md                   # Detailed DevOps implementation report
├── TROUBLESHOOTING.md          # All challenges and solutions
└── README.md
```

---

## ⚙️ How to Run Locally

### Prerequisites

- Docker Desktop installed and running
- Git

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/shravanmungarwadi/Full-Stack-Deployment.git
cd Full-Stack-Deployment

# 2. Start both containers
docker compose up --build

# 3. Open in browser
# Frontend: http://localhost
# Backend:  http://localhost:8000/api/hello/
```

---

## 🐳 Docker Implementation

### Multi-Stage Builds

Both Dockerfiles use multi-stage builds to keep image sizes small:

**Backend** (`backend/Dockerfile`):
```
Stage 1 (builder) → installs Python dependencies
Stage 2 (runtime) → copies only what's needed, runs as non-root user
```

**Frontend** (`frontend/Dockerfile`):
```
Stage 1 (builder) → Node.js builds React app into static HTML/CSS/JS
Stage 2 (runtime) → Nginx serves the static files, runs as non-root user
```

### Security Practices

- ✅ Non-root users inside containers (`appuser`)
- ✅ No secrets hardcoded in Dockerfiles
- ✅ `.dockerignore` excludes `node_modules`, `.env`, `__pycache__`
- ✅ Environment variables injected at runtime via `docker-compose`

---

## 🔄 CI/CD Pipeline (GitHub Actions)

**File:** `.github/workflows/cicd-aws-ec2.yml`

**Trigger:** Every push to `main` branch

### Pipeline Stages

```
Push to main
     │
     ▼
┌─────────────────────┐
│    lint-and-test    │
│                     │
│  • flake8 (Python)  │
│  • pytest (Django)  │
│  • eslint (React)   │
└─────────┬───────────┘
          │  only if lint+test pass
          ▼
┌─────────────────────┐
│   build-and-push    │
│                     │
│  • Build backend    │
│    Docker image     │
│  • Build frontend   │
│    Docker image     │
│  • Push both to     │
│    Docker Hub       │
└─────────┬───────────┘
          │  only if build succeeds
          ▼
┌─────────────────────┐
│      deploy         │
│                     │
│  • SSH into EC2     │
│  • Pull new images  │
│  • Restart with     │
│    docker compose   │
└─────────────────────┘
```

### Required GitHub Secrets

| Secret | Description |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `EC2_HOST` | EC2 public/Elastic IP address |
| `EC2_USER` | EC2 SSH username (`ubuntu`) |
| `EC2_SSH_PRIVATE_KEY` | Private SSH key for EC2 access |

---

## ☁️ Infrastructure as Code (Terraform)

**Directory:** `infra/terraform/`

### What Terraform Provisions

- ✅ VPC with DNS support
- ✅ Public subnet
- ✅ Internet Gateway + Route Table
- ✅ EC2 instance (Ubuntu 22.04, t2.micro)
- ✅ Security Group (ports 22, 80, 443, 9090, 3000, 9100)
- ✅ SSH Key Pair
- ✅ Elastic IP
- ✅ S3 Bucket (storage layer)
- ✅ IAM Role + Policy (EC2 → S3 read/write access)
- ✅ IAM Instance Profile (attaches role to EC2)
- ✅ Docker auto-installed via `user_data` script

### Key Outputs

```bash
ec2_public_ip  = "XX.XX.XX.XX"
s3_bucket_name = "devops-assessment-storage-XXXXXX"
iam_role_name  = "devops-assessment-ec2-s3-role"
ssh_user       = "ubuntu"
```

### Usage

```bash
# Navigate to terraform directory
cd infra/terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Create infrastructure
terraform apply

# Destroy everything (saves costs when not in use)
terraform destroy
```

---

## 📊 Monitoring Setup

| Tool | Purpose | Port |
| --- | --- | --- |
| Prometheus | Scrapes metrics from app + system | 9090 |
| Grafana | Visualizes metrics as dashboards | 3000 |
| Node Exporter | Collects EC2 system metrics (CPU/RAM/Disk) | 9100 |
| django-prometheus | Exposes Django app metrics at `/metrics` | 8000 |

### Grafana Login
```
URL:      http://<EC2_IP>:3000
Username: admin
Password: admin123
```

### Prometheus Targets
All 3 targets should show **UP** at `http://<EC2_IP>:9090/targets`:
```
backend       → UP ✅
node-exporter → UP ✅
prometheus    → UP ✅
```

---

## 🔁 Re-deploy Guide (After terraform destroy)

Every time you run `terraform destroy` and `terraform apply` again:

```bash
# Step 1 — Create infrastructure
cd infra/terraform
terraform apply
# Note the EC2 IP shown in output

# Step 2 — Update GitHub Secret
# GitHub → Settings → Secrets → Update EC2_HOST with new IP

# Step 3 — SSH into EC2 and setup Docker permissions
ssh -i infra/terraform/keys/ec2_key ubuntu@<NEW_IP>
sudo usermod -aG docker ubuntu
sudo systemctl restart docker
sudo mkdir -p /opt/devops-assessment
sudo chown ubuntu:ubuntu /opt/devops-assessment
exit

# Step 4 — Copy compose and prometheus files to EC2
scp -i infra/terraform/keys/ec2_key deploy/docker-compose.prod.yml ubuntu@<NEW_IP>:/opt/devops-assessment/
scp -i infra/terraform/keys/ec2_key deploy/prometheus.yml ubuntu@<NEW_IP>:/opt/devops-assessment/

# Step 5 — Create .env on EC2
ssh -i infra/terraform/keys/ec2_key ubuntu@<NEW_IP>
cd /opt/devops-assessment
cat > .env << EOF
DOCKERHUB_USERNAME=shravanmungarwadi
ALLOWED_HOSTS=<NEW_IP>,backend,localhost
EOF
exit

# Step 6 — Trigger CI/CD pipeline
git commit --allow-empty -m "trigger: redeploy after terraform apply"
git push origin main

# Step 7 — App is live! 🎉
# http://<NEW_IP>       → Application
# http://<NEW_IP>:9090  → Prometheus
# http://<NEW_IP>:3000  → Grafana
```

---

## 📋 Evaluation Criteria Checklist

| Criteria | Status |
| --- | --- |
| Multi-stage Docker builds | ✅ |
| Non-root users in containers | ✅ |
| `.dockerignore` files | ✅ |
| No hardcoded secrets | ✅ |
| CI/CD lint step (flake8 + eslint) | ✅ |
| CI/CD test step (pytest) | ✅ |
| CI/CD triggers on push to main | ✅ |
| Images pushed to Docker Hub | ✅ |
| Deployed to AWS EC2 (Cloud) | ✅ |
| Terraform — Compute (EC2) | ✅ |
| Terraform — Networking (VPC, SG) | ✅ |
| Terraform — Storage (S3) | ✅ |
| IAM Role connecting EC2 to S3 | ✅ |
| Prometheus monitoring | ✅ |
| Grafana dashboard | ✅ |
| Node Exporter system metrics | ✅ |
| DEVOPS.md documentation | ✅ |
| TROUBLESHOOTING.md log | ✅ |

---

## 📸 Screenshots

### Application Running
![App](screenshots/app.png)

### CI/CD Pipeline — All Jobs Green
![Pipeline](screenshots/github-actions.png)

### Prometheus Targets
![Prometheus](screenshots/prometheus-targets.png)

### Grafana Dashboard
![Grafana](screenshots/grafana-dashboard.png)

### AWS EC2 Instance
![EC2](screenshots/ec2-instance.png)

### AWS S3 Bucket
![S3](screenshots/s3-bucket.png)

---

## 👤 Author

**Shravan Mungarwadi**

- GitHub: [@shravanmungarwadi](https://github.com/shravanmungarwadi)
- Docker Hub: [shravanvm](https://hub.docker.com/u/shravanvm)
