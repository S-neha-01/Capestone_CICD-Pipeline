# Step 6 — Monitoring and Logging (CloudWatch)

Run once EC2/EKS access is available. Region: `us-east-1`.

## 1) Container logs → CloudWatch Logs

EKS pods already write to stdout/stderr, which the EKS-managed Fargate/EC2 nodes
forward to CloudWatch automatically if the cluster has the CloudWatch Container
Insights add-on enabled:

```bash
aws eks update-kubeconfig --region us-east-1 --name sneha-streaming-cluster

# enable Container Insights (creates log groups per namespace/pod automatically)
curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml \
  | sed "s/{{cluster_name}}/sneha-streaming-cluster/;s/{{region_name}}/us-east-1/" \
  | kubectl apply -f -
```

Log groups will appear under `/aws/containerinsights/sneha-streaming-cluster/...`
in the CloudWatch console.

## 2) Metrics + alarms

```bash
# CPU/memory alarms per deployment, once Container Insights is running
aws cloudwatch put-metric-alarm \
  --alarm-name sneha-streaming-high-cpu \
  --namespace ContainerInsights \
  --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value=sneha-streaming-cluster \
  --statistic Average --period 300 --threshold 80 \
  --comparison-operator GreaterThanThreshold --evaluation-periods 2 \
  --region us-east-1
```

## 3) What to screenshot for submission

- CloudWatch Container Insights dashboard showing live pod/node metrics
- Log groups listing under `/aws/containerinsights/...` with recent log streams
- The alarm in "OK" or "ALARM" state in the CloudWatch console
