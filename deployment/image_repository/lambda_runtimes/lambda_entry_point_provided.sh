#! /bin/bash

# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

trap  'echo SIGTERM' SIGTERM
trap  'echo SIGINT' SIGINT
trap  'echo SIGHUP' SIGHUP
trap  'echo SIGQUIT' SIGQUIT
trap  'echo SIGALRM' SIGALRM

if [ $# -ne 1 ]; then
  echo "entrypoint requires the handler name to be the first argument" 1>&2
  exit 142
fi
export _HANDLER="$1"

RUNTIME_ENTRYPOINT=/var/task/bootstrap
/usr/local/bin/aws-lambda-rie $RUNTIME_ENTRYPOINT