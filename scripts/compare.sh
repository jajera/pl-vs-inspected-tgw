#!/usr/bin/env bash
# Run sub.py on the consumer instance for both paths via SSM send-command.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STATE_DIR="${ROOT}/scripts/.state"
PORT="${STREAM_PORT:-9000}"
SECONDS_RUN="${COMPARE_SECONDS:-120}"
CONSUMER_PROFILE="${CONSUMER_PROFILE:-consumer}"

: "${AWS_REGION:?set AWS_REGION}"
: "${CONSUMER_INSTANCE_ID:?}"
: "${RELAY_PRIVATE_IP:?}"

PL_DNS="${PL_DNS:-}"
if [[ -z "$PL_DNS" && -f "$STATE_DIR/pl_dns" ]]; then
  PL_DNS=$(cat "$STATE_DIR/pl_dns")
fi
: "${PL_DNS:?set PL_DNS or run setup-privatelink.sh first}"

run_one() {
  local label="$1"
  local host="$2"
  local cmd="python3 /opt/plvtgw/sub.py ${host} ${PORT} ${SECONDS_RUN}"
  echo "=== ${label}: ${host} ==="
  local cid
  cid=$(aws ssm send-command \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$CONSUMER_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"${cmd}\"]" \
    --query 'Command.CommandId' --output text)

  aws ssm wait command-executed \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --command-id "$cid" --instance-id "$CONSUMER_INSTANCE_ID" || true

  aws ssm get-command-invocation \
    --profile "$CONSUMER_PROFILE" --region "$AWS_REGION" \
    --command-id "$cid" --instance-id "$CONSUMER_INSTANCE_ID" \
    --query '{Status:Status,Stdout:StandardOutputContent,Stderr:StandardErrorContent}' \
    --output text
  echo
}

run_one "privatelink" "$PL_DNS"
run_one "tgw-inspected" "$RELAY_PRIVATE_IP"
