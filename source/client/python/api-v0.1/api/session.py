# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import time
import logging
import json
import base64
import traceback

logging.basicConfig(format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
                    datefmt='%H:%M:%S', level=logging.INFO)

def get_time_now_ms():
    return int(round(time.time() * 1000))

class GridSession:

    def __init__(self, htc_grid_connector, session_id, callback):

        self.htc_grid_connector = htc_grid_connector
        self.session_id = session_id

        self.submitted_task_ids = []
        self.submitted_tasks_count = 0

        self.received_task_ids = {}

        self.callback = callback
        self.time_send_was_invoked_ms = 0

        self.in_out_manager = htc_grid_connector.in_out_manager

        # TODO: update constants
        self.TASK_TIMEOUT_SEC = 3600
        self.RETRY_COUNT = 5

    def send(self, tasks):  # returns TaskID[]
        """This method submits tasks to the HTC grid

        Args:
          tasks_list (list): the list of tasks to execute on the grid

        Returns:
          dict: the response from the endpoint of the HTC grid

        """
        try:
            self.time_send_was_invoked_ms = get_time_now_ms()

            # <1.> Generate Task IDs based on the Session ID and the index of each task.
            logging.info(f"Sending {len(tasks)} tasks for session {self.session_id}")
            new_task_ids = []

            for i, t in enumerate(tasks):

                task_index = i + self.submitted_tasks_count
                task_id = self.__make_task_id_from_session_id(self.session_id, task_index)
                new_task_ids.append(task_id)

            # <2.> Upload tasks into the Data Plane
            serialized_tasks = []

            for i, t in enumerate(tasks):

                data = json.dumps(t).encode('utf-8')

                b64data = base64.b64encode(data)

                self.in_out_manager.put_input_from_bytes(new_task_ids[i], b64data)

                serialized_tasks.append(b64data)

            # <3.> Construct submit_tasks Lambda invocation payload that will be passed via Data Plane
            lambda_data_plane_payload = self.__construct_submit_tasks_lambda_invocation_payload(new_task_ids, serialized_tasks)
            logging.info(f"lambda_data_plane_payload: {lambda_data_plane_payload}")

            # <4.> Invoke Submit Tasks Lambda in Control Plane
            json_response = self.htc_grid_connector.submit(lambda_data_plane_payload)
            logging.info(f"Submit Tasks Lambda json_response = {json_response}")

            # <5.> Bookkeeping
            # TODO: check if submission is successful
            self.submitted_tasks_count += len(tasks)
            self.submitted_task_ids += new_task_ids

            return json_response
        except Exception as e:
            print("Unexpected error in sending {} [{}]".format(
            e, traceback.format_exc()))


    def __construct_submit_tasks_lambda_invocation_payload(self, new_task_ids, serialized_tasks):
        lambda_payload = {
            "session_id": self.session_id,
            "scheduler_data": {
                "task_timeout_sec": self.TASK_TIMEOUT_SEC,
                "retry_count": self.RETRY_COUNT,
                "tstamp_api_grid_connector_ms": 0,
                "tstamp_agent_read_from_sqs_ms": 0
            },
            "stats": {
                "stage1_grid_api_01_task_creation_tstmp": {"label": " ", "tstmp": self.time_send_was_invoked_ms},
                "stage1_grid_api_02_task_submission_tstmp": {"label": "upload_data_to_storage",
                                                             "tstmp": get_time_now_ms()},

                "stage2_sbmtlmba_01_invocation_tstmp": {"label": "grid_api_2_lambda_ms", "tstmp": 0},
                "stage2_sbmtlmba_02_before_batch_write_tstmp": {"label": "task_construction_ms", "tstmp": 0},
                # "stage2_sbmtlmba_03_invocation_over_tstmp":    {"label": "dynamo_db_submit_ms", "tstmp" : 0},

                "stage3_agent_01_task_acquired_sqs_tstmp": {"label": "sqs_queuing_time_ms", "tstmp": 0},
                "stage3_agent_02_task_acquired_ddb_tstmp": {"label": "ddb_task_claiming_time_ms", "tstmp": 0},

                "stage4_agent_01_user_code_finished_tstmp": {"label": "user_code_exec_time_ms", "tstmp": 0},
                "stage4_agent_02_S3_stdout_delivered_tstmp": {"label": "S3_stdout_upload_time_ms", "tstmp": 0}
            },
            "tasks_list": {
                "tasks": new_task_ids if self.htc_grid_connector.is_task_input_passed_via_external_storage() == 1 else serialized_tasks
            }
        }

        return lambda_payload


    def check_tasks_states(self):
        print(f"Session: Checking status {self.session_id}, submitted: {len(self.submitted_task_ids)}, received: {len(self.received_task_ids)}")

        try:

            res = self.htc_grid_connector.get_results(self.session_id)

            # Process only task_ids that we haven't seen before.
            for t in res["finished"]:
                if t not in self.received_task_ids:

                    self.received_task_ids[t] = True

                    stdout_bytes = self.in_out_manager.get_output_to_bytes(t)
                    logging.info("output_bytes: {}".format(stdout_bytes))

                    output = base64.b64decode(stdout_bytes).decode('utf-8')
                    logging.info("output_obj: {}".format(output))

                    # TODO: check if success or failure

                    self.callback(output)

        except Exception as e:
            print("Unexpected error in check_tasks_states {} [{}]".format(
            e, traceback.format_exc()))


    def wait_for_completion(self, timeout_ms=0, complete_and_close=False):
        time_start_ms = get_time_now_ms()

        while len(self.received_task_ids) < len(self.submitted_task_ids):
            print("Session: Main thread sleeps for results")

            time.sleep(1.0)

            if 0 < timeout_ms < get_time_now_ms() - time_start_ms:
                logging.warning(f"{__name__} timeoud after {timeout_ms}")
                break

        if len(self.received_task_ids) == len(self.submitted_task_ids):
            # Unless more tasks will be submitted within this session
            # Session can be considered completed.
            if complete_and_close:
                self.close()

    def cancel(self):
        self.htc_grid_connector.cancel_sessions([self.session_id])

    def close(self):
        self.htc_grid_connector.diregister_session(session=self)


    def __make_task_id_from_session_id(self, session_id, task_index):
        return f"{session_id}_{task_index}"

    def __hash__(self):
        return self.session_id

    def __eq__(self, other):
        if not isinstance(other, type(self)): return NotImplemented
        return self.session_id == other.session_id