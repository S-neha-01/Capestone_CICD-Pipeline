# Deployment Documentation — StreamingApp Capstone

Submission documentation tracking each step of the DevOps capstone brief. Status
is marked per step; screenshot placeholders are called out where evidence is
needed for grading.

Repository: https://github.com/S-neha-01/Orchestration-Scaling
Upstream: https://github.com/UnpredictablePrashant/StreamingApp

## Architecture

```
                        ┌─────────────┐
                        │   frontend  │  React SPA, nginx, port 3000
                        └──────┬──────┘
                               │
        ┌──────────┬──────────┼──────────┬──────────┐
        ▼          ▼          ▼          ▼          ▼
   ┌────────┐ ┌──────────┐ ┌───────┐ ┌────────┐ ┌────────┐
   │  auth  │ │streaming │ │ admin │ │  chat  │ │        │
   │ :3001  │ │  :3002   │ │ :3003 │ │ :3004  │ │        │
   └───┬────┘ └────┬─────┘ └───┬───┘ └───┬────┘ └────────┘
       │           │           │         │
       └───────────┴─────┬─────┴─────────┘
                          ▼
                    ┌──────────┐        ┌────────────┐
                    │  mongo   │        │  S3 (video │
                    │ :27017   │        │   assets)  │
                    └──────────┘        └────────────┘
```

Five containerized services (`frontend`, `authService`, `streamingService`,
`adminService`, `chatService`) plus a shared MongoDB instance, orchestrated
locally via `docker-compose.yml` and in production via the Helm chart at
[`streamingapp/`](./streamingapp).

---

## Step 1 — Version Control ✅ DONE

- Forked `UnpredictablePrashant/StreamingApp` to this repository.
- Remotes configured:
  - `origin` → `https://github.com/S-neha-01/Orchestration-Scaling.git`
  - `upstream` → `https://github.com/UnpredictablePrashant/StreamingApp.git`
- Verified `upstream/main` is an ancestor of local `main` before the initial
  push (clean fast-forward, no history rewrite).

**Screenshot:** `git remote -v` output; GitHub fork page showing commit history.

---

## Step 2 — Containerization ✅ DONE (local verification)

Dockerfiles exist for all five services:
- [`frontend/Dockerfile`](./frontend/Dockerfile) — multi-stage build (node → nginx)
- [`backend/authService/Dockerfile`](./backend/authService/Dockerfile)
- [`backend/streamingService/Dockerfile`](./backend/streamingService/Dockerfile)
- [`backend/adminService/Dockerfile`](./backend/adminService/Dockerfile)
- [`backend/chatService/Dockerfile`](./backend/chatService/Dockerfile)

Verified locally:
```bash
docker compose up -d --build
docker compose ps          # all 6 containers Up, 0 restarts
```
All services connected to MongoDB successfully and responded on their
respective ports; frontend served the built React app on `:3000` (HTTP 200).

Credential-validation hardening added to `adminService`/`streamingService`
S3 controllers (fail fast with a clear error instead of a silent/late S3 error
if AWS credentials are missing) — commit `c0f14ef`.

**Screenshot:** `docker compose ps` showing all 6 containers healthy; `docker images` listing the 5 built images.

⚠️ ECR push for these images is **PENDING** — see Step 3.

---

## Step 3 — AWS CLI / Account Access ⏸️ BLOCKED

AWS CLI is installed and authenticates successfully:
```bash
aws sts get-caller-identity
# UserId: AIDA6GBMCU7ZPXD52PJHJ, Account: 975050024946
```

However this IAM user has **no authorization** beyond `sts:GetCallerIdentity` —
confirmed via repeated `AccessDeniedException`/`UnauthorizedOperation` on:
- `ecr:DescribeRepositories`
- `ec2:DescribeInstances`, `ec2:DescribeKeyPairs`, `ec2:DescribeVpcs`
- `iam:ListAttachedUserPolicies`, `iam:ListUserPolicies`, `iam:ListGroupsForUser`

This blocks Steps 4 (Jenkins on EC2), 2's ECR push, 5 (EKS), 6 (CloudWatch),
and 9 (SNS). Requested permissions from account admin; pending grant or
provisioning of an alternate AWS account with sufficient access.

**Screenshot:** the `AccessDeniedException` output, as evidence the blocker is real and was investigated, not skipped.

---

## Step 4 — Jenkins CI ⏸️ PARTIALLY READY (execution blocked by Step 3)

[`Jenkinsfile`](./Jenkinsfile) defines the full pipeline: checkout → parallel
image builds → ECR login → tag → push → EKS deploy via Helm. Renamed all
resource identifiers from the previous fork owner's naming (`rajsaw`) to
this account's own (`sneha`) — commit `b5f4fc1`:
- `ECR_BASE` → `.../batch-14/sneha`
- `EKS_CLUSTER` → `sneha-streaming-cluster`
- Jenkins `credentialsId` → `sneha-ecr-cred`

[`infra/jenkins-ec2-userdata.sh`](./infra/jenkins-ec2-userdata.sh) is a ready
EC2 user-data script installing Jenkins, Docker, AWS CLI, kubectl, and Helm on
boot — run via `aws ec2 run-instances --user-data file://...` once EC2 access
exists.

Tried the shared academy Jenkins (`jenkinsacademics.herovired.com`) with the
brief's provided credentials — returned `401 Unauthorized`; not pursued further
without valid credentials.

**Pending:** EC2 instance launch, Jenkins credential setup for `sneha-ecr-cred`, first pipeline run.

---

## Step 5 — Kubernetes Deployment (EKS + Helm) ⏸️ PARTIALLY READY

Helm chart at [`streamingapp/`](./streamingapp) validated locally:
```bash
helm lint ./streamingapp        # 0 charts failed
helm template streamingapp ./streamingapp | grep image:
# all 5 service images correctly resolve to .../batch-14/sneha/<service>:latest
```

**Pending:** `eksctl create cluster`, `helm upgrade --install` against a real cluster.

---

## Step 6 — Monitoring and Logging ⏸️ PLANNED

See [`infra/monitoring-setup.md`](./infra/monitoring-setup.md) — CloudWatch
Container Insights enablement command and a sample CPU alarm, ready to run
once an EKS cluster exists.

**Pending:** execution once Step 5 cluster is live.

---

## Step 7 — Documentation ✅ THIS DOCUMENT

Supplementary docs already in the repo:
- [`README.md`](./README.md) — service/env-var reference
- [`CODE_STRUCTURE.md`](./CODE_STRUCTURE.md) — repo layout and service responsibilities
- [`helm.md`](./helm.md) — command reference for build/push/deploy

---

## Step 8 — Final Validation ⏸️ PARTIAL

- ✅ Local: all 6 services healthy under `docker compose`, frontend reachable, all backends connected to MongoDB.
- ⏸️ Production (EKS): pending Step 5.

---

## Step 9 (Bonus) — ChatOps ⏸️ PLANNED

See [`infra/chatops-setup.md`](./infra/chatops-setup.md) — SNS topic creation,
AWS Chatbot → Slack wiring, and the Jenkinsfile `post` block snippet to publish
on success/failure.

**Pending:** execution once Step 3 is unblocked.

---

## Summary

| Step | Status |
|---|---|
| 1. Version Control | ✅ Done |
| 2. Containerization | ✅ Done locally, ECR push pending |
| 3. AWS CLI / Access | ⏸️ Blocked — IAM permissions |
| 4. Jenkins CI | ⏸️ Config ready, execution pending |
| 5. EKS + Helm | ⏸️ Chart validated, cluster pending |
| 6. Monitoring | ⏸️ Planned |
| 7. Documentation | ✅ This document |
| 8. Final Validation | ⏸️ Local done, production pending |
| 9. ChatOps (bonus) | ⏸️ Planned |
