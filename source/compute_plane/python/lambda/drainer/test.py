# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import boto3
import logging
import os.path


logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

region = os.environ["AWS_REGION"]

ecs = boto3.client("ecs", region_name=region)
ec2 = boto3.client("ec2", region_name=region)
asg = boto3.client("autoscaling", region_name=region)


def check_container_instance_status(cluster, instance_id, status):
    response = ecs.list_container_instances(
        cluster=cluster, filter=f"ec2InstanceId == {instance_id}", status=status
    )
    if response:
        return response["containerInstanceArns"][0].split("/")[-1]
    else:
        return ""


def abandon_lifecycle_action(
    asg_client, auto_scaling_group_name, lifecycle_hook_name, instance_id
):
    """Completes the lifecycle action with the ABANDON result, which stops any remaining actions,
    such as other lifecycle hooks.
    """
    asg_client.complete_lifecycle_action(
        LifecycleHookName=lifecycle_hook_name,
        AutoScalingGroupName=auto_scaling_group_name,
        LifecycleActionResult="ABANDON",
        InstanceId=instance_id,
    )


def _lambda_handler(env, event):
    cluster_name = env["cluster_name"]

    lifecycle_hook_name = event["detail"]["LifecycleHookName"]
    auto_scaling_group_name = event["detail"]["AutoScalingGroupName"]

    instance_id = event["detail"]["EC2InstanceId"]
    logger.info("Instance ID: " + instance_id)
    instance = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"][0][
        "Instances"
    ][0]

    node_name = instance["PrivateDnsName"]
    logger.info("Node name: " + node_name)

    # Configure
    try:
        is_container_active = check_container_instance_status(
            cluster_name, instance_id, "ACTIVE"
        )
        if is_container_active:
            logger.info(f"Container Instance is active {is_container_active}")
            update_response = ecs.update_container_instances_state(
                cluster=cluster_name,
                containerInstances=[is_container_active],
                status="DRAINING",
            )
            if update_response["failures"]:
                logger.error(f'reason: {update_response["failures"][0]["reason"]}')
                logger.error(f'detail: {update_response["failures"][0]["detail"]}')
                abandon_lifecycle_action(
                    asg, auto_scaling_group_name, lifecycle_hook_name, instance_id
                )

        is_container_draining = check_container_instance_status(
            cluster_name, instance_id, "DRAINING"
        )
        if is_container_draining:
            logger.info(f"Container Instance is draining {is_container_draining}")
            # update_response = ecs.update_container_instances_state(cluster=cluster_name,containerInstances=[is_container_active],status="DRAINING")
            response_stopped_tasks = ecs.list_tasks(
                cluster=cluster_name,
                containerInstance=is_container_draining,
                desiredStatus="STOPPED",
            )

            if response_stopped_tasks["taskArns"]:
                waiter = ecs.get_waiter("tasks_stopped")
                waiter.wait(cluster="default", tasks=response_stopped_tasks["taskArns"])

        logger.info("all task terminated")
        asg.complete_lifecycle_action(
            LifecycleHookName=lifecycle_hook_name,
            AutoScalingGroupName=auto_scaling_group_name,
            LifecycleActionResult="CONTINUE",
            InstanceId=instance_id,
        )
        logger.info("lifecycling hooks over")
    except Exception:
        logger.exception(
            "There was an error removing the pods from the node {}".format(node_name)
        )
        abandon_lifecycle_action(
            asg, auto_scaling_group_name, lifecycle_hook_name, instance_id
        )


def lambda_handler(event, context):
    env = {"cluster_name": os.environ.get("CLUSTER_NAME")}
    return _lambda_handler(env, event)


if __name__ == "__main__":
    event = {
        "detail": {
            "LifecycleHookName": "test",
            "AutoScalingGroupName": "test",
            "EC2InstanceId": "i-0d01186eb82e7e8d5",
        }
    }
    lambda_handler(event, "test")
