#!/bin/bash

# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

period="${1:-60}"
output_file="${2:-cpu.csv}"
echo $period
echo "dow month day hour timezone year cpu" > $output_file
while true; do 
    T1=`date`
    VAL=`kubectl get nodes -o jsonpath='{range .items[?(@.status.conditions[*].reason contains "KubeletReady")]}{.status.capacity.cpu}{"\n"}{end}' | awk '{n += $1}; END{print n}'`
    T2=`date`
    echo "$T1          CPU:[ $VAL ]"
    echo "$T1 $VAL" >> $output_file
    sleep $period
done

