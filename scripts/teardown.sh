#!/usr/bin/env bash
# Tear down harness resources (PrivateLink + EC2 + SGs + IAM).
# Prefers scripts/.state; falls back to demo=pl-vs-inspected-tgw / Name=plvtgw-* discovery.
# Does NOT touch TGW, inspection VPC, or Network Firewall.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${ROOT}/scripts/.state"
PROVIDER_PROFILE="${PROVIDER_PROFILE:-shared-services}"
CONSUMER_PROFILE="${CONSUMER_PROFILE:-consumer}"
TAG_KEY="${TAG_KEY:-demo}"
TAG_VAL="${TAG_VAL:-pl-vs-inspected-tgw}"

: "${AWS_REGION:?set AWS_REGION}"

read_state() {
  local f="$STATE_DIR/$1"
  [[ -f "$f" ]] || return 1
  cat "$f"
}

echo "== consumer: interface endpoint =="
if EP_ID=$(read_state endpoint_id); then
  aws ec2 delete-vpc-endpoints \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --vpc-endpoint-ids "$EP_ID" || true
else
  mapfile -t EPS < <(aws ec2 describe-vpc-endpoints \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --filters "Name=tag:${TAG_KEY},Values=${TAG_VAL}" \
    --query 'VpcEndpoints[?contains(ServiceName, `vpce-svc`)].VpcEndpointId' --output text)
  if [[ ${#EPS[@]} -gt 0 && -n "${EPS[0]}" ]]; then
    aws ec2 delete-vpc-endpoints \
      --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
      --vpc-endpoint-ids ${EPS[*]} || true
  fi
fi

echo "== consumer: terminate plvtgw-subscriber =="
if CID=$(read_state consumer_instance_id); then
  :
else
  CID=$(aws ec2 describe-instances \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --filters Name=tag:Name,Values=plvtgw-subscriber \
              Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
fi
if [[ -n "${CID:-}" && "$CID" != "None" ]]; then
  aws ec2 terminate-instances \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$CID" || true
  aws ec2 wait instance-terminated \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$CID" || true
fi

echo "== provider: endpoint service =="
if SVC_ID=$(read_state service_id); then
  aws ec2 delete-vpc-endpoint-service-configurations \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --service-ids "$SVC_ID" || true
else
  mapfile -t SVCS < <(aws ec2 describe-vpc-endpoint-service-configurations \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --query "ServiceConfigurations[?Tags[?Key=='${TAG_KEY}' && Value=='${TAG_VAL}']].ServiceId" \
    --output text)
  if [[ ${#SVCS[@]} -gt 0 && -n "${SVCS[0]}" ]]; then
    aws ec2 delete-vpc-endpoint-service-configurations \
      --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
      --service-ids ${SVCS[*]} || true
  fi
fi

echo "== provider: listener + NLB + target group =="
if LISTENER_ARN=$(read_state listener_arn); then
  aws elbv2 delete-listener \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --listener-arn "$LISTENER_ARN" || true
fi

if NLB_ARN=$(read_state nlb_arn); then
  :
else
  NLB_ARN=$(aws elbv2 describe-load-balancers \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --query 'LoadBalancers[?LoadBalancerName==`plvtgw-nlb`].LoadBalancerArn | [0]' --output text)
fi
if [[ -n "${NLB_ARN:-}" && "$NLB_ARN" != "None" ]]; then
  # delete listeners if state missing
  mapfile -t LARS < <(aws elbv2 describe-listeners \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --load-balancer-arn "$NLB_ARN" \
    --query 'Listeners[].ListenerArn' --output text 2>/dev/null || true)
  for lar in ${LARS[*]:-}; do
    [[ -n "$lar" && "$lar" != "None" ]] || continue
    aws elbv2 delete-listener \
      --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
      --listener-arn "$lar" || true
  done
  aws elbv2 delete-load-balancer \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --load-balancer-arn "$NLB_ARN" || true
  for _ in $(seq 1 60); do
    if ! aws elbv2 describe-load-balancers \
      --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
      --load-balancer-arns "$NLB_ARN" &>/dev/null; then
      break
    fi
    sleep 5
  done
fi

if TG_ARN=$(read_state tg_arn); then
  :
else
  TG_ARN=$(aws elbv2 describe-target-groups \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --query 'TargetGroups[?TargetGroupName==`plvtgw-tg`].TargetGroupArn | [0]' --output text)
fi
if [[ -n "${TG_ARN:-}" && "$TG_ARN" != "None" ]]; then
  aws elbv2 delete-target-group \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --target-group-arn "$TG_ARN" || true
fi

echo "== provider: terminate plvtgw-relay =="
if PID=$(read_state provider_instance_id); then
  :
else
  PID=$(aws ec2 describe-instances \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --filters Name=tag:Name,Values=plvtgw-relay \
              Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
fi
if [[ -n "${PID:-}" && "$PID" != "None" ]]; then
  aws ec2 terminate-instances \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$PID" || true
  aws ec2 wait instance-terminated \
    --profile "$PROVIDER_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$PID" || true
fi

echo "== security groups (plvtgw-*) =="
sleep 10
for profile in "$CONSUMER_PROFILE" "$PROVIDER_PROFILE"; do
  mapfile -t SGS < <(aws ec2 describe-security-groups \
    --profile "$profile" --region "$AWS_REGION" \
    --filters Name=group-name,Values=plvtgw-* \
    --query 'SecurityGroups[].GroupId' --output text)
  for sg in ${SGS[*]:-}; do
    [[ -n "$sg" && "$sg" != "None" ]] || continue
    aws ec2 delete-security-group \
      --profile "$profile" --region "$AWS_REGION" \
      --group-id "$sg" || true
  done
done

echo "== lab-only SSM VPCEs (Name=plvtgw-ssm) =="
for profile in "$CONSUMER_PROFILE" "$PROVIDER_PROFILE"; do
  mapfile -t SSM_EPS < <(aws ec2 describe-vpc-endpoints \
    --profile "$profile" --region "$AWS_REGION" \
    --filters Name=tag:Name,Values=plvtgw-ssm \
    --query 'VpcEndpoints[].VpcEndpointId' --output text)
  if [[ ${#SSM_EPS[@]} -gt 0 && -n "${SSM_EPS[0]}" ]]; then
    aws ec2 delete-vpc-endpoints \
      --profile "$profile" --region "$AWS_REGION" \
      --vpc-endpoint-ids ${SSM_EPS[*]} || true
  fi
done

echo "== IAM plvtgw-ec2-ssm (both accounts) =="
for profile in "$CONSUMER_PROFILE" "$PROVIDER_PROFILE"; do
  aws iam remove-role-from-instance-profile \
    --profile "$profile" \
    --instance-profile-name plvtgw-ec2-ssm \
    --role-name plvtgw-ec2-ssm 2>/dev/null || true
  aws iam delete-instance-profile \
    --profile "$profile" \
    --instance-profile-name plvtgw-ec2-ssm 2>/dev/null || true
  aws iam detach-role-policy \
    --profile "$profile" \
    --role-name plvtgw-ec2-ssm \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
  aws iam delete-role \
    --profile "$profile" \
    --role-name plvtgw-ec2-ssm 2>/dev/null || true
done

echo "harness teardown finished."
echo "Hub TGW / Network Firewall were not modified."
echo "state files left in ${STATE_DIR}; delete when satisfied."
