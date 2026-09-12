---
title: Consumer
layout: default
parent: Setup
nav_order: 3
permalink: /setup/consumer/
description: >-
  Use the consumer profile: create the subscriber EC2, attach the interface
  VPC endpoint, and install measure tools (and optional sub.py).
---

<div class="conduit-hero">
  <p class="conduit-kicker">setup / 3 · consumer</p>
  <h1>Consumer</h1>
  <p class="conduit-lede">
    Work in the <strong>consumer</strong> account. The consumer VPC and
    <strong>private</strong> subnets already exist — create the subscriber EC2,
    attach the interface endpoint to the provider service, and install measure
    tools. Validate after each step (fictitious sample output below — replace
    IDs with yours). Measuring both paths is the next page.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/measure/">Next: Measure</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/setup/provider/">Back: Provider</a>
  </div>
</div>

## Which account

| | |
| --- | --- |
| Account role | Consumer spoke (subscriber host for Measure) |
| AWS CLI profile | `consumer` |
| Already exists | Consumer VPC, **private** subnets (workloads + interface ENIs) |
| What you create | Subscriber EC2 (+ SG), VPCE SG, interface VPC endpoint |
| From provider | `$SVC_NAME`, `$RELAY_PRIVATE_IP` |

Confirm you are in the right account, then set network IDs and provider outputs:

```bash
export AWS_PROFILE=consumer
export AWS_REGION=ap-southeast-6   # same Region as the provider

aws sts get-caller-identity

# Existing consumer spoke (example IDs — use yours)
export CONSUMER_VPC_ID=vpc-0c0c0c0c0c0c0c0c0

# private — subscriber EC2 (one AZ)
export CONSUMER_PRIVATE_SUBNET_ID=subnet-0ccc1111dddd2222

# private — interface endpoint ENIs (2+ AZs)
export CONSUMER_VPCE_SUBNET_IDS=subnet-0ccc1111dddd2222,subnet-0ccc3333eeee4444,subnet-0ccc5555ffff6666

# From Provider (fictitious — use yours)
export SVC_NAME=com.amazonaws.vpce.ap-southeast-6.vpce-svc-0aaaa1111bbbb2222
export RELAY_PRIVATE_IP=10.50.1.10
```

**Validate** — a **different** account ID than `shared-services` (fictitious):

```text
{
    "UserId": "AROAEXAMPLEID:you@example.com",
    "Account": "444455556666",
    "Arn": "arn:aws:sts::444455556666:assumed-role/AWSReservedSSO_AdministratorAccess_example/you@example.com"
}
```
{: .output }

{: .cost }
> Interface endpoint hours accrue per AZ while the VPCE exists. Subscriber EC2
> is billable too. Tag with <code>demo=pl-vs-inspected-tgw</code> so
> [Teardown]({{ site.baseurl }}/teardown/) is easy to find.

## Subscriber EC2

Still with `AWS_PROFILE=consumer`. Launch in a **private** subnet with SSM (no
public IP). NAT is only needed if the host must reach the public internet; the
measure step itself talks to PrivateLink ENIs and the provider private IP via
TGW.

### SSM interface endpoints

Same rule as provider: need `ssm` and `ssmmessages` **available** in this VPC.
`ec2messages` may not exist in the Region.

```bash
aws ec2 describe-vpc-endpoints \
  --profile consumer --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$CONSUMER_VPC_ID" \
  --query 'VpcEndpoints[?contains(ServiceName, `ssm`)].{ServiceName:ServiceName,State:State}' \
  --output table
```

**Validate**:

```text
---------------------------------------------------------------
|                   DescribeVpcEndpoints                      |
+------------------------------------------------+------------+
|  com.amazonaws.ap-southeast-6.ssm              |  available |
|  com.amazonaws.ap-southeast-6.ssmmessages      |  available |
+------------------------------------------------+------------+
```
{: .output }

If `ssm` is missing, create an interface endpoint tagged for this lab (reuse your
existing endpoint security group for HTTPS to AWS APIs; do not weaken it):

```bash
aws ec2 create-vpc-endpoint \
  --profile consumer --region "$AWS_REGION" \
  --vpc-id "$CONSUMER_VPC_ID" \
  --vpc-endpoint-type Interface \
  --service-name "com.amazonaws.${AWS_REGION}.ssm" \
  --subnet-ids $(echo "$CONSUMER_VPCE_SUBNET_IDS" | tr ',' ' ') \
  --security-group-ids "$EXISTING_ENDPOINT_SG_ID" \
  --private-dns-enabled \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-ssm}]'
```

Poll until `State=available` — do not rely on `aws ec2 wait vpc-endpoint-available`
(that waiter is not always present). Teardown removes only `Name=plvtgw-ssm`.

### Security groups

{% include diagram.html file="diagrams/consumer-sg.svg" alt="Consumer security groups for subscriber and interface endpoint TCP 9000" %}
<p class="diagram-caption">Dashed boundaries = security groups. Endpoint SG allows TCP 9000 from the subscriber SG only.</p>

Create two harness security groups: one for the subscriber instance, one for
the PrivateLink interface endpoint.

```bash
CONSUMER_INSTANCE_SG_ID=$(aws ec2 create-security-group \
  --profile consumer --region "$AWS_REGION" \
  --group-name plvtgw-subscriber \
  --description "pl-vs-inspected-tgw consumer subscriber EC2" \
  --vpc-id "$CONSUMER_VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-subscriber}]' \
  --query 'GroupId' --output text)

CONSUMER_ENDPOINT_SG_ID=$(aws ec2 create-security-group \
  --profile consumer --region "$AWS_REGION" \
  --group-name plvtgw-vpce \
  --description "pl-vs-inspected-tgw consumer interface endpoint :9000" \
  --vpc-id "$CONSUMER_VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-vpce}]' \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --profile consumer --region "$AWS_REGION" \
  --group-id "$CONSUMER_ENDPOINT_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=9000,ToPort=9000,UserIdGroupPairs=[{GroupId=${CONSUMER_INSTANCE_SG_ID},Description=from subscriber}]"

echo "CONSUMER_INSTANCE_SG_ID=$CONSUMER_INSTANCE_SG_ID"
echo "CONSUMER_ENDPOINT_SG_ID=$CONSUMER_ENDPOINT_SG_ID"
```

**Validate** — endpoint SG allows TCP 9000 from the subscriber SG only:

```bash
aws ec2 describe-security-groups \
  --profile consumer --region "$AWS_REGION" \
  --group-ids "$CONSUMER_ENDPOINT_SG_ID" \
  --query 'SecurityGroups[0].{GroupId:GroupId,GroupName:GroupName,Ingress:IpPermissions}' \
  --output json
```

```text
{
    "GroupId": "sg-0eeee3333ffff4444",
    "GroupName": "plvtgw-vpce",
    "Ingress": [
        {
            "IpProtocol": "tcp",
            "FromPort": 9000,
            "ToPort": 9000,
            "UserIdGroupPairs": [
                {
                    "Description": "from subscriber",
                    "GroupId": "sg-0cccc1111dddd2222"
                }
            ]
        }
    ]
}
```
{: .output }

### IAM instance profile (SSM)

{% include diagram.html file="diagrams/consumer-iam.svg" alt="IAM role and instance profile for SSM on the subscriber EC2" %}
<p class="diagram-caption">Role + <code>AmazonSSMManagedInstanceCore</code> → instance profile attached at launch.</p>

Same pattern as provider — create once in the consumer account if missing:

```bash
aws iam create-role \
  --profile consumer \
  --role-name plvtgw-ec2-ssm \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ec2.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --profile consumer \
  --role-name plvtgw-ec2-ssm \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
  --profile consumer \
  --instance-profile-name plvtgw-ec2-ssm

aws iam add-role-to-instance-profile \
  --profile consumer \
  --instance-profile-name plvtgw-ec2-ssm \
  --role-name plvtgw-ec2-ssm

aws iam tag-role \
  --profile consumer \
  --role-name plvtgw-ec2-ssm \
  --tags Key=demo,Value=pl-vs-inspected-tgw

sleep 15
```

**Validate**:

```bash
aws iam get-instance-profile \
  --profile consumer \
  --instance-profile-name plvtgw-ec2-ssm \
  --query 'InstanceProfile.{Name:InstanceProfileName,Roles:Roles[0].RoleName}' \
  --output json
```

```text
{
    "Name": "plvtgw-ec2-ssm",
    "Roles": "plvtgw-ec2-ssm"
}
```
{: .output }

### Launch the instance

{% include diagram.html file="diagrams/consumer-launch.svg" alt="Launch subscriber EC2 in private subnet with SSM" %}
<p class="diagram-caption">EC2 in <strong>private</strong>; SSM for access — no public IP. Measure traffic stays private (VPCE / TGW).</p>

```bash
AMI_ID=$(aws ssm get-parameters \
  --profile consumer --region "$AWS_REGION" \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)

CONSUMER_INSTANCE_ID=$(aws ec2 run-instances \
  --profile consumer --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --subnet-id "$CONSUMER_PRIVATE_SUBNET_ID" \
  --security-group-ids "$CONSUMER_INSTANCE_SG_ID" \
  --iam-instance-profile Name=plvtgw-ec2-ssm \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=plvtgw-subscriber},{Key=demo,Value=pl-vs-inspected-tgw}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running \
  --profile consumer --region "$AWS_REGION" \
  --instance-ids "$CONSUMER_INSTANCE_ID"

echo "CONSUMER_INSTANCE_ID=$CONSUMER_INSTANCE_ID"
```

**Validate** — instance running, then SSM `Online`:

```bash
aws ec2 describe-instances \
  --profile consumer --region "$AWS_REGION" \
  --instance-ids "$CONSUMER_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PrivateIp:PrivateIpAddress}' \
  --output json

aws ssm describe-instance-information \
  --profile consumer --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$CONSUMER_INSTANCE_ID" \
  --query 'InstanceInformationList[0].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName}' \
  --output json
```

```text
{
    "InstanceId": "i-0cccc1111dddd2222",
    "State": "running",
    "PrivateIp": "10.60.3.20"
}
{
    "InstanceId": "i-0cccc1111dddd2222",
    "PingStatus": "Online",
    "PlatformName": "Amazon Linux"
}
```
{: .output }

```bash
aws ssm start-session \
  --profile consumer --region "$AWS_REGION" \
  --target "$CONSUMER_INSTANCE_ID"
```

## Interface endpoint

Requires `$SVC_NAME` from [Provider]({{ site.baseurl }}/setup/provider/).

{% include diagram.html file="diagrams/consumer-vpce.svg" alt="Interface VPC endpoint from consumer to provider PrivateLink service" %}
<p class="diagram-caption">Subscriber → local interface ENI (:9000) → PrivateLink → provider NLB / endpoint service.</p>

### Create the interface endpoint

```bash
EP_ID=$(aws ec2 create-vpc-endpoint \
  --profile consumer --region "$AWS_REGION" \
  --vpc-endpoint-type Interface \
  --service-name "$SVC_NAME" \
  --vpc-id "$CONSUMER_VPC_ID" \
  --subnet-ids $(echo "$CONSUMER_VPCE_SUBNET_IDS" | tr ',' ' ') \
  --security-group-ids "$CONSUMER_ENDPOINT_SG_ID" \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-pl}]' \
  --query 'VpcEndpoint.VpcEndpointId' --output text)

echo "EP_ID=$EP_ID"
```

### Wait until available

Poll (do not use the missing `vpc-endpoint-available` waiter):

```bash
for i in $(seq 1 48); do
  st=$(aws ec2 describe-vpc-endpoints \
    --profile consumer --region "$AWS_REGION" \
    --vpc-endpoint-ids "$EP_ID" \
    --query 'VpcEndpoints[0].State' --output text)
  echo "State=$st"
  [[ "$st" == available ]] && break
  sleep 5
done
```

**Validate**:

```text
State=pending
…
State=available
```
{: .output }

### Get the PrivateLink DNS name

```bash
PL_DNS=$(aws ec2 describe-vpc-endpoints \
  --profile consumer --region "$AWS_REGION" \
  --vpc-endpoint-ids "$EP_ID" \
  --query 'VpcEndpoints[0].DnsEntries[0].DnsName' --output text)

echo "PL_DNS=$PL_DNS"
```

**Validate** (fictitious hostname):

```text
PL_DNS=vpce-0eeee3333ffff4444-abcd1234.vpce-svc-0aaaa1111bbbb2222.ap-southeast-6.vpce.amazonaws.com
```
{: .output }

## Measure tools on the consumer host

Install on the instance (SSM session) — needed for [Measure]({{ site.baseurl }}/measure/):

```bash
sudo dnf install -y tmux nmap-ncat nmap pv
command -v nc tmux pv nping
```
{: .on-host }

**Validate**:

```text
/usr/bin/nc
/usr/bin/tmux
/usr/bin/pv
/usr/bin/nping
```
{: .output }

## Optional: `sub.py`

Only if you want a Comparison one-liner later. Interactive Measure does not need it.

Copy from the laptop (same base64 paste pattern as Provider `relay.py`), or:

```bash
# laptop
base64 -w0 scripts/sub.py
```

```bash
# on the instance
sudo mkdir -p /opt/plvtgw
printf '%s' '…paste sub.py b64…' | base64 -d | sudo tee /opt/plvtgw/sub.py >/dev/null
sudo chmod 755 /opt/plvtgw/sub.py
```
{: .on-host }

**Validate**:

```bash
ls -l /opt/plvtgw/sub.py
python3 -m py_compile /opt/plvtgw/sub.py && echo ok
```
{: .on-host }

```text
-rwxr-xr-x. 1 root root … /opt/plvtgw/sub.py
ok
```
{: .output }

Keep `$EP_ID`, `$PL_DNS`, `$CONSUMER_INSTANCE_ID`, `$RELAY_PRIVATE_IP`, and the
two SGs for [Measure]({{ site.baseurl }}/measure/) and
[Teardown]({{ site.baseurl }}/teardown/).

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/measure/">
    <strong>Measure</strong>
    <span>PrivateLink and TGW (interactive)</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/setup/provider/">
    <strong>Provider</strong>
    <span>Relay · NLB · endpoint service</span>
  </a>
</div>
