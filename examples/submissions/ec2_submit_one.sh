#!/usr/bin/env bash
# Submit ONE mock_computation job to an EC2-backend HTC-Grid from OUTSIDE the VPC.
#
# A host outside the grid VPC cannot reach the private API Gateway or ElastiCache Redis, so we
# do NOT submit from here. Instead we run the submitter image ON a worker instance (which is
# inside the VPC) via SSM RunShellScript, and only orchestrate from this machine. This machine
# needs AWS creds with: lambda:InvokeFunction (orchestrator, for status only),
# ssm:SendCommand + GetCommandInvocation, and ec2:DescribeInstances.
#
# This script does NOT touch the capacity controller and does NOT ask ORB to create capacity.
# It expects at least one worker to already be running: it selects one and submits to it, or
# errors out if there are none. Manage capacity out of band (e.g. orb_api_probe.sh RUN_CREATE=1).
#
# Usage:  TAG=mygrid REGION=eu-west-1 ./ec2_submit_one.sh
#
# Reconstructed after the work instance was terminated with this file uncommitted; rebuilt from
# the session transcript (header, step logic, and the exact intra-VPC submitter invocation that
# was used live). Re-test before relying on it.
set -euo pipefail

TAG="${TAG:?set TAG to the grid/project tag, e.g. main-orb-t1}"
REGION="${REGION:-eu-west-1}"
ORCHESTRATOR="orb-orchestrator-${TAG}"
ECR="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com"
SUBMITTER_IMAGE="${ECR}/submitter:${TAG}"

# Job shape (small single batch by default; override via env).
NUM_TASKS="${NUM_TASKS:-1}"
WORKER_ARGS="${WORKER_ARGS:-1000 1 1}"   # "<duration_ms> <memory> <output>" for mock_computation
JOB_SIZE="${JOB_SIZE:-10}"
JOB_BATCH_SIZE="${JOB_BATCH_SIZE:-5}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

orb_invoke() {  # $1 = JSON payload -> writes response to /tmp/orb_status.json, echoes it
  aws lambda invoke --function-name "${ORCHESTRATOR}" --region "${REGION}" \
    --cli-binary-format raw-in-base64-out --payload "$1" /tmp/orb_status.json >/dev/null
  cat /tmp/orb_status.json
}

# --- 1. Select an already-running worker (no controller, no capacity create) -------------------
# This script does not manage capacity: it expects a worker to be running already, picks one,
# and errors out if there are none. Ensure capacity beforehand (e.g. orb_api_probe.sh RUN_CREATE=1).
running_worker() {
  orb_invoke '{"action":"status"}' >/dev/null
  python3 - <<'PY'
import json
d = json.load(open("/tmp/orb_status.json"))
machines = d.get("body", {}).get("result", {}).get("machines", [])
ids = [m["machine_id"] for m in machines if m.get("status") == "running"]
print(ids[0] if ids else "")
PY
}

INSTANCE_ID="$(running_worker)"
[ -n "${INSTANCE_ID}" ] || {
  log "ERROR: no running worker for ${TAG}; this script does not launch capacity."
  log "       Start a worker first (e.g. RUN_CREATE=1 ./orb_api_probe.sh) and retry."
  exit 1
}
log "using worker ${INSTANCE_ID}"

# --- 2. Wait for bootstrap to finish (SSM agent Online + 'bootstrap complete' in the log) -------
log "waiting for SSM + bootstrap complete on ${INSTANCE_ID}"
# Pass commands via a JSON file to avoid inline --parameters quoting pitfalls.
cat > /tmp/ssm_check.json <<JSON
{"commands":["grep -c 'bootstrap complete' /var/log/htc-bootstrap.log 2>/dev/null || echo 0"]}
JSON
for _ in $(seq 1 30); do
  CMD_ID="$(aws ssm send-command --region "${REGION}" --instance-ids "${INSTANCE_ID}" \
    --document-name AWS-RunShellScript --parameters file:///tmp/ssm_check.json \
    --query 'Command.CommandId' --output text 2>/dev/null || true)"
  if [ -n "${CMD_ID:-}" ]; then
    sleep 3
    OUT="$(aws ssm get-command-invocation --region "${REGION}" \
      --command-id "${CMD_ID}" --instance-id "${INSTANCE_ID}" \
      --query 'StandardOutputContent' --output text 2>/dev/null || echo 0)"
    [ "${OUT//[$'\t\r\n ']/}" != "0" ] && { log "bootstrap complete"; break; }
  fi
  sleep 7
done

# --- 3. Submit one job by running the submitter image ON the worker (intra-VPC) -----------------
# INTRA_VPC=1 makes the client use the private API Gateway and skip Cognito; the worker is in-VPC.
# We log Docker in to ECR on the worker first (the submitter image is private), then run the client
# with --do_print true so each task's result (the producer output) is echoed to stdout. The worker's
# instance profile must allow ecr:GetAuthorizationToken + pull (workers normally already have this).
log "submitting workload via submitter image on ${INSTANCE_ID}"
cat > /tmp/ssm_submit.json <<JSON
{"commands":[
"set -eo pipefail",
"aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR}",
"docker run --rm --network host -e INTRA_VPC=1 -e AWS_REGION=${REGION} -v /opt/htc/agent-config:/etc/agent:ro ${SUBMITTER_IMAGE} python3 ./client.py -n ${NUM_TASKS} --worker_arguments \"${WORKER_ARGS}\" --job_size ${JOB_SIZE} --job_batch_size ${JOB_BATCH_SIZE} --do_print true --log warning"
]}
JSON
SUBMIT_CMD_ID="$(aws ssm send-command --region "${REGION}" --instance-ids "${INSTANCE_ID}" \
  --document-name AWS-RunShellScript --parameters file:///tmp/ssm_submit.json \
  --query 'Command.CommandId' --output text)"
log "submit command ${SUBMIT_CMD_ID}; waiting for completion"

# Block until the command reaches a terminal state. The waiter itself fails on a non-zero exit code,
# so we don't trust it for pass/fail (|| true); we verify explicitly from the invocation below.
aws ssm wait command-executed --region "${REGION}" \
  --command-id "${SUBMIT_CMD_ID}" --instance-id "${INSTANCE_ID}" 2>/dev/null || true

# --- 4. Verify the task condition and print the producer results --------------------------------
# Pull the full invocation (status + exit code + BOTH output streams). The client prints each task's
# result on stdout (--do_print); diagnostic logging goes to stderr.
#
# Authoritative pass/fail = the SSM ResponseCode. The client calls sys.exit(1) if jw.verify_results()
# fails for any task (client.py), and multiprocessing_execute_py re-raises a non-zero child exit, so
# the container — and thus the SSM command — can only exit 0 if EVERY task's result was retrieved and
# verified. We surface the "All results are verified!" log line as a bonus when present, but do not
# require it: SSM truncates each stream to ~24KB, so that tail line may legitimately be cut off.
aws ssm get-command-invocation --region "${REGION}" \
  --command-id "${SUBMIT_CMD_ID}" --instance-id "${INSTANCE_ID}" \
  --output json > /tmp/ssm_submit_result.json 2>/dev/null || true

RC=0
python3 - <<'PY' || RC=$?
import json, sys
try:
    d = json.load(open("/tmp/ssm_submit_result.json"))
except Exception as e:
    print("ERROR: could not read SSM invocation result: {}".format(e))
    sys.exit(2)

status = d.get("Status", "Unknown")
code = d.get("ResponseCode", -1)
stdout = (d.get("StandardOutputContent") or "").rstrip()
stderr = (d.get("StandardErrorContent") or "").rstrip()

print("---- submitter (producer) stdout ----")
print(stdout if stdout else "(empty)")
if stderr:
    print("---- submitter (producer) stderr ----")
    print(stderr)
print("-------------------------------------")
print("SSM status={} exit_code={}".format(status, code))

ssm_ok = (status == "Success" and code == 0)
verified = ("All results are verified" in stdout) or ("All results are verified" in stderr)

if ssm_ok:
    extra = "" if verified else " (verification log line truncated by SSM, but exit 0 implies all tasks verified)"
    print("RESULT: PASS - all tasks completed and producer results verified{}".format(extra))
    sys.exit(0)
print("RESULT: FAIL - submitter did not complete cleanly (status={} exit_code={}); see streams above".format(status, code))
sys.exit(1)
PY

log "done (verification exit ${RC})"
exit ${RC}
