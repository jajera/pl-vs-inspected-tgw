---
title: Teardown
layout: default
nav_order: 7
permalink: /teardown/
description: >-
  Delete the harness PrivateLink resources, EC2 hosts, and IAM. Leave the shared
  hub alone.
---

<div class="conduit-hero">
  <p class="conduit-kicker">after measure</p>
  <h1>Teardown</h1>
  <p class="conduit-lede">
    Remove only what the harness created. Consumer first, then provider. Do not
    touch TGW, inspection VPC, or Network Firewall policy.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/comparison/">Back to Comparison</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/references/">References</a>
  </div>
</div>

{: .warning }
> Stop here if you still need the lab. This deletes the stream path permanently.

## Order

| Step | Account | Delete |
| --- | --- | --- |
| 1 | **consumer** | Interface endpoint → subscriber EC2 → SGs → IAM (and lab-only SSM VPCE if you created one) |
| 2 | **shared-services** | Endpoint service → NLB → target group → relay EC2 → SG → IAM (and lab-only SSM VPCE if you created one) |

Discover by tag if you lost IDs:

```bash
export AWS_REGION=ap-southeast-6

aws resourcegroupstaggingapi get-resources \
  --profile consumer --region "$AWS_REGION" \
  --tag-filters Key=demo,Values=pl-vs-inspected-tgw \
  --query 'ResourceTagMappingList[].ResourceARN' --output table

aws resourcegroupstaggingapi get-resources \
  --profile shared-services --region "$AWS_REGION" \
  --tag-filters Key=demo,Values=pl-vs-inspected-tgw \
  --query 'ResourceTagMappingList[].ResourceARN' --output table
```

---

## 1. Consumer

```bash
export AWS_PROFILE=consumer
export AWS_REGION=ap-southeast-6

aws sts get-caller-identity
```

### Interface endpoint

```bash
# Example — use your EP_ID from Consumer setup
export EP_ID=vpce-0eeee3333ffff4444

aws ec2 delete-vpc-endpoints \
  --profile consumer --region "$AWS_REGION" \
  --vpc-endpoint-ids "$EP_ID"
```

**Validate**

```bash
aws ec2 describe-vpc-endpoints \
  --profile consumer --region "$AWS_REGION" \
  --vpc-endpoint-ids "$EP_ID" \
  --query 'VpcEndpoints[0].State' --output text
```

```text
deleting
```
{: .output }

### Subscriber EC2

```bash
export CONSUMER_INSTANCE_ID=i-0cccc1111dddd2222

aws ec2 terminate-instances \
  --profile consumer --region "$AWS_REGION" \
  --instance-ids "$CONSUMER_INSTANCE_ID"

aws ec2 wait instance-terminated \
  --profile consumer --region "$AWS_REGION" \
  --instance-ids "$CONSUMER_INSTANCE_ID"
```

### Security groups

Wait until ENIs from the endpoint and instance are gone, then:

```bash
export CONSUMER_ENDPOINT_SG_ID=sg-0eeee3333ffff4444
export CONSUMER_INSTANCE_SG_ID=sg-0cccc1111dddd2222

aws ec2 delete-security-group \
  --profile consumer --region "$AWS_REGION" \
  --group-id "$CONSUMER_ENDPOINT_SG_ID"

aws ec2 delete-security-group \
  --profile consumer --region "$AWS_REGION" \
  --group-id "$CONSUMER_INSTANCE_SG_ID"
```

If delete fails with “DependencyViolation”, wait ~30 s and retry.

### IAM instance profile

```bash
aws iam remove-role-from-instance-profile \
  --profile consumer \
  --instance-profile-name plvtgw-ec2-ssm \
  --role-name plvtgw-ec2-ssm

aws iam delete-instance-profile \
  --profile consumer \
  --instance-profile-name plvtgw-ec2-ssm

aws iam detach-role-policy \
  --profile consumer \
  --role-name plvtgw-ec2-ssm \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam delete-role \
  --profile consumer \
  --role-name plvtgw-ec2-ssm
```

Skip IAM deletes if the role is shared with other workloads.

### Lab-only SSM endpoint (optional)

Only if you created a tagged `plvtgw-ssm` interface endpoint during Consumer prep:

```bash
aws ec2 describe-vpc-endpoints \
  --profile consumer --region "$AWS_REGION" \
  --filters Name=tag:Name,Values=plvtgw-ssm \
  --query 'VpcEndpoints[].VpcEndpointId' --output text

# then:
# aws ec2 delete-vpc-endpoints --profile consumer --region "$AWS_REGION" --vpc-endpoint-ids vpce-…
```

Do **not** delete pre-existing spoke SSM endpoints you did not create for this lab.

---

## 2. Provider (`shared-services`)

```bash
export AWS_PROFILE=shared-services
export AWS_REGION=ap-southeast-6

aws sts get-caller-identity
```

### Endpoint service

```bash
export SVC_ID=vpce-svc-0aaaa1111bbbb2222

aws ec2 delete-vpc-endpoint-service-configurations \
  --profile shared-services --region "$AWS_REGION" \
  --service-ids "$SVC_ID"
```

### NLB, listener, target group

```bash
export NLB_ARN=arn:aws:elasticloadbalancing:ap-southeast-6:111122223333:loadbalancer/net/plvtgw-nlb/0123456789abcdef
export TG_ARN=arn:aws:elasticloadbalancing:ap-southeast-6:111122223333:targetgroup/plvtgw-tg/fedcba9876543210

# Listener (if still present)
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --profile shared-services --region "$AWS_REGION" \
  --load-balancer-arn "$NLB_ARN" \
  --query 'Listeners[0].ListenerArn' --output text)
aws elbv2 delete-listener \
  --profile shared-services --region "$AWS_REGION" \
  --listener-arn "$LISTENER_ARN"

aws elbv2 delete-load-balancer \
  --profile shared-services --region "$AWS_REGION" \
  --load-balancer-arn "$NLB_ARN"

# Wait until describe fails
until ! aws elbv2 describe-load-balancers \
  --profile shared-services --region "$AWS_REGION" \
  --load-balancer-arns "$NLB_ARN" &>/dev/null; do
  sleep 5
done

aws elbv2 delete-target-group \
  --profile shared-services --region "$AWS_REGION" \
  --target-group-arn "$TG_ARN"
```

### Relay EC2

```bash
export PROVIDER_INSTANCE_ID=i-0aaaa1111bbbb2222

aws ec2 terminate-instances \
  --profile shared-services --region "$AWS_REGION" \
  --instance-ids "$PROVIDER_INSTANCE_ID"

aws ec2 wait instance-terminated \
  --profile shared-services --region "$AWS_REGION" \
  --instance-ids "$PROVIDER_INSTANCE_ID"
```

Host files under `/opt/plvtgw` and `plvtgw-relay.service` disappear with the instance.

### Security group + IAM

```bash
export PROVIDER_SG_ID=sg-0relay1111cccc2222

aws ec2 delete-security-group \
  --profile shared-services --region "$AWS_REGION" \
  --group-id "$PROVIDER_SG_ID"

aws iam remove-role-from-instance-profile \
  --profile shared-services \
  --instance-profile-name plvtgw-ec2-ssm \
  --role-name plvtgw-ec2-ssm

aws iam delete-instance-profile \
  --profile shared-services \
  --instance-profile-name plvtgw-ec2-ssm

aws iam detach-role-policy \
  --profile shared-services \
  --role-name plvtgw-ec2-ssm \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam delete-role \
  --profile shared-services \
  --role-name plvtgw-ec2-ssm
```

### Lab-only SSM endpoint (optional)

Same rule as consumer — only delete a `plvtgw-ssm` endpoint you created for this lab.

---

## Leave alone

| Resource | Why |
| --- | --- |
| Transit Gateway, attachments, spoke routes | Hub prerequisite |
| Inspection VPC / Network Firewall policy | Hub prerequisite |
| Pre-existing SSM / other interface endpoints | Not harness-owned |
| Spoke VPCs and subnets | Already existed |

If you temporarily opened hub firewall for consumer → provider `:9000` outside this repo, reverse that in the **network** account. That change is not part of the harness tag.

---

## Confirm clean

```bash
aws resourcegroupstaggingapi get-resources \
  --profile consumer --region "$AWS_REGION" \
  --tag-filters Key=demo,Values=pl-vs-inspected-tgw \
  --query 'ResourceTagMappingList' --output table

aws resourcegroupstaggingapi get-resources \
  --profile shared-services --region "$AWS_REGION" \
  --tag-filters Key=demo,Values=pl-vs-inspected-tgw \
  --query 'ResourceTagMappingList' --output table
```

Empty tables (or only lingering ARNs in `deleting`) means teardown is done.

Laptop helper (needs `scripts/.state` from setup): `./scripts/teardown.sh`.

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/comparison/">
    <strong>Comparison</strong>
    <span>Latency, cost, when each path wins</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/references/">
    <strong>References</strong>
    <span>Related labs and AWS docs</span>
  </a>
</div>
