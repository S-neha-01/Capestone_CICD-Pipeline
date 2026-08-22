pipeline {
    agent any

    environment {
        AWS_REGION = "us-east-1"
        ACCOUNT_ID = "378436334075"
        ECR_BASE = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/streamingapp"
        IMAGE_TAG = "${BUILD_NUMBER}"
        EKS_CLUSTER = "sneha-streaming-cluster"
        K8S_NAMESPACE = "streamingapp"
        HELM_RELEASE = "streamingapp"
    }

    stages {

        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Build Images') {
            parallel {

                stage('Build Frontend') {
                    steps {
                        sh 'docker build -t frontend:latest -t frontend:${IMAGE_TAG} frontend'
                    }
                }

                stage('Build AuthService') {
                    steps {
                        sh 'docker build -t authservice:latest -t authservice:${IMAGE_TAG} backend/authService'
                    }
                }

                stage('Build StreamingService') {
                    steps {
                        sh 'docker build -f backend/streamingService/Dockerfile -t streamingservice:latest -t streamingservice:${IMAGE_TAG} backend'
                    }
                }

                stage('Build AdminService') {
                    steps {
                        sh 'docker build -f backend/adminService/Dockerfile -t adminservice:latest -t adminservice:${IMAGE_TAG} backend'
                    }
                }

                stage('Build ChatService') {
                    steps {
                        sh 'docker build -f backend/chatService/Dockerfile -t chatservice:latest -t chatservice:${IMAGE_TAG} backend'
                    }
                }
            }
        }

        stage('Login to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'sneha-ecr-cred'
                ]]) {
                    sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                    """
                }
            }
        }

        stage('Tag Images') {
            steps {
                sh """
                docker tag frontend:latest ${ECR_BASE}/frontend:latest
                docker tag frontend:${IMAGE_TAG} ${ECR_BASE}/frontend:${IMAGE_TAG}
                docker tag authservice:latest ${ECR_BASE}/authservice:latest
                docker tag authservice:${IMAGE_TAG} ${ECR_BASE}/authservice:${IMAGE_TAG}
                docker tag streamingservice:latest ${ECR_BASE}/streamingservice:latest
                docker tag streamingservice:${IMAGE_TAG} ${ECR_BASE}/streamingservice:${IMAGE_TAG}
                docker tag adminservice:latest ${ECR_BASE}/adminservice:latest
                docker tag adminservice:${IMAGE_TAG} ${ECR_BASE}/adminservice:${IMAGE_TAG}
                docker tag chatservice:latest ${ECR_BASE}/chatservice:latest
                docker tag chatservice:${IMAGE_TAG} ${ECR_BASE}/chatservice:${IMAGE_TAG}
                """
            }
        }

        stage('Push Images') {
            steps {
                sh """
                docker push ${ECR_BASE}/frontend:latest
                docker push ${ECR_BASE}/frontend:${IMAGE_TAG}
                docker push ${ECR_BASE}/authservice:latest
                docker push ${ECR_BASE}/authservice:${IMAGE_TAG}
                docker push ${ECR_BASE}/streamingservice:latest
                docker push ${ECR_BASE}/streamingservice:${IMAGE_TAG}
                docker push ${ECR_BASE}/adminservice:latest
                docker push ${ECR_BASE}/adminservice:${IMAGE_TAG}
                docker push ${ECR_BASE}/chatservice:latest
                docker push ${ECR_BASE}/chatservice:${IMAGE_TAG}
                """
            }
        }

        stage('Bootstrap Helm (No SSH Needed)') {
            steps {
                sh """
                set -e
                if command -v helm >/dev/null 2>&1; then
                  echo "Helm already available on agent: \$(helm version --short)"
                  exit 0
                fi

                mkdir -p "\$WORKSPACE/.ci-bin"
                HELM_VERSION="v3.20.0"
                ARCHIVE="helm-\${HELM_VERSION}-linux-amd64.tar.gz"
                curl -fsSL "https://get.helm.sh/\${ARCHIVE}" -o "\$WORKSPACE/\${ARCHIVE}"
                tar -xzf "\$WORKSPACE/\${ARCHIVE}" -C "\$WORKSPACE"
                mv "\$WORKSPACE/linux-amd64/helm" "\$WORKSPACE/.ci-bin/helm"
                chmod +x "\$WORKSPACE/.ci-bin/helm"
                rm -rf "\$WORKSPACE/linux-amd64" "\$WORKSPACE/\${ARCHIVE}"

                "\$WORKSPACE/.ci-bin/helm" version --short
                """
            }
        }

        stage('Validate Deployment Tools') {
            steps {
                sh """
                set -e
                command -v aws >/dev/null 2>&1 || { echo "Missing required tool: aws"; exit 1; }
                command -v kubectl >/dev/null 2>&1 || { echo "Missing required tool: kubectl"; exit 1; }
                if ! command -v helm >/dev/null 2>&1 && [ ! -x "\$WORKSPACE/.ci-bin/helm" ]; then
                  echo "Missing required tool: helm"
                  exit 1
                fi

                aws --version
                kubectl version --client
                if command -v helm >/dev/null 2>&1; then
                  helm version
                else
                  "\$WORKSPACE/.ci-bin/helm" version
                fi
                """
            }
        }

        stage('Deploy to EKS') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'sneha-ecr-cred'
                ]]) {
                    sh """
                    set -e
                    aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER}

                    HELM_CMD=helm
                    if ! command -v helm >/dev/null 2>&1; then
                      HELM_CMD="\$WORKSPACE/.ci-bin/helm"
                    fi

                    "\$HELM_CMD" upgrade --install ${HELM_RELEASE} ./streamingapp \
                      --namespace ${K8S_NAMESPACE} \
                      --create-namespace \
                      --set frontend.image=${ECR_BASE}/frontend:${IMAGE_TAG} \
                      --set authService.image=${ECR_BASE}/authservice:${IMAGE_TAG} \
                      --set streamingService.image=${ECR_BASE}/streamingservice:${IMAGE_TAG} \
                      --set adminService.image=${ECR_BASE}/adminservice:${IMAGE_TAG} \
                      --set chatService.image=${ECR_BASE}/chatservice:${IMAGE_TAG}

                    kubectl get deployments -n ${K8S_NAMESPACE} -l app.kubernetes.io/instance=${HELM_RELEASE} -o name | while read deploy; do
                      kubectl rollout status -n ${K8S_NAMESPACE} "\$deploy" --timeout=300s
                    done
                    """
                }
            }
        }
    }

    post {
        success {
            echo "All microservices built, pushed, and deployed to EKS successfully!"
        }
        failure {
            echo "Pipeline failed during build, push, or EKS deployment."
        }
    }
}
