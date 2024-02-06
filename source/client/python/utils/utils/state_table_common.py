# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


TASK_STATE_CANCELLED = "cancelled"
TASK_STATE_PENDING = "pending"
TASK_STATE_FAILED = "failed"
TASK_STATE_FINISHED = "finished"
TASK_STATE_PROCESSING = "processing"


class StateTableException(Exception):
    def __init__(
        self,
        original_message,
        supplied_message,
        caused_by_throttling=False,
        caused_by_condition=False,
    ):
        super().__init__(original_message)

        self.caused_by_throttling = caused_by_throttling
        self.caused_by_condition = caused_by_condition
        self.original_message = original_message
        self.supplied_message = supplied_message

    def __str__(self):
        return f"Original Message: {self.original_message}, supplied_message: {self.supplied_message}"
