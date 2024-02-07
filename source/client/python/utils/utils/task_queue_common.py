# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


class TaskQueueException(Exception):
    def __init__(self, original_exception, supplied_message, traceback_msg):
        super().__init__(original_exception)
        self.original_message = str(original_exception)
        self.supplied_message = supplied_message
        self.traceback_msg = traceback_msg

    def get_original_exception(self):
        return self.get_original_exception

    def get_supplied_message(self):
        return self.supplied_message

    def get_traceback_message(self):
        return self.traceback_msg

    def __str__(self):
        return f"TaskQueueException: Original Message: {self.original_message}, supplied_message: {self.supplied_message}"
