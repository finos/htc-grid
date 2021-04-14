#!/usr/bin/bash

# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

while true; do 
    T1=`date`
    VAL=`kubectl get po | grep Running | wc -l`
    T2=`date`
    echo "$T1          PODS:[ $VAL ]"
    sleep 60
done