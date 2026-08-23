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

## Step 4 — Jenkins CI ✅ DONE

[`Jenkinsfile`](./Jenkinsfile) defines the full pipeline: checkout → parallel
image builds → ECR login → tag → push → EKS deploy via Helm. Resource
identifiers point at this account (`378436334075`, `us-east-1`) — commit
`b5f4fc1` and later:
- `ECR_BASE` → `378436334075.dkr.ecr.us-east-1.amazonaws.com/streamingapp`
- `EKS_CLUSTER` → `sneha-streaming-cluster`
- Jenkins `credentialsId` → `sneha-ecr-cred`

Run on the shared academy Jenkins (`jenkinsacademics.herovired.com`) as job
**`Sneha-StreamingApp-Capstone`**, pulling this repo's `main` branch.

Security note: that Jenkins instance is shared by the whole cohort with a
flat, unscoped job namespace (500+ jobs, no per-student folders) — a global
credential there is technically referenceable from any job on the instance.
Rather than use full account access, `sneha-ecr-cred` holds a **purpose-built,
least-privilege IAM user** (`sneha-jenkins-ci-scoped`) limited to:
- `ecr:GetAuthorizationToken` (required to be account-wide by the ECR API)
- push/pull only on the `streamingapp/*` repositories
- `eks:DescribeCluster` on `sneha-streaming-cluster` only, plus an EKS
  **access entry** scoped to the `AmazonEKSEditPolicy` on the `streamingapp`
  namespace only (no cluster-wide Kubernetes access)

A private, single-owner Jenkins on EC2 (`streamingapp-jenkins`,
`infra/jenkins-ec2-userdata.sh`, locked to one trusted IP) also exists as a
non-shared alternative if the academy instance becomes unavailable.

**Build history:** #1 failed at the deploy stage (`--create-namespace`
requires cluster-scope permission the scoped user intentionally doesn't
have); fixed by pre-creating the namespace and dropping the flag from the
Jenkinsfile (commit `534e6a5`). **Build #3 succeeded end-to-end** — checkout,
all 5 parallel image builds, ECR push, and Helm deploy to EKS, in ~70s once
Docker layers were cached.

**Screenshot:** Jenkins stage view for build #3 (green, all stages); the `sneha-jenkins-ci-scoped` IAM user's attached policy in the AWS console.

---

## Step 5 — Kubernetes Deployment (EKS + Helm) ✅ DONE

Cluster provisioned via `eksctl` (Kubernetes 1.31, `us-east-1`, 2×`t3.small`
managed nodes, no NAT gateway — public subnets only, to keep cost down):

```bash
eksctl create cluster -f eksctl-cluster.yaml   # cluster + managed nodegroup, ~15 min
kubectl get nodes
# 2 nodes, STATUS Ready
```

Helm chart at [`streamingapp/`](./streamingapp) deployed by the Jenkins
pipeline (see Step 4). Verified live in the cluster:

```bash
kubectl get pods -n streamingapp
# mongo, streamingapp-{frontend,authservice,streamingservice,adminservice,chatservice}
# all 1/1 Running
```

Raw command output saved as evidence: [`docs/screenshots/eks-nodes-ready.txt`](./docs/screenshots/eks-nodes-ready.txt), [`docs/screenshots/eks-pods-running.txt`](./docs/screenshots/eks-pods-running.txt), [`docs/screenshots/eks-deployments-services.txt`](./docs/screenshots/eks-deployments-services.txt), [`docs/screenshots/helm-release-status.txt`](./docs/screenshots/helm-release-status.txt).

**Screenshot:** `kubectl get pods -n streamingapp -o wide` and `kubectl get nodes` from a real terminal, and the EKS cluster/nodegroup page in the AWS console.

⚠️ **Cost note:** this cluster is billable while running (~$0.10/hr control
plane + 2×`t3.small` nodes). Plan is to tear it down after grading evidence
is captured — see the teardown command in [`helm.md`](./helm.md).

---

## Step 6 — Monitoring and Logging ✅ DONE

CloudWatch Container Insights (cloudwatch-agent + fluent-bit daemonsets)
deployed to the cluster. Two real fixes needed along the way:
- The quickstart manifest's pinned `cloudwatch-agent` image tag no longer
  exists in the public ECR registry — repointed the daemonset to `:latest`.
- The node instance role had no CloudWatch permissions — attached AWS's
  managed `CloudWatchAgentServerPolicy` (metrics + logs write only, nothing
  else) to `eksctl-sneha-streaming-cluster-nod-NodeInstanceRole-...`.

Verified real data flowing (not just "pods are Running"):
```bash
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/sneha-streaming-cluster
# /aws/containerinsights/sneha-streaming-cluster/performance
# /aws/containerinsights/sneha-streaming-cluster/host

aws cloudwatch list-metrics --namespace ContainerInsights --dimensions Name=ClusterName,Value=sneha-streaming-cluster
# 20+ real metrics: node_cpu_utilization, pod_memory_utilization, node_number_of_running_pods, ...
```

CPU alarm created per [`infra/monitoring-setup.md`](./infra/monitoring-setup.md):
```bash
aws cloudwatch put-metric-alarm --alarm-name sneha-streaming-high-cpu \
  --namespace ContainerInsights --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value=sneha-streaming-cluster \
  --statistic Average --period 300 --threshold 80 \
  --comparison-operator GreaterThanThreshold --evaluation-periods 2
```

Raw evidence saved: [`docs/screenshots/cloudwatch-container-insights-metrics.txt`](./docs/screenshots/cloudwatch-container-insights-metrics.txt), [`docs/screenshots/cloudwatch-alarm.txt`](./docs/screenshots/cloudwatch-alarm.txt).

**Screenshot:** the CloudWatch Container Insights dashboard for `sneha-streaming-cluster` in the AWS console, showing live pod/node metrics; the `sneha-streaming-high-cpu` alarm.

---

## Step 7 — Documentation ✅ THIS DOCUMENT

Supplementary docs already in the repo:
- [`README.md`](./README.md) — service/env-var reference
- [`CODE_STRUCTURE.md`](./CODE_STRUCTURE.md) — repo layout and service responsibilities
- [`helm.md`](./helm.md) — command reference for build/push/deploy

---

## Step 8 — Final Validation ✅ DONE

- ✅ Local: all 6 services healthy under `docker compose`, frontend reachable, all backends connected to MongoDB.
- ✅ Production (EKS): Jenkins build #3 and #4 both green end-to-end (checkout → build → ECR push → Helm deploy); all 6 pods (`mongo` + 5 services) `1/1 Running` in the `streamingapp` namespace on real EKS nodes.

---

## Step 9 (Bonus) — ChatOps ✅ MOSTLY DONE

Two SNS topics created:
```bash
aws sns create-topic --name sneha-deploy-success   # arn:aws:sns:us-east-1:378436334075:sneha-deploy-success
aws sns create-topic --name sneha-deploy-failure   # arn:aws:sns:us-east-1:378436334075:sneha-deploy-failure
```

Jenkinsfile `post` block publishes to the matching topic on every run —
verified for real on build #4:
```
+ aws sns publish --region us-east-1 --topic-arn arn:aws:sns:us-east-1:378436334075:sneha-deploy-success --message StreamingApp build #4 deployed successfully to EKS
{"MessageId": "15b575c0-acd8-5bde-8fe7-16c59c843556"}
```

Raw evidence: [`docs/screenshots/sns-topics.txt`](./docs/screenshots/sns-topics.txt).

**Pending (requires interactive browser OAuth, can't be scripted):** AWS
Chatbot → Slack channel configuration, attaching both topic ARNs, per
[`infra/chatops-setup.md`](./infra/chatops-setup.md) step 2.

**Screenshot:** the two SNS topics in the console; the AWS Chatbot Slack channel configuration once wired up; a Slack message landing after a pipeline run.

---

## Summary

| Step | Status |
|---|---|
| 1. Version Control | ✅ Done |
| 2. Containerization | ✅ Done |
| 3. AWS CLI / Access | ✅ Done |
| 4. Jenkins CI | ✅ Done |
| 5. EKS + Helm | ✅ Done |
| 6. Monitoring | ✅ Done |
| 7. Documentation | ✅ Done |
| 8. Final Validation | ✅ Done |
| 9. ChatOps (bonus) | ✅ Mostly done — Slack OAuth step pending |
