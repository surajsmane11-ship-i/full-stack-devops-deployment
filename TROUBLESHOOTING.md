# 🛠️ Troubleshooting Log

This document records all the real challenges encountered during this DevOps project
and exactly how each one was diagnosed and resolved.

---

## Issue 1: Git Push Rejected Due to Large Files

**Phase:** Version Control Setup

**Symptoms:**
```
error: File .terraform/providers/... exceeds GitHub's file size limit of 100MB
remote: error: GH001: Large files detected.
```

**Root Cause:**
The `.terraform` directory (which contains provider binaries) was accidentally
committed to Git before `.gitignore` was configured.

**Fix Applied:**
```bash
# Add to .gitignore
echo ".terraform/" >> .gitignore

# Remove from Git tracking without deleting the files
git rm -r --cached .terraform

# Commit the fix
git commit -m "fix: remove .terraform from tracking"
git push origin main
```

**Lesson Learned:**
Always configure `.gitignore` before the first `git add .`. The `.terraform`
directory must always be excluded — it contains binary provider files that
are too large for GitHub and are machine-specific anyway.

---

## Issue 2: GitHub Actions Not Starting Due to Billing Lock

**Phase:** CI/CD Setup

**Symptoms:**
- GitHub Actions workflows did not start after push
- Jobs showed status: *"Account is locked due to a billing issue"*
- No pipeline logs were generated at all

**Root Cause:**
International transactions were disabled on the linked debit card.
GitHub could not verify billing, which temporarily locked Actions.

**Fix Applied:**
1. Enabled international transactions on the debit card
2. Waited for GitHub billing verification to complete (~10 minutes)
3. Manually re-ran the GitHub Actions workflow

**Verification:**
GitHub Actions jobs started successfully. Build and deploy stages
executed without any billing errors.

---

## Issue 3: Docker Permission Denied on EC2

**Phase:** First Deployment to EC2

**Symptoms:**
```
permission denied while trying to connect to the Docker daemon socket
at unix:///var/run/docker.sock
```

**Root Cause:**
The EC2 `ubuntu` user was not added to the `docker` group.
Docker socket requires elevated group membership to use without `sudo`.

**Fix Applied:**
```bash
sudo usermod -aG docker ubuntu
sudo systemctl restart docker
# Log out and back in for group change to take effect
exit
```

**Why This Matters (DevOps Perspective):**
Running Docker commands with `sudo` in CI/CD pipelines is a security risk.
Adding the user to the `docker` group is the correct production approach.

---

## Issue 4: Frontend Showing "Connection Failed" Despite Backend Running

**Phase:** Production Deployment

**Symptoms:**
- Frontend UI loaded successfully
- Backend container was running
- API requests returned HTTP 400 Bad Request
- Browser showed: "Failed to connect to the backend"

**Root Cause:**
Django's `ALLOWED_HOSTS` setting was empty (`[]`). Requests coming through
Nginx proxy were being rejected because Django didn't trust the hostname.

**Fix Applied:**
```yaml
# In docker-compose.prod.yml
environment:
  - ALLOWED_HOSTS=*
```

Then force-recreated the backend container:
```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate backend
```

**Verification:**
```bash
curl http://localhost/api/hello/
# Returns: {"message": "Hello World from Django Backend!"}
```

---

## Issue 5: Flake8 Lint Failures in CI/CD Pipeline

**Phase:** Adding Lint + Test to CI/CD

**Symptoms:**
GitHub Actions `lint-and-test` job failed with multiple errors:
```
./config/settings.py:28:1: E402 module level import not at top of file
./config/settings.py:34:1: E303 too many blank lines (3)
./core/admin.py:1:1: F401 'django.contrib.admin' imported but unused
./core/models.py:1:1: F401 'django.db.models' imported but unused
./core/tests.py:3:1: E302 expected 2 blank lines, found 1
./core/views.py:3:1: E302 expected 2 blank lines, found 1
./core/tests.py:17:78: W292 no newline at end of file
```

**Root Cause:**
Python code didn't follow PEP8 style rules:
- `import os` was in the middle of `settings.py` instead of the top
- Unused imports in `admin.py` and `models.py`
- Missing blank lines before function/class definitions
- Missing newline at end of files

**Fix Applied:**
1. Moved `import os` to the top of `settings.py`
2. Removed unused imports from `admin.py` and `models.py`
3. Added 2 blank lines before all function and class definitions
4. Added newline at end of `tests.py`

**Lesson Learned:**
Run flake8 locally before pushing to catch these issues early:
```bash
cd backend
pip install flake8
flake8 . --max-line-length=120 --exclude=migrations,__pycache__
```

---

## Issue 6: AWS Security Group DependencyViolation (15-Minute Timeout)

**Phase:** Adding Prometheus + Grafana ports to Security Group

**Symptoms:**
```
Error: deleting Security Group (sg-0d64a83c6abdab23d):
DependencyViolation: resource sg-0d64a83c6abdab23d has a dependent object
```

Terraform tried to destroy and recreate the security group for 15+ minutes
and timed out. This happened because the `description` field was changed.

**Root Cause:**
AWS security group `description` is an **immutable field**. Once created,
it cannot be updated in-place. Terraform was forced to:
1. Destroy the old security group
2. Create a new one

But AWS couldn't delete the old SG because EC2's network interface was
still attached to it, causing the `DependencyViolation` error.

**Fix Applied:**

Step 1 — Wait for Terraform to time out and exit

Step 2 — Go to AWS Console:
```
EC2 → Instances → i-06d6f281fb1ec9a05
→ Actions → Security → Change security groups
→ Add "default" security group
→ Save (EC2 must always have at least 1 SG attached)
```

Step 3 — Run terraform apply again:
```bash
terraform apply
```
This time the old SG had no dependencies — deleted in 1 second ✅

**Lesson Learned:**
**Never change the `description` field of an existing `aws_security_group`.**
Only add/modify ingress and egress rules using separate
`aws_vpc_security_group_ingress_rule` resources. Descriptions are cosmetic
labels only — their immutability makes changing them expensive.

---

## Issue 7: Prometheus Showing Backend as DOWN (value = 0)

**Phase:** Monitoring Setup

**Symptoms:**
Running `up` query in Prometheus showed:
```
up{instance="backend:8000", job="backend"} = 0
```
Even though the backend container was running perfectly fine.

**Root Cause — Two separate issues:**

**Issue A:** Django had no `/metrics` endpoint. Prometheus was trying to
scrape `backend:8000/metrics` but Django returned 404.

**Issue B:** Even after installing `django-prometheus`, the scrape was
returning HTTP 400. Docker logs showed:
```
DisallowedHost: Invalid HTTP_HOST header: 'backend:8000'
You may need to add 'backend' to ALLOWED_HOSTS.
```
Prometheus uses the container name `backend:8000` as the Host header,
which Django rejected because it wasn't in `ALLOWED_HOSTS`.

**Fix Applied:**

For Issue A — Added django-prometheus to the backend:
```
# requirements.txt
django-prometheus==2.3.1
```
```python
# settings.py — add to INSTALLED_APPS (must be FIRST)
'django_prometheus',
```
```python
# urls.py
path('', include('django_prometheus.urls')),
```

For Issue B — Updated ALLOWED_HOSTS on EC2:
```bash
cd /opt/devops-assessment
cat > .env << EOF
DOCKERHUB_USERNAME=shravanmungarwadi
ALLOWED_HOSTS=65.2.19.214,backend,localhost
EOF
docker compose -f docker-compose.prod.yml up -d backend
```

**Verification:**
```bash
docker exec prometheus wget -qO- http://backend:8000/metrics | head -5
# Returns: # HELP go_gc_duration_seconds ...
```

Prometheus `up` query then showed:
```
up{instance="backend:8000", job="backend"} = 1  ✅
```

---

## Issue 8: Grafana Dashboard Showing N/A for All Metrics

**Phase:** Grafana Dashboard Setup

**Symptoms:**
After importing Node Exporter Full dashboard (ID: 1860), all panels
showed N/A or "No data".

**Root Cause — Two issues:**

**Issue A:** Node Exporter container was not running. The dashboard
requires `prom/node-exporter` which collects EC2 system metrics.
Without it, Prometheus has no system data to show.

**Issue B:** After adding Node Exporter, Prometheus wasn't scraping it
because the old `prometheus.yml` (without the `node-exporter` job) was
still running. Prometheus needs a restart to reload its config.

**Fix Applied:**

Added node-exporter to `docker-compose.prod.yml`:
```yaml
node-exporter:
  image: prom/node-exporter:latest
  container_name: node-exporter
  restart: always
  ports:
    - "9100:9100"
  networks:
    - appnet
```

Added scrape job to `prometheus.yml`:
```yaml
- job_name: 'node-exporter'
  static_configs:
    - targets: ['node-exporter:9100']
```

Restarted Prometheus to reload config:
```bash
docker compose -f docker-compose.prod.yml restart prometheus
```

**Verification:**
All 3 targets showing UP at `http://65.2.19.214:9090/targets`:
```
backend        UP ✅
node-exporter  UP ✅
prometheus     UP ✅
```

Grafana dashboard then showed live CPU (91.6%), RAM (71.4%), Uptime data.

---

## Issue 9: Internet Connection Drop During terraform apply

**Phase:** Security Group Recreation

**Symptoms:**
```
Error: request send failed
dial tcp: lookup ec2.ap-south-1.amazonaws.com: no such host
```

**Root Cause:**
Local WiFi/internet connection dropped while Terraform was in the middle
of communicating with the AWS API. This is a network issue, not an
AWS or Terraform problem.

**Fix Applied:**
1. Verified internet connection was restored
2. Ran `terraform apply` again — Terraform resumed from where it left off

**Lesson Learned:**
Terraform is stateful. If a `terraform apply` is interrupted by a network
issue, simply run `terraform apply` again. It reads the current state
from `terraform.tfstate` and only applies the remaining changes.
Never use `terraform force-unlock` or manually edit state files unless
absolutely necessary.
