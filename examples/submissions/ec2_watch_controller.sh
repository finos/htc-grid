#!/usr/bin/env bash
# Live-tail the EC2 capacity_controller Lambda's CloudWatch logs and pretty-print what it is doing.
#
# The controller emits structured JSON log lines (see ec2_capacity_controller.py). This script
# follows the log group and distills the noisy JSON down to the reconcile decisions you care about:
#   * "capacity reconcile"  -> backlog / live / active / draining / desired (the per-tick snapshot)
#   * "reconcile actions"   -> how many actions the tick took
#   * "orb.create / orb.terminate / cordon / uncordon / resend_stop" -> the actions themselves
#   * "noop"                -> tick decided to do nothing
# Anything it does not recognise (warnings, errors, tracebacks) is passed through verbatim so you
# don't miss problems.
#
# Following is done by POLLING `aws logs filter-log-events` on an interval (POLL seconds), NOT by
# `aws logs tail --follow`. The latter is unreliable in some environments / aws-cli builds: it can
# block and emit nothing for the whole session (it silently falls back to a FilterLogEvents poll
# that never streams), which made this script print only "(idle) no reconcile seen yet" forever.
# Polling filter-log-events streams every tick reliably.
#
# Needs AWS creds with logs:FilterLogEvents (and logs:DescribeLogGroups for the existence check).
#
# Usage:  TAG=ec2orb1 REGION=eu-west-1 ./ec2_watch_controller.sh
#         SINCE=30m ./ec2_watch_controller.sh        # backfill 30 min of history, then follow
#         POLL=5    ./ec2_watch_controller.sh        # poll CloudWatch every 5s (default 5)
#         HEARTBEAT=15 ./ec2_watch_controller.sh      # reprint last status every 15s when idle
#         RAW=1     ./ec2_watch_controller.sh        # print raw JSON lines, no distilling
#
# When the grid is idle (no new controller ticks), every HEARTBEAT seconds the script reprints the
# last reconcile snapshot as a "(idle) LAST ..." line so the current state is always on screen.
set -euo pipefail

TAG="${TAG:?set TAG to the grid/project tag, e.g. ec2orb1}"
REGION="${REGION:-eu-west-1}"
LOG_GROUP="${LOG_GROUP:-/aws/lambda/capacity_controller-${TAG}}"
SINCE="${SINCE:-5m}"     # how much history to backfill before following (e.g. 30s, 5m, 1h)
POLL="${POLL:-5}"        # seconds between CloudWatch polls
RAW="${RAW:-0}"          # 1 = pass raw JSON straight through

# Exported so the embedded Python child (below) can read them from its environment.
export REGION LOG_GROUP SINCE POLL RAW
export HEARTBEAT="${HEARTBEAT:-30}"

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }

log "watching ${LOG_GROUP} (region ${REGION}, since ${SINCE}, poll ${POLL}s); Ctrl-C to stop"

if ! aws logs describe-log-groups --region "${REGION}" \
      --log-group-name-prefix "${LOG_GROUP}" \
      --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP}"; then
  log "WARNING: log group ${LOG_GROUP} not found yet (controller may not have run). Polling anyway."
fi

# Everything below is one Python process: it polls filter-log-events, dedups events, distills the
# structured JSON into compact lines, and emits an idle heartbeat between ticks. Fed via /dev/fd/3
# (not stdin) so nothing competes for the controlling terminal.
exec python3 -u /dev/fd/3 3<<'PY'
import json, os, subprocess, sys, time

REGION    = os.environ["REGION"]
LOG_GROUP = os.environ["LOG_GROUP"]
POLL      = float(os.environ.get("POLL", "5"))
HEARTBEAT = float(os.environ.get("HEARTBEAT", "30"))
RAW       = os.environ.get("RAW", "0") == "1"

# Parse SINCE ("30s", "5m", "1h", "2d", or a bare number = minutes) into seconds of backfill.
def parse_since(s):
    s = s.strip()
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    if s and s[-1] in units:
        return float(s[:-1] or "0") * units[s[-1]]
    return float(s) * 60  # bare number = minutes

def now_ms():
    return int(time.time() * 1000)

def now_hms():
    return time.strftime("%H:%M:%S", time.gmtime())

def iso_ms(ms):
    return time.strftime("%H:%M:%S", time.gmtime(ms / 1000))

# One filter-log-events page-walk from start_ms. Returns events sorted by timestamp.
def fetch(start_ms):
    events, token = [], None
    while True:
        cmd = ["aws", "logs", "filter-log-events", "--region", REGION,
               "--log-group-name", LOG_GROUP, "--start-time", str(start_ms),
               "--output", "json"]
        if token:
            cmd += ["--next-token", token]
        out = subprocess.run(cmd, capture_output=True, text=True)
        if out.returncode != 0:
            sys.stderr.write("filter-log-events failed: {}\n".format(out.stderr.strip()[:300]))
            return None
        data = json.loads(out.stdout or "{}")
        events.extend(data.get("events", []))
        token = data.get("nextToken")
        if not token:
            break
    events.sort(key=lambda e: e.get("timestamp", 0))
    return events

# ---- distilling -------------------------------------------------------------
last_reconcile = None  # the formatted "backlog=.. live=.." body, for idle reprints

def reconcile_body(d):
    return ("backlog={} live={} active={} draining={} desired={} "
            "(target/inst={} min={} max={} busy_known={})".format(
                d.get("backlog"), d.get("live"), d.get("active"), d.get("draining"),
                d.get("desired"), d.get("target_per_instance"),
                d.get("min_instances"), d.get("max_instances"), d.get("busy_known")))

def emit(ev):
    global last_reconcile
    ts_ms = ev.get("timestamp", 0)
    msg = (ev.get("message") or "").rstrip("\n")
    s = msg.strip()

    if RAW:
        print("{} {}".format(iso_ms(ts_ms), msg), flush=True)
        return

    if not (s.startswith("{") and s.endswith("}")):
        # Drop the Lambda platform framing (START/END/REPORT/XRAY/INIT) — pure noise per tick.
        # Keep everything else (boto warnings, tracebacks) verbatim so problems aren't hidden.
        head = s.split(" ", 1)[0]
        if head in ("START", "END", "REPORT", "INIT_START") or s.startswith("XRAY TraceId"):
            return
        if s:
            print("{} {}".format(iso_ms(ts_ms), s), flush=True)
        return
    try:
        d = json.loads(s)
    except Exception:
        print("{} {}".format(iso_ms(ts_ms), s), flush=True)
        return

    m = d.get("message", "")
    lvl = d.get("level", "INFO")
    t = (d.get("timestamp") or iso_ms(ts_ms))[:23]

    if m == "capacity reconcile":
        last_reconcile = reconcile_body(d)
        print("{} RECONCILE {}".format(t, last_reconcile), flush=True)
    elif m == "reconcile actions":
        print("{} ACTIONS  count={}".format(t, d.get("action_count")), flush=True)
    elif m == "noop":
        print("{} NOOP     live={} desired={}".format(t, d.get("live"), d.get("desired")), flush=True)
    elif m in ("orb.create", "orb.terminate", "cordon", "uncordon", "resend_stop"):
        ids = d.get("machine_ids")
        tail = " ids={}".format(ids) if ids else ""
        cnt = " count={}".format(d.get("count")) if d.get("count") is not None else ""
        print("{}  -> {}{}{}".format(t, m.upper(), cnt, tail), flush=True)
    elif lvl in ("WARNING", "ERROR", "CRITICAL"):
        print("{} {:<8} {}".format(t, lvl, m), flush=True)
    else:
        # other INFO/DEBUG lines: show message only, keep it quiet
        print("{} {:<8} {}".format(t, lvl, m), flush=True)

# ---- follow loop ------------------------------------------------------------
# Poll filter-log-events on an interval. Dedup via eventId: after each poll advance start_ms to the
# newest timestamp seen and keep only the eventIds at that exact ms (the only ones an inclusive
# re-query can return), so events are never printed twice and never skipped at a poll boundary.
start_ms = now_ms() - int(parse_since(os.environ.get("SINCE", "5m")) * 1000)
seen = set()
last_output = time.time()

while True:
    events = fetch(start_ms)
    if events is None:
        time.sleep(POLL)
        continue

    fresh = [e for e in events if e.get("eventId") not in seen]
    for e in fresh:
        emit(e)
    if fresh:
        last_output = time.time()

    if events:
        max_ts = max(e.get("timestamp", 0) for e in events)
        seen = {e.get("eventId") for e in events if e.get("timestamp", 0) == max_ts}
        start_ms = max_ts

    # Idle heartbeat: nothing new for HEARTBEAT seconds -> reprint current state (distilled mode).
    if not RAW and (time.time() - last_output) >= HEARTBEAT:
        if last_reconcile is not None:
            print("{} (idle) LAST     {}".format(now_hms(), last_reconcile), flush=True)
        else:
            print("{} (idle) no reconcile seen yet (waiting for next controller tick)".format(now_hms()), flush=True)
        last_output = time.time()

    time.sleep(POLL)
PY
