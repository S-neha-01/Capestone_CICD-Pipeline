# Step 9 (Bonus) — ChatOps via SNS + Slack

Run once AWS access is available. Region: `us-west-1`.

## 1) Create SNS topics

```bash
aws sns create-topic --name sneha-deploy-success --region us-west-1
aws sns create-topic --name sneha-deploy-failure --region us-west-1
```

Note the returned `TopicArn` for each — used below and in the Jenkinsfile `post` block.

## 2) Subscribe Slack (via AWS Chatbot)

1. AWS console → **Chatbot** → *Configure new client* → Slack → authorize your workspace.
2. Create a channel configuration, attach the two SNS topic ARNs from step 1.
3. Slack will post automatically whenever either topic receives a message —
   no webhook/token to store in Jenkins.

## 3) Wire into the Jenkinsfile

Add to the existing `post` block:

```groovy
post {
    success {
        sh """
        aws sns publish --region us-west-1 \\
          --topic-arn <sneha-deploy-success-arn> \\
          --message 'StreamingApp build #${BUILD_NUMBER} deployed successfully to EKS'
        """
    }
    failure {
        sh """
        aws sns publish --region us-west-1 \\
          --topic-arn <sneha-deploy-failure-arn> \\
          --message 'StreamingApp build #${BUILD_NUMBER} failed — check Jenkins console'
        """
    }
}
```

## 4) What to screenshot for submission

- The two SNS topics in the console
- The AWS Chatbot Slack channel configuration
- A Slack message actually landing in the channel after a pipeline run
