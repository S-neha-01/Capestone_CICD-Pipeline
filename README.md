# StreamingApp — DevOps Capstone

A microservice video-streaming platform (auth, catalogue, admin uploads, live chat)
containerized, built, and deployed end-to-end with a real CI/CD pipeline: **Docker →
Jenkins → ECR → EKS (Helm) → CloudWatch → SNS/Slack**.

This repo is the capstone submission covering the full DevOps brief — version
control, containerization, CI, Kubernetes deployment, monitoring, and ChatOps.
For the detailed, step-by-step status of each brief requirement (with evidence),
see **[DEPLOYMENT.md](./DEPLOYMENT.md)**.

## Architecture

```
                        ┌─────────────┐
                        │   frontend  │  React SPA, nginx, port 3000
                        └──────┬──────┘
                               │
        ┌──────────┬──────────┼──────────┬──────────┐
        ▼          ▼          ▼          ▼          ▼
   ┌────────┐ ┌──────────┐ ┌───────┐ ┌────────┐
   │  auth  │ │streaming │ │ admin │ │  chat  │
   │ :3001  │ │  :3002   │ │ :3003 │ │ :3004  │
   └───┬────┘ └────┬─────┘ └───┬───┘ └───┬────┘
       │           │           │         │
       └───────────┴─────┬─────┴─────────┘
                          ▼
                    ┌──────────┐        ┌────────────┐
                    │  mongo   │        │  S3 (video │
                    │ :27017   │        │   assets)  │
                    └──────────┘        └────────────┘
```

| Service | Port | Purpose |
| --- | --- | --- |
| `authService` | 3001 | Registration, login, JWT issuance |
| `streamingService` | 3002 | Video catalogue, S3-backed playback, thumbnails |
| `adminService` | 3003 | Admin-only upload and video/asset management |
| `chatService` | 3004 | REST + Socket.IO real-time chat per video room |
| `frontend` | 3000 | React SPA — browse, player, chat, admin dashboard |
| `mongo` | 27017 | Shared MongoDB instance |

See **[CODE_STRUCTURE.md](./CODE_STRUCTURE.md)** for the full repo layout and
what each file/folder does.

## CI/CD Pipeline

```
git push → Jenkins (EC2) → docker build (5 services, parallel)
         → ECR login/tag/push → helm upgrade --install → EKS
         → CloudWatch metrics/logs → SNS → Slack (success/failure)
```

| Stage | Tool | Config |
| --- | --- | --- |
| Source control | Git / GitHub | this repo |
| CI orchestration | Jenkins on EC2 | [`Jenkinsfile`](./Jenkinsfile), bootstrapped via [`infra/jenkins-ec2-userdata.sh`](./infra/jenkins-ec2-userdata.sh) |
| Image registry | Amazon ECR | 5 repos under `streamingapp/*` |
| Container orchestration | Amazon EKS + Helm | chart at [`streamingapp/`](./streamingapp) |
| Monitoring | CloudWatch Container Insights | [`infra/monitoring-setup.md`](./infra/monitoring-setup.md) |
| ChatOps (bonus) | SNS + AWS Chatbot → Slack | [`infra/chatops-setup.md`](./infra/chatops-setup.md) |
| Command reference | — | [`helm.md`](./helm.md) |

## Environment Configuration

Each service reads its config from environment variables — see
[`.env.example`](./.env.example) for the full list (ports, Mongo URI, JWT
secret, AWS/S3 settings, frontend build-time API URLs). Copy it to `.env` and
fill in real values locally; the populated `.env` is gitignored and never
committed.

## Running Locally with Docker Compose

```bash
docker-compose up --build
```

Resulting images:

![docker images output showing all 5 built service images](./docs/screenshots/docker-images-list.png)

Navigate to `http://localhost:3000`:

![StreamingApp frontend running at localhost:3000](./docs/screenshots/frontend-live.png)

All six containers (`frontend`, `auth`, `streaming`, `admin`, `chat`, `mongo`)
running healthy:

![StreamingApp containers running in Docker Desktop](./docs/screenshots/docker-desktop-containers.png)

## Local Development (without Docker)

```bash
# install
cd backend/authService && npm install
cd ../streamingService && npm install
cd ../adminService && npm install
cd ../chatService && npm install
cd ../../frontend && npm install

# run (separate terminals, after starting MongoDB)
cd backend/authService && npm run dev
cd backend/streamingService && npm run dev
cd backend/adminService && npm run dev
cd backend/chatService && npm run dev
cd frontend && npm start
```

## Kubernetes Deployment (EKS + Helm)

The [`streamingapp/`](./streamingapp) Helm chart deploys all 5 services plus
MongoDB to an EKS cluster. Jenkins runs this automatically on every pipeline
run; to do it manually:

```bash
aws eks update-kubeconfig --region us-east-1 --name sneha-streaming-cluster
cd streamingapp
helm upgrade --install streamingapp . --namespace streamingapp --create-namespace
kubectl get pods -n streamingapp
```

![EKS nodes ready](./docs/screenshots/eks-nodes-ready.png)

![Pods running in the streamingapp namespace](./docs/screenshots/eks-pods-running.png)

## Feature Highlights

- **S3-backed adaptive streaming** with secure signed uploads for admins.
- **Dedicated admin microservice** for video ingestion, metadata management, and featured curation.
- **Real-time chat** overlay in the player (Socket.IO + persistent message history).
- **Modern React experience** featuring cinematic hero sections, dynamic carousels, and responsive design.
- **Role-aware access control** across frontend routes and backend microservices.
- **Fully automated CI/CD**: a `git push` builds, pushes, and redeploys all 5 services to EKS with no manual steps.

## Testing

Recommended smoke checks:

1. Register and log in through the web UI.
2. Upload a small video + thumbnail via the admin dashboard (requires valid S3 credentials).
3. Confirm playback from the browse page and verify that chat messages broadcast between multiple browser tabs.

## Submission Documentation

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** — step-by-step status of every capstone brief requirement, with evidence/screenshots called out per step.
- **[CODE_STRUCTURE.md](./CODE_STRUCTURE.md)** — repository layout and service responsibilities.
- **[helm.md](./helm.md)** — full command reference (build, push, Helm, kubectl access modes).

## License

MIT © StreamFlix Team
