#!/bin/bash
# EC2 user-data script: bootstraps Jenkins + Docker + AWS CLI + kubectl + helm
# on a fresh Amazon Linux 2023 instance.
#
# Usage once you have EC2 access:
#   aws ec2 run-instances \
#     --image-id <amazon-linux-2023-ami-id> \
#     --instance-type t3.medium \
#     --key-name <your-key-pair> \
#     --security-group-ids <sg-allowing-22-and-8080> \
#     --user-data file://infra/jenkins-ec2-userdata.sh \
#     --region us-east-1
set -euxo pipefail

# --- Java (required by Jenkins) ---
dnf install -y java-17-amazon-corretto

# --- Jenkins ---
curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.repo -o /etc/yum.repos.d/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins
systemctl enable jenkins
systemctl start jenkins

# --- Docker (Jenkins agents build/push images) ---
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins

# --- AWS CLI v2 ---
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# --- kubectl ---
curl -fsSL -o /usr/local/bin/kubectl "https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# --- Helm ---
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

systemctl restart jenkins

echo "Jenkins initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword || echo "(not ready yet, check again in a minute: sudo cat /var/lib/jenkins/secrets/initialAdminPassword)"
