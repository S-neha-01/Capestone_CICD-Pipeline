# Deployment Documentation — StreamingApp Capstone

Submission documentation tracking each step of the DevOps capstone brief. Status
is marked per step; screenshot placeholders are called out where evidence is
needed for grading.

Repository: https://github.com/S-neha-01/Capestone_CICD-Pipeline
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

✅ All 5 images pushed to ECR (`378436334075.dkr.ecr.us-east-1.amazonaws.com/streamingapp/*:latest`).

---

## Step 3 — AWS CLI / Account Access ✅ DONE

The original account (975050024946) stayed locked to `sts:GetCallerIdentity`
only — see the original blocker evidence still below. Moved to a second,
fully-authorized personal AWS account (378436334075, `us-east-1`) instead:

```bash
aws sts get-caller-identity --profile cloud-automation
# UserId: AIDAVQHEQGH5XFVXAYYJY, Account: 378436334075, User: Sneha
```

Verified real access (not just identity) across every service the pipeline
needs: ECR, EC2, EKS, VPC, CloudWatch, SNS.

**Screenshot:** `aws sts get-caller-identity` output for the working account; IAM console showing attached policies.

<details>
<summary>Original blocked-account evidence (kept for the record)</summary>

```bash
aws sts get-caller-identity
# UserId: AIDA6GBMCU7ZPXD52PJHJ, Account: 975050024946
```

This IAM user had **no authorization** beyond `sts:GetCallerIdentity` —
confirmed via repeated `AccessDeniedException`/`UnauthorizedOperation` on:
- `ecr:DescribeRepositories`
- `ec2:DescribeInstances`, `ec2:DescribeKeyPairs`, `ec2:DescribeVpcs`
- `iam:ListAttachedUserPolicies`, `iam:ListUserPolicies`, `iam:ListGroupsForUser`

Requested permissions from the account admin; no grant arrived, so the
capstone was completed on a second personal account instead (see above).

</details>

---

## Step 4 — Jenkins CI ⏸️ IN PROGRESS

[`Jenkinsfile`](./Jenkinsfile) defines the full pipeline: checkout → parallel
image builds → ECR login → tag → push → EKS deploy via Helm. Resource
identifiers point at this account (`378436334075`, `us-east-1`) — commit
`b5f4fc1` and later:
- `ECR_BASE` → `378436334075.dkr.ecr.us-east-1.amazonaws.com/streamingapp`
- `EKS_CLUSTER` → `sneha-streaming-cluster`
- Jenkins `credentialsId` → `sneha-ecr-cred`

Jenkins deployed via [`infra/jenkins-ec2-userdata.sh`](./infra/jenkins-ec2-userdata.sh)
on a `t3.medium` EC2 instance (`streamingapp-jenkins`), running Jenkins,
Docker, AWS CLI, kubectl, and Helm. Access locked to a single trusted IP via
`streamingapp-jenkins-sg` (ports 22 and 8080 only).

All 5 images already exist in ECR with the `latest` tag (pushed while
verifying the account's access ahead of the first Jenkins-triggered run).
Jenkins pipeline job (`streamingapp-pipeline`) and the `sneha-ecr-cred`
credential are being created now.

**Pending:** first Jenkins-triggered pipeline run (not yet executed through Jenkins itself).

**Screenshot:** Jenkins pipeline stage view showing a green end-to-end run, once triggered.

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
