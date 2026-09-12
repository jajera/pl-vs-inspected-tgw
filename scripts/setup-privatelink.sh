#!/usr/bin/env bash
# Create NLB + endpoint service (provider) and interface endpoint (consumer).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STATE_DIR="${ROOT}/scripts/.state"
mkdir -p "$STATE_DIR"

PREFIX="${RESOURCE_PREFIX:-plvtgw}"
PORT="${STREAM_PORT:-9000}"
TAG_KEY="${TAG_KEY:-demo}"
TAG_VAL="${TAG_VAL:-pl-vs-inspected-tgw}"
PROVIDER_PROFILE="${PROVIDER_PROFILE:-shared-services}"
CONSUMER_PROFILE="${CONSUMER_PROFILE:-consumer}"

: "${AWS_REGION:?set AWS_REGION}"
: "${PROVIDER_VPC_ID:?}"
: "${PROVIDER_SUBNET_IDS:?}" # comma-separated
: "${PROVIDER_INSTANCE_ID:?}"
: "${CONSUMER_VPC_ID:?}"
: "${CONSUMER_SUBNET_IDS:?}"
: "${CONSUMER_ENDPOINT_SG_ID:?}"
: "${CONSUMER_ACCOUNT_ID:?}"

IFS=',' read -r -a PROVIDER_SUBNETS <<<"$PROVIDER_SUBNET_IDS"
IFS=',' read -r -a CONSUMER_SUBNETS <<<"$CONSUMER_SUBNET_IDS"

echo "creating NLB in provider account..."
NLB_ARN=$(aws elbv2 create-load-balancer \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --name "${PREFIX}-nlb" --type network --scheme internal \
  --subnets "${PROVIDER_SUBNETS[@]}" \
  --tags "Key=${TAG_KEY},Value=${TAG_VAL}" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "$NLB_ARN" >"$STATE_DIR/nlb_arn"

TG_ARN=$(aws elbv2 create-target-group \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --name "${PREFIX}-tg" --protocol TCP --port "$PORT" \
  --vpc-id "$PROVIDER_VPC_ID" --target-type instance \
  --health-check-protocol TCP \
  --tags "Key=${TAG_KEY},Value=${TAG_VAL}" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "$TG_ARN" >"$STATE_DIR/tg_arn"

aws elbv2 register-targets \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --target-group-arn "$TG_ARN" \
  --targets "Id=${PROVIDER_INSTANCE_ID}"

LISTENER_ARN=$(aws elbv2 create-listener \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --load-balancer-arn "$NLB_ARN" --protocol TCP --port "$PORT" \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --query 'Listeners[0].ListenerArn' --output text)
echo "$LISTENER_ARN" >"$STATE_DIR/listener_arn"

echo "creating endpoint service..."
SVC_ID=$(aws ec2 create-vpc-endpoint-service-configuration \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --network-load-balancer-arns "$NLB_ARN" \
  --no-acceptance-required \
  --tag-specifications "ResourceType=vpc-endpoint-service,Tags=[{Key=${TAG_KEY},Value=${TAG_VAL}}]" \
  --query 'ServiceConfiguration.ServiceId' --output text)
echo "$SVC_ID" >"$STATE_DIR/service_id"

SVC_NAME=$(aws ec2 describe-vpc-endpoint-service-configurations \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --service-ids "$SVC_ID" \
  --query 'ServiceConfigurations[0].ServiceName' --output text)
echo "$SVC_NAME" >"$STATE_DIR/service_name"

aws ec2 modify-vpc-endpoint-service-permissions \
  --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
  --service-id "$SVC_ID" \
  --add-allowed-principals "arn:aws:iam::${CONSUMER_ACCOUNT_ID}:root"

echo "creating interface endpoint in consumer account..."
EP_ID=$(aws ec2 create-vpc-endpoint \
  --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
  --vpc-endpoint-type Interface \
  --service-name "$SVC_NAME" \
  --vpc-id "$CONSUMER_VPC_ID" \
  --subnet-ids "${CONSUMER_SUBNETS[@]}" \
  --security-group-ids "$CONSUMER_ENDPOINT_SG_ID" \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=${TAG_KEY},Value=${TAG_VAL}}]" \
  --query 'VpcEndpoint.VpcEndpointId' --output text)
echo "$EP_ID" >"$STATE_DIR/endpoint_id"

echo "waiting for endpoint available..."
aws ec2 wait vpc-endpoint-available \
  --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
  --vpc-endpoint-ids "$EP_ID"

PL_DNS=$(aws ec2 describe-vpc-endpoints \
  --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
  --vpc-endpoint-ids "$EP_ID" \
  --query 'VpcEndpoints[0].DnsEntries[0].DnsName' --output text)
echo "$PL_DNS" >"$STATE_DIR/pl_dns"

cat <<EOF
done.

service_id=${SVC_ID}
service_name=${SVC_NAME}
endpoint_id=${EP_ID}
pl_dns=${PL_DNS}

On the consumer host:
  python3 sub.py ${PL_DNS} ${PORT} 120
  python3 sub.py ${RELAY_PRIVATE_IP:-<RELAY_PRIVATE_IP>} ${PORT} 120
EOF
