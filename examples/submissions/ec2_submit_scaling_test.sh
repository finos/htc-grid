#!/usr/bin/env bash
# Submit a LARGE batch of mock_computation tasks to an EC2-backend HTC-Grid to exercise
# autoscaling, then watch ORB's live worker count climb in response.
#
# Same principles as ec2_submit_one.sh: a host outside the grid VPC cannot reach the private
# API Gateway or ElastiCache Redis, so we do NOT submit from here. We run the submitter image
# ON an already-running worker (inside the VPC) via SSM RunShellScript and only orchestrate from
# this machine. Required creds: lambda:InvokeFunction (orchestrator status), ssm:SendCommand +
# GetCommandInvocation, ec2:DescribeInstances.
#
# Difference from ec2_submit_one.sh:
#   * Takes a TASK COUNT as input and floods the grid with that many tasks in a single batch,
#     so a deep backlog forms before any worker can drain it.
#   * Tasks are LONG by default (WORKER_ARGS duration) so the backlog persists across the
#     capacity_controller's rate(1 min) tick and scaling is actually observable.
#   * Does NOT block on per-task verification (that is ec2_submit_one.sh's job). It launches the
#     submitter DETACHED and then polls ORB {"action":"status"} to show the live machine count
#     and per-state breakdown grow over a watch window.
#
# This script needs ONE worker already running to submit from (it does not create capacity); the
# capacity_controller is what scales the rest UP in response to the backlog. Ensure the seed
# worker exists first (e.g. RUN_CREATE=1 ./orb_api_probe.sh), and that the capacity_controller is
# deployed and its max is high enough to show movement.
#
# Usage:  TAG=mygrid REGION=eu-west-1 ./ec2_submit_scaling_test.sh <num_tasks>
#   e.g.  TAG=ec2orb1 ./ec2_submit_scaling_test.sh 2000
set -euo pipefail

NUM_TASKS_TOTAL="${1:?usage: $0 <num_tasks>   (total tasks to flood the grid with, e.g. 2000)}"
case "${NUM_TASKS_TOTAL}" in
  ''|*[!0-9]*) echo "ERROR: <num_tasks> must be a positive integer, got '${NUM_TASKS_TOTAL}'"; exit 2 ;;
esac
[ "${NUM_TASKS_TOTAL}" -ge 1 ] || { echo "ERROR: <num_tasks> must be >= 1"; exit 2; }

TAG="${TAG:?set TAG to the grid/project tag, e.g. main-orb-t1}"
REGION="${REGION:-eu-west-1}"
ORCHESTRATOR="orb-orchestrator-${TAG}"
ECR="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com"
SUBMITTER_IMAGE="${ECR}/submitter:${TAG}"

# Job shape. The client computes total tasks as nthreads * njobs * job_batch_size * job_size.
# We flood in a SINGLE batch (njobs=1): the client submits every session up front, then waits,
# so the whole load lands on the queue before draining begins. We derive job_batch_size (sessions
# per thread) from the requested total so that <num_tasks> is honoured (rounded up to a whole
# number of sessions; the actual submitted count is reported below).
JOB_SIZE="${JOB_SIZE:-10}"          # tasks per session
NTHREADS="${NTHREADS:-1}"           # parallel submitter processes inside the container
# Long tasks by default so backlog outlives the 1-min controller tick (override for quick smoke).
WORKER_ARGS="${WORKER_ARGS:-60000 1 1}"   # "<duration_ms> <memory> <output>" for mock_computation

# Scaling watch window.
WATCH_SECS="${WATCH_SECS:-360}"     # how long to poll ORB after submitting
WATCH_INTERVAL="${WATCH_INTERVAL:-15}"

# sessions per thread = ceil(total / (job_size * nthreads)); >= 1
JOB_BATCH_SIZE=$(( (NUM_TASKS_TOTAL + JOB_SIZE * NTHREADS - 1) / (JOB_SIZE * NTHREADS) ))
[ "${JOB_BATCH_SIZE}" -ge 1 ] || JOB_BATCH_SIZE=1
ACTUAL_TASKS=$(( NTHREADS * JOB_BATCH_SIZE * JOB_SIZE ))

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

orb_invoke() {  # $1 = JSON payload -> writes response to /tmp/orb_status.json, echoes it
  aws lambda invoke --function-name "${ORCHESTRATOR}" --region "${REGION}" \
    --cli-binary-format raw-in-base64-out --payload "$1" /tmp/orb_status.json >/dev/null
  cat /tmp/orb_status.json
}

# Print "<live_count> <state breakdown>" for the current ORB status, e.g. "3 running=2,pending=1".
orb_live_summary() {
  orb_invoke '{"action":"status"}' >/dev/null
  python3 - <<'PY'
import json
from collections import Counter
d = json.load(open("/tmp/orb_status.json"))
machines = d.get("body", {}).get("result", {}).get("machines", [])
live = {"pending", "running", "stopping", "shutting-down"}
states = [m.get("status") for m in machines if m.get("status") in live]
c = Counter(states)
breakdown = ",".join("{}={}".format(k, c[k]) for k in sorted(c)) or "none"
print("{} {}".format(len(states), breakdown))
PY
}

# --- 1. Select an already-running worker to submit FROM (no capacity create here) --------------
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
  log "ERROR: no running worker for ${TAG}; this script submits from an existing worker, it does not launch one."
  log "       Start a seed worker first (e.g. RUN_CREATE=1 ./orb_api_probe.sh) and retry."
  exit 1
}
log "submitting from worker ${INSTANCE_ID}"
log "requested ${NUM_TASKS_TOTAL} tasks -> shape: nthreads=${NTHREADS} njobs=1 job_batch_size=${JOB_BATCH_SIZE} job_size=${JOB_SIZE} (actual=${ACTUAL_TASKS} tasks, worker_args='${WORKER_ARGS}')"

# --- 2. Wait for bootstrap to finish on the seed worker (only matters if it just launched) ------
log "waiting for SSM + bootstrap complete on ${INSTANCE_ID}"
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

# --- 3. Flood the grid: run the submitter DETACHED on the worker so we return immediately --------
# INTRA_VPC=1 -> private API Gateway, skip Cognito. We log in to ECR first (private image), then
# `docker run -d` returns a container id at once; the SSM command does not block on the workload.
# No --do_print here (we are not inspecting results) and --log warning to keep things quiet.
log "launching detached submitter (this floods the queue, then returns)"
cat > /tmp/ssm_flood.json <<JSON
{"commands":[
"set -eo pipefail",
"aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR}",
"docker run -d --rm --network host -e INTRA_VPC=1 -e AWS_REGION=${REGION} -v /opt/htc/agent-config:/etc/agent:ro --name htc-scaling-test ${SUBMITTER_IMAGE} python3 ./client.py -n 1 --nthreads ${NTHREADS} --worker_arguments \"${WORKER_ARGS}\" --job_size ${JOB_SIZE} --job_batch_size ${JOB_BATCH_SIZE} --log warning"
]}
JSON
FLOOD_CMD_ID="$(aws ssm send-command --region "${REGION}" --instance-ids "${INSTANCE_ID}" \
  --document-name AWS-RunShellScript --parameters file:///tmp/ssm_flood.json \
  --query 'Command.CommandId' --output text)"
log "flood command ${FLOOD_CMD_ID}; waiting for the submitter container to start"
aws ssm wait command-executed --region "${REGION}" \
  --command-id "${FLOOD_CMD_ID}" --instance-id "${INSTANCE_ID}" 2>/dev/null || true
aws ssm get-command-invocation --region "${REGION}" \
  --command-id "${FLOOD_CMD_ID}" --instance-id "${INSTANCE_ID}" \
  --output json > /tmp/ssm_flood_result.json 2>/dev/null || true
python3 - <<'PY' || true
import json
try:
    d = json.load(open("/tmp/ssm_flood_result.json"))
except Exception:
    raise SystemExit
status, code = d.get("Status", "?"), d.get("ResponseCode", "?")
cid = (d.get("StandardOutputContent") or "").strip().splitlines()[-1:] or [""]
print("submitter launch: SSM status={} exit_code={} container={}".format(status, code, cid[0][:12]))
err = (d.get("StandardErrorContent") or "").strip()
if status != "Success" and err:
    print("---- launch stderr ----"); print(err[-800:])
PY

# --- 4. Watch ORB scale UP in response to the backlog -------------------------------------------
# Supply-side signal: ORB's live machine count. The capacity_controller reads the SQS/DDB backlog
# on its rate(1 min) tick and asks ORB to create workers; here we just poll status and watch the
# count (and per-state breakdown) move. Expect the first change within ~1-2 minutes.
BASELINE="$(orb_live_summary)"
log "baseline live workers: ${BASELINE}"
log "watching ORB for ${WATCH_SECS}s (every ${WATCH_INTERVAL}s); expect scale-up within ~1-2 min"
PEAK=0
ELAPSED=0
while [ "${ELAPSED}" -lt "${WATCH_SECS}" ]; do
  sleep "${WATCH_INTERVAL}"
  ELAPSED=$(( ELAPSED + WATCH_INTERVAL ))
  SUMMARY="$(orb_live_summary || echo '? error')"
  COUNT="${SUMMARY%% *}"
  case "${COUNT}" in ''|*[!0-9]*) COUNT=0 ;; esac
  [ "${COUNT}" -gt "${PEAK}" ] && PEAK="${COUNT}"
  log "t+${ELAPSED}s  live workers: ${SUMMARY}  (peak ${PEAK})"
done

BASE_COUNT="${BASELINE%% *}"
case "${BASE_COUNT}" in ''|*[!0-9]*) BASE_COUNT=0 ;; esac
log "done: baseline=${BASE_COUNT} peak=${PEAK} (submitted ${ACTUAL_TASKS} tasks)"
if [ "${PEAK}" -gt "${BASE_COUNT}" ]; then
  log "RESULT: SCALE-UP OBSERVED (live workers grew ${BASE_COUNT} -> ${PEAK})"
  exit 0
fi
log "RESULT: NO SCALE-UP SEEN within ${WATCH_SECS}s. Check: backlog actually formed (CloudWatch"
log "        pending_tasks_ddb), capacity_controller deployed + max > ${BASE_COUNT}, tasks long"
log "        enough (WORKER_ARGS duration), and WATCH_SECS long enough for a rate(1 min) tick."
exit 1
