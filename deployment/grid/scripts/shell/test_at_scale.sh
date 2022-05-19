#!/bin/bash
set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

period="${1:-60}"
prefix="${2:-test-$$}"
target="${3:-10}"
echo $period

echo "starting pods monitoring"
$SCRIPT_DIR/count_pods.sh $period $prefix-pods.csv > /dev/null &
PID_POD_COUNT=$!
echo "pods monitoring started, data written in $prefix-pods.csv"

echo "starting nodes monitoring"
$SCRIPT_DIR/count_nodes.sh $period $prefix-nodes.csv > /dev/null &
PID_NODES_COUNT=$!
echo "nodes monitoring started, data written in $prefix-nodes.csv"

echo "starting CPU monitoring"
$SCRIPT_DIR/count_cpu.sh $period $prefix-cpu.csv > /dev/null &
PID_CPU_COUNT=$!
echo "CPU monitoring started, data written in $prefix-cpu.csv"
patch=$(printf '{"spec":{"minReplicas":%s,"maxReplicas":%s}}' $target $target)

echo " PACTH $patch PACTH"
kubectl patch hpa htc-agent-scaler --patch $patch

tail -f $prefix-pods.csv  | while read line
do
  current_running_pods=$(echo $line | awk '{print $7}')
  echo "current running pods $current_running_pods target $target"
  if [ $current_running_pods == $target ]
  then
    echo "successfully reach  target state => scaling in"
    break
  fi
done

pause=$(echo "3*$period" | bc)
echo "sleeping some time ($pause s) to gather data point"
sleep $pause
kubectl patch hpa htc-agent-scaler --patch '{"spec":{"minReplicas":1,"maxReplicas":1}}'

tail -f $prefix-pods.csv  | while read line
do
  current_running_pods=$(echo $line | awk '{print $7}')
  echo "current running pods $current_running_pods target 1"
  if [ $current_running_pods == 1 ]
  then
    echo "successfully reach  target state => exit"
    break
  fi
done

kill -9 $PID_POD_COUNT
kill -9 $PID_NODES_COUNT
kill -9 $PID_CPU_COUNT
