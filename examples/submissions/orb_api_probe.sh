#!/usr/bin/env bash
# Probe every action the orb-orchestrator Lambda exposes and print each response.
#
# The handler (source/compute_plane/orb_orchestrator/orb_lambda.py) dispatches on `action`:
#   status    - read-only: live machines, full history, and (if given) one request's status
#   create    - MUTATES: launches `count` instances via ORB
#   terminate - MUTATES: returns specific machine_ids via ORB (graceful)
#
# Read-only `status` calls always run. The two mutating actions are OFF by default and only
# run when you opt in (RUN_CREATE=1 / RUN_TERMINATE=1), so a bare run can't change your fleet.
#
# Usage:
#   TAG=ec2orb1 REGION=eu-west-1 ./orb_api_probe.sh            # status probes only
#   TAG=ec2orb1 RUN_CREATE=1 ./orb_api_probe.sh               # also create 1 instance
#   TAG=ec2orb1 RUN_TERMINATE=1 MACHINE_IDS="i-abc,i-def" ./orb_api_probe.sh   # also terminate
#
# Needs AWS creds with lambda:InvokeFunction on orb-orchestrator-<TAG>.
set -euo pipefail

TAG="${TAG:?set TAG to the grid/project tag, e.g. ec2orb1}"
REGION="${REGION:-eu-west-1}"
ORCHESTRATOR="orb-orchestrator-${TAG}"

CREATE_TEMPLATE_ID="${CREATE_TEMPLATE_ID:-RunInstances-OnDemand}"
CREATE_COUNT="${CREATE_COUNT:-1}"
MACHINE_IDS="${MACHINE_IDS:-}"   # comma-separated, required when RUN_TERMINATE=1
REQUEST_ID="${REQUEST_ID:-}"     # optional: probe status of one specific request

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# Pretty-print JSON if a pretty-printer is around; otherwise pass through untouched.
pp() {
  if command -v jq >/dev/null 2>&1; then jq .
  elif command -v python3 >/dev/null 2>&1; then python3 -m json.tool
  else cat
  fi
}

# probe <label> <json-payload>: invoke the orchestrator and print the response.
probe() {
  local label="$1" payload="$2"
  echo
  echo "==================================================================="
  log "${label}"
  echo "  -> payload: ${payload}"
  echo "-------------------------------------------------------------------"
  if aws lambda invoke \
      --function-name "${ORCHESTRATOR}" --region "${REGION}" \
      --cli-binary-format raw-in-base64-out --payload "${payload}" \
      /tmp/orb_probe_out.json >/dev/null 2>/tmp/orb_probe_err.txt; then
    pp < /tmp/orb_probe_out.json
  else
    log "ERROR invoking ${ORCHESTRATOR}:"
    cat /tmp/orb_probe_err.txt
  fi
}

log "probing ${ORCHESTRATOR} in ${REGION}"

# --- status: read-only, always safe to run ------------------------------------------------
probe "status (live machines)"            '{"action":"status"}'
probe "status (include terminated)"       '{"action":"status","include_terminated":true}'
if [ -n "${REQUEST_ID}" ]; then
  probe "status (request ${REQUEST_ID})"  "{\"action\":\"status\",\"request_id\":\"${REQUEST_ID}\"}"
else
  log "skipping request-scoped status (set REQUEST_ID=req-... to probe one request)"
fi

# --- create: mutating, opt-in -------------------------------------------------------------
if [ "${RUN_CREATE:-0}" = "1" ]; then
  probe "create (${CREATE_COUNT}x ${CREATE_TEMPLATE_ID})" \
    "{\"action\":\"create\",\"template_id\":\"${CREATE_TEMPLATE_ID}\",\"count\":${CREATE_COUNT}}"
else
  log "skipping create (set RUN_CREATE=1 to launch ${CREATE_COUNT}x ${CREATE_TEMPLATE_ID})"
fi

# --- terminate: mutating, opt-in, needs explicit machine ids ------------------------------
if [ "${RUN_TERMINATE:-0}" = "1" ]; then
  if [ -z "${MACHINE_IDS}" ]; then
    log "ERROR: RUN_TERMINATE=1 but MACHINE_IDS is empty; set MACHINE_IDS=\"i-abc,i-def\""
  else
    # Turn the comma-separated list into a JSON array: i-abc,i-def -> ["i-abc","i-def"]
    ids_json="$(printf '%s' "${MACHINE_IDS}" | awk -F, '{for(i=1;i<=NF;i++){printf "%s\"%s\"",(i>1?",":""),$i}}')"
    probe "terminate ([${ids_json}])" "{\"action\":\"terminate\",\"machine_ids\":[${ids_json}]}"
  fi
else
  log "skipping terminate (set RUN_TERMINATE=1 MACHINE_IDS=\"i-...\" to return instances)"
fi

echo
log "done"
