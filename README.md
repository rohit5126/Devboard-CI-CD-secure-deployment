# 🔐 DevBoard – End-to-End DevSecOps CI/CD + GitOps Platform

A production-grade **DevSecOps CI/CD pipeline** implementing **automated code quality checks, security scanning, container validation, GitOps-based deployment on Kubernetes (EKS), and full observability** using GitHub Actions, ArgoCD, Terraform, and Prometheus/Grafana.

**DevBoard** itself is the demo application shipped through this pipeline — a task/project tracker with a React (Vite) frontend and a Go backend, backed by PostgreSQL.

This project demonstrates a **complete Shift-Left + Shift-Right security approach** with **PR-based validation, modular CI workflows, event-driven CD pipeline, GitOps deployment, and cluster monitoring.**

---

## 🚀 Key Highlights

* 🔄 PR-based automated validation pipeline
* 🔐 Integrated DevSecOps (SAST, Dependency Scan, Secret Scan, Docker Lint & Image Scan)
* 🐳 Automated build & push to Docker Hub, with SonarQube scan on merge
* ⚡ Modular, reusable GitHub Actions workflows
* 🚀 GitOps deployment to Kubernetes via ArgoCD auto-sync
* 🛡️ OWASP ZAP runtime (DAST) security testing
* ☸️ Infrastructure as Code — EKS cluster provisioned via Terraform (remote state in S3)
* 🔑 Centralized secrets management via External Secrets Operator
* 🌐 Envoy Gateway as the cluster ingress
* 📊 Cluster observability via Prometheus + Grafana
* 🧪 Load-tested with `siege` to validate throughput and stability

---

## 🏗️ Pipeline Architecture

```text
Pull Request → CI Checks → Merge (CI) → Update image tags → ArgoCD Sync → DAST Scan
```

**Full lifecycle:**

```text
Terraform (provisions EKS + networking, state in S3)
        ↓
GitHub Actions (PR checks → build/scan → push to Docker Hub → bump Helm tags)
        ↓
ArgoCD (auto-detects Git changes, syncs Helm chart to EKS)
        ↓
Kubernetes workloads (frontend, backend, postgres) behind Envoy Gateway
        ↓
Prometheus + Grafana (cluster & workload monitoring)
```

---

## 🧪 PR Pipeline – `PR-pipeline-checks`

Triggered on:

```yaml
pull_request:
  branches: [master]
  types: [opened, synchronize]
```

### 🔹 Checks Performed

✔ **Frontend Code Quality**
* Node.js linting & validation

✔ **Backend Code Quality**
* Go code checks & dependency validation

✔ **Secret Scanning**
* Detects hardcoded secrets

✔ **Dependency Security Check**
* Vulnerability scanning for frontend (Node) & backend (Go) dependencies

✔ **Docker Lint & Image Scan**
* Validates Dockerfiles for both frontend and backend
* Scans built images for vulnerabilities before merge

All jobs run as a matrix across frontend/backend where applicable, and complete in well under a minute per check.

### 💬 PR Automation

After all checks pass, an automated bot comment is added to the PR:

> **All CI Checks Completed Successfully**
> All automated validation steps for this pull request have passed.
>
> Completed checks include:
> - Code quality analysis (Frontend & Backend)
> - Secret detection scan
> - Dependency vulnerability assessment
> - Vulnerability reports created for frontend and backend
> - Docker build and lint validation
>
> This pull request meets the required quality and security standards and is ready for review and merge.

---

## ⚙️ CI Pipeline – `merge` Workflow

Triggered on:

```yaml
push:
  branches: [master]
```

### 🔹 Jobs

#### 1. SonarQube Scan (SAST)
* Runs static code analysis
* Ensures code quality & maintainability

#### 2. Tag Generation
* Generates a unique image tag per build (short commit SHA / random tag)

#### 3. Docker Build & Push
* Builds frontend & backend images
* Pushes images to Docker Hub with the generated tag
  ```bash
  docker push rohit5126/devboard-backend:tagname
  ```

#### 4. Update Helm `values.yaml`
* Bumps the `tags:` field for both `frontend` and `backend` sections using `yq`
* Commits the change back to the GitOps chart, which ArgoCD then picks up

---

## 🚀 CD Pipeline – GitOps Deployment (ArgoCD)

Triggered automatically once the `merge` workflow updates `devboard/values.yaml`.

* ArgoCD watches the `devboard/` Helm chart in this repository
* On detecting a new commit (new image tag), it **auto-syncs** the cluster to match Git — no manual `kubectl apply` needed
* Deploys/updates:
  * `frontend-deployment` + `frontend-service`
  * `backend-deployment` + `backend-service`
  * `postgres` (StatefulSet/Service)
  * `external-secrets` (ServiceAccount + secret sync)
* Rolling updates use Horizontal Pod Autoscaling (see Helm values below), so new ReplicaSets spin up and old ones scale down with zero downtime

---

## 🚀 DAST Pipeline – Runtime Security Scan

Triggered via:

```yaml
workflow_run:
  workflows: [merge]
  types: completed
```

✔ **OWASP ZAP Scan (DAST)**
* Runs after deployment, against the live running service
* Performs runtime vulnerability testing on the deployed application

---

## ☸️ Infrastructure as Code

* **Terraform** (`EKS-terraform-K8s/`) provisions the AWS EKS cluster, node groups, and supporting networking/IAM resources
* **Remote state** is stored in an S3 backend (`S3-backend/`) for team-safe, versioned Terraform state
* Cluster is exposed via an AWS Elastic Load Balancer, fronted by **Envoy Gateway** inside the cluster for ingress routing

## 🔑 Secrets Management

* **External Secrets Operator** syncs secrets from an external secret store (e.g. AWS Secrets Manager / SSM) into Kubernetes `Secret` objects, keeping credentials out of Git and Helm values entirely

## 📦 Helm Deployment Configuration

The `devboard/` Helm chart (`values.yaml`) defines, per service (frontend & backend):

* `replicaCount`, container `image.repository` / `image.tags`
* `service.type: ClusterIP`, exposed `service.port`
* `resources.requests` / `resources.limits` (CPU & memory)
* `autoscaling` — HPA enabled, `minReplicas` / `maxReplicas`, `targetCPUUtilization`
* `storageClassName: gp2` for any persistent volumes (e.g. Postgres)

## 📊 Monitoring & Observability

* **Prometheus + Grafana** dashboards track cluster and workload health across namespaces (`argocd`, `devboard-app`, `envoy-gateway-system`, `external-secrets`, `kube-system`, `monitoring`)
* Tracked metrics include CPU/Memory Utilisation, Requests & Limits Commitment, and per-namespace CPU usage over time
* Example baseline: ~5–6% CPU utilisation, ~47% memory utilisation, ~68–79% requests/limits commitment under normal load

## 🧪 Load Testing

The deployed service has been load-tested using `siege` to validate stability under concurrent traffic:

```bash
siege -c 60 -t 5m "http://<load-balancer-endpoint>/"
```

**Sample results:**

| Metric | Result |
|---|---|
| Transactions | 8,648 hits |
| Availability | 99.97% |
| Elapsed time | 135.88 secs |
| Data transferred | 174.82 MB |
| Response time | 0.93 secs |
| Transaction rate | 63.64 trans/sec |
| Throughput | 1.29 MB/sec |
| Concurrency | 58.88 |
| Successful transactions | 8,648 |
| Failed transactions | 3 |
| Longest transaction | 19.96 secs |
| Shortest transaction | 0.24 secs |

---

## 🔐 DevSecOps Coverage

| Stage | Security Implementation |
| ------------ | ---------------------------------- |
| PR Stage | SAST-lite lint, Secret Scan, Dependency Scan |
| Build Stage | Docker Lint & Image Vulnerability Scan |
| CI Stage | SonarQube Analysis (SAST) |
| Update Stage | Automated Helm tag update via `yq` |
| Deploy Stage | GitOps sync via ArgoCD (no manual deploy) |
| Secrets | External Secrets Operator (no plaintext secrets in Git) |
| Runtime | OWASP ZAP (DAST) |
| Post-Deploy | Load testing (`siege`) + Prometheus/Grafana monitoring |

---

## 📂 Repository Structure

```bash
.
├── .github/workflows/
│   ├── PR-pipeline.yml
│   ├── merge.yml
│   ├── gitops_bump.yml
│   ├── Node-code-quality.yml
│   ├── Go-code-quality.yml
│   ├── secret-scanning.yml
│   ├── security-check.yml
│   ├── docker-lint.yml
│   ├── Sonarcube.yml
│   ├── docker-push.yml
│   ├── OWASP_DAST.yml
│
├── argoCD/                  # ArgoCD Application manifests
├── devboard/                 # Helm chart for the app
│   ├── templates/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── .helmignore
├── EKS-terraform-K8s/         # Terraform for EKS cluster provisioning
├── S3-backend/                # Terraform remote state backend config
├── terraform/                 # Additional Terraform modules
├── frontend/                  # React (Vite) app
│   └── src/
│       ├── api/
│       ├── components/
│       ├── hooks/
│       ├── pages/
│       └── styles/
├── backend/                   # Go backend service
├── Dockerfile
├── Makefile
├── .env.example
├── .gitignore
├── .trivyignore
└── README.md
```

---

## 🔄 Workflow Design

This project follows modern DevOps best practices:

* ✅ Shift-Left Security (PR validation)
* ✅ Reusable workflows for modular design
* ✅ CI/CD separation
* ✅ Event-driven pipeline chaining
* ✅ Automated PR feedback
* ✅ GitOps auto-deploy via ArgoCD
* ✅ Infrastructure as Code (Terraform, remote state in S3)
* ✅ Zero-trust secrets handling (External Secrets Operator)
* ✅ Post-deploy validation (load testing + monitoring)

---

## 🚀 Getting Started

### 1️⃣ Clone Repository

```bash
git clone https://github.com/rohit5126/devboard-cicd-secure-delivery.git
cd devboard-cicd-secure-delivery
```

### 2️⃣ Configure Secrets & Variables

#### 🔐 GitHub Actions Secrets
* `SONAR_TOKEN`
* `DOCKER_TOKEN`

#### ⚙️ GitHub Actions Variables
* `SONAR_HOST_URL`
* `DOCKER_USER`

#### 🔑 Cluster Secrets
* Managed via External Secrets Operator — configure your external secret store (e.g. AWS Secrets Manager) and reference it in the `external-secrets` manifests. No app secrets should be committed to Git or `values.yaml`.

### 3️⃣ Provision Infrastructure

```bash
cd S3-backend/     # bootstrap remote state bucket first
terraform init && terraform apply


cd ../EKS-terraform-K8s/
terraform init && terraform apply
```

### 4️⃣ Bootstrap ArgoCD
```
helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace -f install_values.yml

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

kubectl port-forward service/argocd-server -n argocd 8080:80 --address 0.0.0.0

cd argoCD

kubect  apply -f root.yml
```

### 5️⃣ Trigger Pipelines

* Create PR → triggers **PR pipeline checks**
* Merge → triggers **CI pipeline** (build, scan, push, bump Helm tags)
* Helm tag bump → **ArgoCD auto-syncs** the new version to the cluster
* Post-deploy → triggers **DAST pipeline** against the live service

### 6️⃣ Verify the Deployment

```bash
# Load-test the live endpoint
siege -c 60 -t 5m "http://<your-load-balancer-endpoint>/"
```

### Verify the application and grafana dashboard

```bash
<gateway url>/  -> app

<gateway url>/monitoring  -> grafana dashboard
```

Check the Grafana dashboard for CPU/Memory utilisation and the ArgoCD UI for sync/health status.

---

## 📊 Key Features

✔ Full DevSecOps pipeline implementation
✔ Automated PR validation & feedback
✔ Multi-layer security checks (SAST, dependency, secrets, container, DAST)
✔ Docker-based build system with automated Helm tag bumps
✔ GitOps deployment via ArgoCD — Git is the single source of truth
✔ Infrastructure as Code with remote Terraform state
✔ Centralized, Git-free secrets management
✔ Cluster observability with Prometheus + Grafana
✔ Verified under load with `siege` (99.97% availability at 60 concurrent users)

---


⭐ **Star this repo if you found it useful!**
