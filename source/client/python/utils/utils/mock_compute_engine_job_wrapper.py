# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/


class MockComputeEngineJobWrapper:
    def __init__(self, worker_arguments, n_tasks_per_job, payload_options):
        self.worker_arguments = worker_arguments
        self.payload_options = payload_options
        self.n_tasks_per_job = n_tasks_per_job

        self.expected_output_string = ""

    def form_dict_task_definition(self):
        worker_arguments = self.worker_arguments.split(" ")

        task_definition = {"worker_arguments": worker_arguments}

        if int(worker_arguments[0]) >= 0:
            self.expected_output_string = worker_arguments[0]
        elif worker_arguments[-1] in self.computational_results_dic:
            self.expected_output_string = self.computational_results_dic[
                worker_arguments[-1]
            ]
        else:
            raise Exception(
                "Can not verify result as computation is not known for input '{}'".format(
                    self.worker_arguments
                )
            )

        return task_definition

    def generate_binary_job(self):
        task_dict = self.form_dict_task_definition()

        tasks = []

        for i in range(0, self.n_tasks_per_job):
            tasks.append(task_dict)

        return tasks

    def verify_results(self, stdout):
        if stdout.rstrip() != self.expected_output_string:
            return False, "Expected: [{}] != Received [{}]".format(
                self.expected_output_string, stdout.rstrip()
            )
        return True, ""
