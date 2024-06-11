#!/usr/bin/bash

# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

readonly NAMESPACE="${1:-default}"
readonly JOB_NAME="${2:-portfolio-pricing-book}"

printf '=%.0s' {1..145}; printf '\n'
printf "| %20s | %27s | %24s | %30s | %28s |\n" "Date" "HPA (Desired/Max [Targets])" "Deployment (Ready/Total)" "Nodes (Ready [NotReady/Total])" "Job (Completions [Duration])"
printf '=%.0s' {1..145}; printf '\n'

while true; do 
    T1=`date --utc +%FT%TZ`
    HPA=`kubectl -n $NAMESPACE get hpa keda-hpa-htc-agent-scaling-metrics --no-headers 2>/dev/null | awk '{printf "%s/%s [%s]", $7, $6, $3}'`
    DEP=`kubectl -n $NAMESPACE get deployment htc-agent --no-headers 2>/dev/null | awk '{print $2}'`
    NODES_ALL=`kubectl get nodes --no-headers`
    NODES_COUNT=`echo "$NODES_ALL" | wc -l | tr -d '\n'`
    NODES_READY=`echo "$NODES_ALL" | grep -v 'Not' | grep -c 'Ready' || true`
    NODES_NOTREADY=`echo "$NODES_ALL" | grep -c 'NotReady' || true`
    NODES="$NODES_READY [$NODES_NOTREADY/$NODES_COUNT]"
    JOB=`kubectl -n $NAMESPACE get job $JOB_NAME --no-headers 2>/dev/null | awk '{printf "%s [%s]", $2, $3}'`
    printf "| %20s | %27s | %24s | %30s | %28s |\n" "$T1" "$HPA" "$DEP" "$NODES" "$JOB"
    sleep 30
done
