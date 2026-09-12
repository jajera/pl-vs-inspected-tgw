---
title: Provider
layout: default
parent: Setup
nav_order: 2
permalink: /setup/provider/
description: >-
  Use the shared-services profile: create the relay EC2 in the existing VPC,
  run relay.py, then create the NLB and VPC endpoint service.
---

<div class="conduit-hero">
  <p class="conduit-kicker">setup / 2 · shared-services</p>
  <h1>Provider</h1>
  <p class="conduit-lede">
    Work in the <strong>shared-services</strong> account. The provider VPC,
    <strong>private</strong> subnets, and <strong>private-lb</strong> subnets
    already exist — create the relay EC2, start <code>relay.py</code>, then the
    NLB and endpoint service. Validate after each step (fictitious sample output
    below — replace IDs with yours).
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/setup/consumer/">Next: Consumer</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/setup/prep/">Back: Prep</a>
  </div>
</div>

## Which account

| | |
| --- | --- |
| Account role | Provider spoke (hosts the relay) |
| AWS CLI profile | `shared-services` |
| Already exists | Provider VPC, **private** subnets (workloads), **private-lb** subnets (NLB) |
| What you create | Relay EC2 (+ SG), NLB, target group, listener, endpoint service |

Confirm you are in the right account, then set the existing network IDs
(fictitious examples throughout this walkthrough — substitute yours):

```bash
export AWS_PROFILE=shared-services
export AWS_REGION=ap-southeast-6   # your Region

aws sts get-caller-identity

# Existing provider spoke (example IDs — use yours)
export PROVIDER_VPC_ID=vpc-0a1b2c3d4e5f67890

# private — workload subnets (relay EC2). Pick one AZ.
export PROVIDER_PRIVATE_SUBNET_ID=subnet-0aaa1111bbbb2222

# private-lb — load balancer subnets (internal NLB needs 2+ AZs)
export PROVIDER_LB_SUBNET_IDS=subnet-0lb1aaaa1111bbbb,subnet-0lb2cccc2222dddd,subnet-0lb3eeee3333ffff
```

**Validate** — account ID and role look right (fictitious):

```text
{
    "UserId": "AROAEXAMPLEID:you@example.com",
    "Account": "111122223333",
    "Arn": "arn:aws:sts::111122223333:assumed-role/AWSReservedSSO_AdministratorAccess_example/you@example.com"
}
```
{: .output }

{: .cost }
> EC2, NLB, and later endpoint hours are billable. Tag with
> <code>demo=pl-vs-inspected-tgw</code> so [Teardown]({{ site.baseurl }}/teardown/)
> is easy to find.

## Relay EC2

Still with `AWS_PROFILE=shared-services`. Launch in a **private** subnet with
SSM (no public IP). The spoke must provide NAT — the relay uses **live**
Wikimedia ingest only (no offline replay).

### SSM interface endpoints

Private Session Manager needs VPC interface endpoints for `ssm` and
`ssmmessages`. Some Regions also offer `ec2messages`; others (including
`ap-southeast-6`) do not — create what exists:

```bash
aws ec2 describe-vpc-endpoint-services \
  --profile shared-services --region "$AWS_REGION" \
  --query "ServiceNames[?contains(@, 'ssm') || contains(@, 'ec2messages')]" \
  --output text
```

**Validate** — in `ap-southeast-6` only `ssm` and `ssmmessages` appear (no
`ec2messages`). Confirm your VPC has those endpoints **available**:

```bash
aws ec2 describe-vpc-endpoints \
  --profile shared-services --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$PROVIDER_VPC_ID" \
  --query 'VpcEndpoints[?contains(ServiceName, `ssm`)].{ServiceName:ServiceName,State:State}' \
  --output table
```

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
existing endpoint security group; do not weaken it):

```bash
# Example — use your private subnets (2+ AZs) and existing endpoint SG
aws ec2 create-vpc-endpoint \
  --profile shared-services --region "$AWS_REGION" \
  --vpc-id "$PROVIDER_VPC_ID" \
  --vpc-endpoint-type Interface \
  --service-name "com.amazonaws.${AWS_REGION}.ssm" \
  --subnet-ids "$PROVIDER_PRIVATE_SUBNET_ID" \
  --security-group-ids "$EXISTING_ENDPOINT_SG_ID" \
  --private-dns-enabled \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-ssm}]'
```

Wait until `State=available` before launching the instance. Teardown removes
only endpoints tagged `Name=plvtgw-ssm`.

### Security group

{% include diagram.html file="diagrams/provider-sg.svg" alt="Provider security group for relay TCP 9000" %}
<p class="diagram-caption">Dashed boundary = security group. Ingress TCP 9000 from provider VPC CIDR (NLB) <strong>and</strong> consumer spoke CIDR (TGW path).</p>

```bash
PROVIDER_SG_ID=$(aws ec2 create-security-group \
  --profile shared-services --region "$AWS_REGION" \
  --group-name plvtgw-relay \
  --description "pl-vs-inspected-tgw relay TCP 9000" \
  --vpc-id "$PROVIDER_VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-relay}]' \
  --query 'GroupId' --output text)

PROVIDER_VPC_CIDR=$(aws ec2 describe-vpcs \
  --profile shared-services --region "$AWS_REGION" \
  --vpc-ids "$PROVIDER_VPC_ID" \
  --query 'Vpcs[0].CidrBlock' --output text)

# Consumer spoke CIDR — required for the TGW path (source is the subscriber IP).
# Example only; use your real consumer VPC CIDR.
export CONSUMER_VPC_CIDR=10.60.0.0/20

aws ec2 authorize-security-group-ingress \
  --profile shared-services --region "$AWS_REGION" \
  --group-id "$PROVIDER_SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=9000,ToPort=9000,IpRanges=[{CidrIp=${PROVIDER_VPC_CIDR},Description=NLB and provider VPC}]" \
    "IpProtocol=tcp,FromPort=9000,ToPort=9000,IpRanges=[{CidrIp=${CONSUMER_VPC_CIDR},Description=TGW path from consumer}]"

echo "PROVIDER_SG_ID=$PROVIDER_SG_ID"
echo "PROVIDER_VPC_CIDR=$PROVIDER_VPC_CIDR"
echo "CONSUMER_VPC_CIDR=$CONSUMER_VPC_CIDR"
```

PrivateLink (NLB → relay) needs the provider VPC CIDR. The TGW path needs the
**consumer** CIDR too — hub firewall PASS alone does not open this SG.

**Validate**:

```bash
aws ec2 describe-security-groups \
  --profile shared-services --region "$AWS_REGION" \
  --group-ids "$PROVIDER_SG_ID" \
  --query 'SecurityGroups[0].{GroupId:GroupId,GroupName:GroupName,Ingress:IpPermissions}' \
  --output json
```

```text
{
    "GroupId": "sg-0aaaa1111bbbb2222",
    "GroupName": "plvtgw-relay",
    "Ingress": [
        {
            "IpProtocol": "tcp",
            "FromPort": 9000,
            "ToPort": 9000,
            "IpRanges": [
                {
                    "Description": "NLB and provider VPC",
                    "CidrIp": "10.50.0.0/20"
                },
                {
                    "Description": "TGW path from consumer",
                    "CidrIp": "10.60.0.0/20"
                }
            ]
        }
    ]
}
```
{: .output }

### IAM instance profile (SSM)

{% include diagram.html file="diagrams/provider-iam.svg" alt="IAM role and instance profile for SSM on the relay EC2" %}
<p class="diagram-caption">Role + <code>AmazonSSMManagedInstanceCore</code> → instance profile attached at launch.</p>

Create once if you do not already have a profile with `AmazonSSMManagedInstanceCore`:

```bash
aws iam create-role \
  --profile shared-services \
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
  --profile shared-services \
  --role-name plvtgw-ec2-ssm \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
  --profile shared-services \
  --instance-profile-name plvtgw-ec2-ssm

aws iam add-role-to-instance-profile \
  --profile shared-services \
  --instance-profile-name plvtgw-ec2-ssm \
  --role-name plvtgw-ec2-ssm

aws iam tag-role \
  --profile shared-services \
  --role-name plvtgw-ec2-ssm \
  --tags Key=demo,Value=pl-vs-inspected-tgw

# IAM is eventually consistent
sleep 15
```

**Validate**:

```bash
aws iam get-instance-profile \
  --profile shared-services \
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

{% include diagram.html file="diagrams/provider-launch.svg" alt="Launch relay EC2 in private subnet with NAT and SSM" %}
<p class="diagram-caption">EC2 in <strong>private</strong>; NAT (exists) for live Wikimedia; SSM for access — no public IP.</p>

```bash
AMI_ID=$(aws ssm get-parameters \
  --profile shared-services --region "$AWS_REGION" \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)

PROVIDER_INSTANCE_ID=$(aws ec2 run-instances \
  --profile shared-services --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --subnet-id "$PROVIDER_PRIVATE_SUBNET_ID" \
  --security-group-ids "$PROVIDER_SG_ID" \
  --iam-instance-profile Name=plvtgw-ec2-ssm \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=plvtgw-relay},{Key=demo,Value=pl-vs-inspected-tgw}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running \
  --profile shared-services --region "$AWS_REGION" \
  --instance-ids "$PROVIDER_INSTANCE_ID"

RELAY_PRIVATE_IP=$(aws ec2 describe-instances \
  --profile shared-services --region "$AWS_REGION" \
  --instance-ids "$PROVIDER_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "PROVIDER_INSTANCE_ID=$PROVIDER_INSTANCE_ID"
echo "RELAY_PRIVATE_IP=$RELAY_PRIVATE_IP"
```

**Validate** — instance `running`:

```bash
aws ec2 describe-instances \
  --profile shared-services --region "$AWS_REGION" \
  --instance-ids "$PROVIDER_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PrivateIp:PrivateIpAddress}' \
  --output json
```

```text
{
    "InstanceId": "i-0aaaa1111bbbb2222",
    "State": "running",
    "PrivateIp": "10.50.1.10"
}
```
{: .output }

**Validate** — then SSM `Online` (may take 1–2 minutes):

```bash
aws ssm describe-instance-information \
  --profile shared-services --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$PROVIDER_INSTANCE_ID" \
  --query 'InstanceInformationList[0].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName}' \
  --output json
```

```text
{
    "InstanceId": "i-0aaaa1111bbbb2222",
    "PingStatus": "Online",
    "PlatformName": "Amazon Linux"
}
```
{: .output }

Then open a session:

```bash
aws ssm start-session \
  --profile shared-services --region "$AWS_REGION" \
  --target "$PROVIDER_INSTANCE_ID"
```

## Relay on the provider host

Install `scripts/relay.py` and run it under **systemd** (required). Live Wikimedia
ingest only — do not use `--replay`.

Copy files from the laptop into the SSM session (example):

```bash
# laptop — encode and paste, or use S3
base64 -w0 scripts/relay.py
base64 -w0 scripts/relay.service.example
```

```bash
# on the instance — decode into place
printf '%s' '…paste relay.py b64…' | base64 -d | sudo tee /tmp/relay.py >/dev/null
printf '%s' '…paste unit b64…' | base64 -d | sudo tee /tmp/relay.service.example >/dev/null
```
{: .on-host }

On the instance:

```bash
sudo useradd --system --home /opt/plvtgw --shell /sbin/nologin plvtgw
sudo mkdir -p /opt/plvtgw
sudo cp /tmp/relay.py /opt/plvtgw/relay.py
sudo chown -R plvtgw:plvtgw /opt/plvtgw
sudo chmod 755 /opt/plvtgw /opt/plvtgw/relay.py

sudo cp /tmp/relay.service.example /etc/systemd/system/plvtgw-relay.service
sudo systemctl daemon-reload
sudo systemctl enable --now plvtgw-relay.service
sudo systemctl status plvtgw-relay.service --no-pager
```
{: .on-host }

Confirm it is listening on **TCP 9000**, staying up, and serving **live** lines:

```bash
sudo systemctl is-active plvtgw-relay.service
sudo ss -ltnp | grep ':9000'
sudo journalctl -u plvtgw-relay.service -n 20 --no-pager

# Live ingest smoke test (should print a timestamped JSON recentchange line)
python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",9000),5); s.settimeout(8); print(s.recv(120)); s.close()'
```
{: .on-host }

**Validate** (fictitious hostname / payload snippet):

```text
active
LISTEN 0      5            0.0.0.0:9000      0.0.0.0:*    users:(("python3",pid=2051,fd=3))
Sep 12 03:04:02 ip-10-50-1-10.ap-southeast-6.compute.internal systemd[1]: Started plvtgw-relay.service - pl-vs-inspected-tgw stream relay (live Wikimedia).
Sep 12 03:04:02 ip-10-50-1-10.ap-southeast-6.compute.internal python3[2051]: listening on 0.0.0.0:9000
b'1789182255886942661 {"$schema":"/mediawiki/recentchange/1.0.0","meta":{"uri":"https://en.wiktionary.org/wiki/example"'
```
{: .output }

Both paths (PrivateLink and TGW) hit this same live process.

## PrivateLink service side

Still with `AWS_PROFILE=shared-services`. Tag with `demo=pl-vs-inspected-tgw`.

### Create the NLB

```bash
NLB_ARN=$(aws elbv2 create-load-balancer \
  --profile shared-services --region "$AWS_REGION" \
  --name plvtgw-nlb --type network --scheme internal \
  --subnets $(echo "$PROVIDER_LB_SUBNET_IDS" | tr ',' ' ') \
  --tags Key=demo,Value=pl-vs-inspected-tgw Key=Name,Value=plvtgw-nlb \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

echo "NLB_ARN=$NLB_ARN"
```

**Validate** — wait until `active` (often ~2 minutes):

```bash
aws elbv2 describe-load-balancers \
  --profile shared-services --region "$AWS_REGION" \
  --load-balancer-arns "$NLB_ARN" \
  --query 'LoadBalancers[0].{Name:LoadBalancerName,State:State.Code,Scheme:Scheme}' \
  --output json
```

```text
{
    "Name": "plvtgw-nlb",
    "State": "active",
    "Scheme": "internal"
}
```
{: .output }

### Create the target group

```bash
TG_ARN=$(aws elbv2 create-target-group \
  --profile shared-services --region "$AWS_REGION" \
  --name plvtgw-tg --protocol TCP --port 9000 \
  --vpc-id "$PROVIDER_VPC_ID" --target-type instance \
  --health-check-protocol TCP \
  --tags Key=demo,Value=pl-vs-inspected-tgw Key=Name,Value=plvtgw-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

echo "TG_ARN=$TG_ARN"
```

### Register the relay instance

```bash
aws elbv2 register-targets \
  --profile shared-services --region "$AWS_REGION" \
  --target-group-arn "$TG_ARN" \
  --targets "Id=${PROVIDER_INSTANCE_ID}"
```

### Create the listener

```bash
aws elbv2 create-listener \
  --profile shared-services --region "$AWS_REGION" \
  --load-balancer-arn "$NLB_ARN" --protocol TCP --port 9000 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}"
```

**Validate** — target becomes `healthy` after the NLB is active and health checks pass:

```bash
aws elbv2 describe-target-health \
  --profile shared-services --region "$AWS_REGION" \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[0].{Id:Target.Id,State:TargetHealth.State}' \
  --output json
```

```text
{
    "Id": "i-0aaaa1111bbbb2222",
    "State": "healthy"
}
```
{: .output }

### Create the endpoint service

```bash
SVC_ID=$(aws ec2 create-vpc-endpoint-service-configuration \
  --profile shared-services --region "$AWS_REGION" \
  --network-load-balancer-arns "$NLB_ARN" \
  --no-acceptance-required \
  --tag-specifications 'ResourceType=vpc-endpoint-service,Tags=[{Key=demo,Value=pl-vs-inspected-tgw},{Key=Name,Value=plvtgw-eps}]' \
  --query 'ServiceConfiguration.ServiceId' --output text)
```

### Resolve the service name

```bash
SVC_NAME=$(aws ec2 describe-vpc-endpoint-service-configurations \
  --profile shared-services --region "$AWS_REGION" \
  --service-ids "$SVC_ID" \
  --query 'ServiceConfigurations[0].ServiceName' --output text)

echo "SVC_ID=$SVC_ID"
echo "SVC_NAME=$SVC_NAME"
```

**Validate**:

```text
SVC_ID=vpce-svc-0aaaa1111bbbb2222
SVC_NAME=com.amazonaws.vpce.ap-southeast-6.vpce-svc-0aaaa1111bbbb2222
```
{: .output }

### Allow the consumer account

Use the consumer account ID (not the shared-services account):

```bash
export CONSUMER_ACCOUNT_ID=444455556666   # consumer account

aws ec2 modify-vpc-endpoint-service-permissions \
  --profile shared-services --region "$AWS_REGION" \
  --service-id "$SVC_ID" \
  --add-allowed-principals "arn:aws:iam::${CONSUMER_ACCOUNT_ID}:root"
```

**Validate**:

```bash
aws ec2 describe-vpc-endpoint-service-permissions \
  --profile shared-services --region "$AWS_REGION" \
  --service-id "$SVC_ID" \
  --output json
```

```text
{
    "AllowedPrincipals": [
        {
            "PrincipalType": "Account",
            "Principal": "arn:aws:iam::444455556666:root",
            "ServicePermissionId": "vpce-svc-perm-0bbbb2222cccc3333",
            "ServiceId": "vpce-svc-0aaaa1111bbbb2222"
        }
    ]
}
```
{: .output }

Keep `$SVC_NAME`, `$NLB_ARN`, `$TG_ARN`, `$SVC_ID`, `$PROVIDER_INSTANCE_ID`, and `$RELAY_PRIVATE_IP` for [Consumer]({{ site.baseurl }}/setup/consumer/) and [Teardown]({{ site.baseurl }}/teardown/).

Optional shortcut (same API calls through the VPCE create): `./scripts/setup-privatelink.sh` — keeps IDs under `scripts/.state/`.

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/setup/consumer/">
    <strong>Consumer</strong>
    <span>Profile consumer · VPCE · measure</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/setup/prep/">
    <strong>Prep</strong>
    <span>Clone the repo</span>
  </a>
</div>
