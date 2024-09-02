#!/bin/sh

# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

# Initialization - load function handler
#source $LAMBDA_TASK_ROOT/"$(echo $_HANDLER | cut -d. -f1).sh"
echo "Handler $_HANDLER"
# Processing
while true
do
  HEADERS="$(mktemp)"
  # Get an event. The HTTP request will block until one is received
  EVENT_DATA=$(curl -sS -LD "$HEADERS" -X GET "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next")
  echo "Event Data : [$EVENT_DATA]"
  echo "Event HEADERS : [$HEADERS]"
  # Extract request ID by scraping response headers received above
  REQUEST_ID=$(grep -Fi Lambda-Runtime-Aws-Request-Id "$HEADERS" | tr -d '[:space:]' | cut -d: -f2)
  ARG_0=$(echo $EVENT_DATA | jq -r '.worker_arguments[0]')
  ARG_1=$(echo $EVENT_DATA | jq -r '.worker_arguments[1]')
  ARG_2=$(echo $EVENT_DATA | jq -r '.worker_arguments[2]')
  # Execute the handler function from the script
  # RESPONSE=$($(echo "$_HANDLER" | cut -d. -f2) "$EVENT_DATA")
  if ! RESPONSE=$($LAMBDA_TASK_ROOT/mock_compute_engine $ARG_0 $ARG_1 $ARG_2)
  then
    echo "No response"
    curl -X POST "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/$REQUEST_ID/response"  -d "BOOTSTRAP ERROR:$RESPONSE"
  fi
  echo "Response : $RESPONSE"
  # Send the response
  curl -X POST "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/$REQUEST_ID/response"  -d "$RESPONSE"
done