# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
import base64
import json
import time
import os
import uuid
import boto3
import botocore
import requests
import logging

from api.in_out_manager import in_out_manager
from utils.state_table_common import TASK_STATE_FINISHED
from warrant_lite import WarrantLite
from apscheduler.schedulers.background import BackgroundScheduler

if os.environ.get("INTRA_VPC"):
    from privateapi import Configuration, ApiClient, ApiException
    from privateapi.api import default_api
else:
    from publicapi import Configuration, ApiClient, ApiException
    from publicapi.api import default_api

URLOPEN_LAMBDA_INVOKE_TIMEOUT_SEC = 120  # TODO Catch timout exception
TASK_TIMEOUT_SEC = 3600
RETRY_COUNT = 5
TOKEK_REFRESH_INTERVAL_SEC = 200

working_path = os.path.dirname(os.path.realpath(__file__))
logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(filename)s - %(funcName)s  - %(lineno)d - %(message)s",
    datefmt="%H:%M:%S",
    level=logging.INFO,
)
logging.info("Init AWS Grid Connector")


# where we read these settings, they must be configurable from clients code


def get_safe_session_id():
    """
    This function returns a safe uuid.

    Returns:
      str: a safe session id

    """
    return str(uuid.uuid1())


class AWSConnector:
    """This class implements the API for managing jobs"""

    in_out_manager = None

    def __init__(self):
        self.in_out_manager = None
        self.__api_gateway_endpoint = ""
        self.__public_api_gateway_endpoint = ""
        self.__private_api_gateway_endpoint = ""
        self.__api_key = ""
        self.__user_pool_id = ""
        self.__user_pool_client_id = ""
        self.__username = ""
        self.__password = ""  # nosec B105
        self.__dynamodb_results_pull_intervall = ""
        self.__task_input_passed_via_external_storage = ""
        self.__user_token_id = None
        self.__user_refresh_token = None
        self.__cognito_client = None
        self.__s3_resource = None
        self.__intra_vpc = False
        self.__authorization_headers = {}
        self.__scheduler = None
        self.__configuration = None
        self.__api_client = None
        self.__default_api_client = None

    def refresh(self):
        """This method refreshes an expired JWT. The new JWT  overrides the existing one"""
        logging.info("starting cognito refresh")
        try:
            tokens = self.__cognito_client.initiate_auth(
                ClientId=self.__user_pool_client_id,
                AuthFlow="REFRESH_TOKEN_AUTH",
                AuthParameters={
                    "REFRESH_TOKEN": self.__user_refresh_token,
                },
            )
            self.__user_token_id = tokens["AuthenticationResult"]["IdToken"]
            logging.info("successfully cognito token refreshed")
        except botocore.exceptions.ClientError:
            logging.exception("Failed while refreshing cognito token")

    def init(
        self,
        agent_config_data,
        username="",
        password="",
        cognitoidp_client=None,
        s3_custom_resource=None,  # nosec B107
        redis_custom_connection=None,
    ):
        """
        Args:
            redis_custom_connection(object): override default redis connection
            s3_custom_resource(object): override default s3 resource
            cognitoidp_client(object):  override default s3 cognito client
            agent_config_data (dict): the HTC grid runtime configuration for the connector
            username (string): the username used for authentication when the client run outside of a VPC
            password (string): the password used for authentication when the client run outside of a VPC

        Returns:
            Nothing
        """
        logging.info("AGENT:", agent_config_data)
        self.in_out_manager = in_out_manager(
            agent_config_data["grid_storage_service"],
            agent_config_data["s3_bucket"],
            agent_config_data["redis_url"],
            agent_config_data["redis_password"],
            s3_kms_key_id=agent_config_data["s3_kms_key_id"],
            s3_region=agent_config_data["region"],
            s3_custom_resource=s3_custom_resource,
            redis_custom_connection=redis_custom_connection,
        )
        self.__api_gateway_endpoint = ""
        self.__public_api_gateway_endpoint = agent_config_data["public_api_gateway_url"]
        self.__private_api_gateway_endpoint = agent_config_data[
            "private_api_gateway_url"
        ]
        self.__api_key = agent_config_data["api_gateway_key"]
        self.__user_pool_id = agent_config_data["user_pool_id"]
        self.__user_pool_client_id = agent_config_data["cognito_userpool_client_id"]
        self.__username = username
        self.__password = password
        self.__dynamodb_results_pull_intervall = agent_config_data[
            "dynamodb_results_pull_interval_sec"
        ]
        self.__task_input_passed_via_external_storage = agent_config_data[
            "task_input_passed_via_external_storage"
        ]
        self.__user_token_id = None
        if cognitoidp_client is None:
            self.__cognito_client = boto3.client(
                "cognito-idp", region_name=agent_config_data["region"]
            )
        else:
            self.__cognito_client = cognitoidp_client
        self.__intra_vpc = False
        logging.warning("Check Private Mode")
        if os.environ.get("INTRA_VPC"):
            logging.warning("The client is running inside the VPC")
            self.__intra_vpc = True
        self.__authorization_headers = {}
        if self.__intra_vpc:
            self.__api_gateway_endpoint = self.__private_api_gateway_endpoint
            self.__configuration = Configuration(host=self.__api_gateway_endpoint)
            self.__configuration.api_key["api_key"] = self.__api_key
        else:
            self.__api_gateway_endpoint = self.__public_api_gateway_endpoint
            self.__configuration = Configuration(host=self.__api_gateway_endpoint)

        self.__scheduler = BackgroundScheduler()
        logging.info("LAMBDA_ENDPOINT_URL:{}".format(self.__api_gateway_endpoint))
        logging.info(
            "dynamodb_results_pull_interval_sec:{}".format(
                self.__dynamodb_results_pull_intervall
            )
        )
        logging.info(
            "task_input_passed_via_external_storage:{}".format(
                self.__task_input_passed_via_external_storage
            )
        )
        logging.info(
            "grid_storage_service:{}".format(agent_config_data["grid_storage_service"])
        )
        logging.info("AWSConnector Initialized")
        logging.info("init with {}".format(self.__user_pool_client_id))
        logging.info("init with {}".format(self.__cognito_client))

    def authenticate(self):
        """This method authenticates against a Cognito User Pool. The JWT is stored as attribute of the class"""
        logging.info("authenticate with {}".format(self.__user_pool_client_id))
        if not self.__intra_vpc:
            try:
                aws = WarrantLite(
                    username=self.__username,
                    password=self.__password,
                    pool_id=self.__user_pool_id,
                    client_id=self.__user_pool_client_id,
                    client=self.__cognito_client,
                )
                tokens = aws.authenticate_user()
                self.__user_token_id = tokens["AuthenticationResult"]["IdToken"]
                self.__user_refresh_token = tokens["AuthenticationResult"][
                    "RefreshToken"
                ]
                logging.info(
                    "authentication successful for user {}".format(self.__user_token_id)
                )
                self.__scheduler.add_job(
                    AWSConnector.refresh,
                    "interval",
                    seconds=TOKEK_REFRESH_INTERVAL_SEC,
                    args=[self],
                )
                self.__scheduler.start()
            except Exception as e:
                logging.error("Cannot authenticate user {}".format(self.__username))
                raise e
            self.__configuration.api_key[
                "htc_cognito_authorizer"
            ] = self.__user_token_id

    def generate_user_task_json(self, tasks_list=None):
        """this methods returns from a list of tasks, a tasks object that can be submitted to the grid

        Args:
          tasks_list (list): the list of tasks to submit (Default value = [])

        Returns:
          dict: an object that can be submitted to the grid

        """

        time_start_ms = int(round(time.time() * 1000))

        session_id = "None"

        binary_tasks_list = []

        if self.__task_input_passed_via_external_storage == 1:
            session_id = get_safe_session_id()
            logging.info("Local session id: {}".format(session_id))

            for i, data in enumerate(tasks_list):
                task_id = session_id + "_" + str(i)

                data = json.dumps(data).encode("utf-8")

                b64data = base64.b64encode(data)

                self.in_out_manager.put_input_from_bytes(task_id, b64data)

                # We are no longer passing the actual task definition
                binary_tasks_list.append(task_id)

        # creation message with tasks_list
        user_task_json = {
            "session_id": session_id,
            "scheduler_data": {
                "task_timeout_sec": TASK_TIMEOUT_SEC,
                "retry_count": RETRY_COUNT,
                "tstamp_api_grid_connector_ms": 0,
                "tstamp_agent_read_from_sqs_ms": 0,
            },
            "stats": {
                "stage1_grid_api_01_task_creation_tstmp": {
                    "label": " ",
                    "tstmp": time_start_ms,
                },
                "stage1_grid_api_02_task_submission_tstmp": {
                    "label": "upload_data_to_storage",
                    "tstmp": int(round(time.time() * 1000)),
                },
                "stage2_sbmtlmba_01_invocation_tstmp": {
                    "label": "grid_api_2_lambda_ms",
                    "tstmp": 0,
                },
                "stage2_sbmtlmba_02_before_batch_write_tstmp": {
                    "label": "task_construction_ms",
                    "tstmp": 0,
                },
                # "stage2_sbmtlmba_03_invocation_over_tstmp":    {"label": "dynamo_db_submit_ms", "tstmp" : 0},
                "stage3_agent_01_task_acquired_sqs_tstmp": {
                    "label": "sqs_queuing_time_ms",
                    "tstmp": 0,
                },
                "stage3_agent_02_task_acquired_ddb_tstmp": {
                    "label": "ddb_task_claiming_time_ms",
                    "tstmp": 0,
                },
                "stage4_agent_01_user_code_finished_tstmp": {
                    "label": "user_code_exec_time_ms",
                    "tstmp": 0,
                },
                "stage4_agent_02_S3_stdout_delivered_tstmp": {
                    "label": "S3_stdout_upload_time_ms",
                    "tstmp": 0,
                },
            },
            "tasks_list": {
                "tasks": binary_tasks_list
                if self.__task_input_passed_via_external_storage == 1
                else tasks_list
            },
        }

        return user_task_json

    # TODO implements this method
    def cancel(self, session_id):
        """

        Args:
            session_id:

        Returns:

        """
        pass

    # TODO raise exception when the  task list is above a given threshold
    # TODO create a response object instead of  dictionary
    def send(self, tasks_list):  # returns TaskID[]
        """This method submits tasks to the HTC grid

        Args:
          tasks_list (list): the list of tasks to execute on the grid

        Returns:
          dict: the response from the endpoint of the HTC grid

        """
        logging.info("Init send {} tasks".format(len(tasks_list)))
        user_task_json_request = self.generate_user_task_json(tasks_list)
        logging.info("user_task_json_request: {}".format(user_task_json_request))
        # print(user_task_json_request)

        json_response = self.submit(user_task_json_request)
        logging.info("json_response = {}".format(json_response))
        return json_response

    def get_results(self, submission_response: dict, timeout_sec=0):
        """This methods get the result associated to a specific submission

        Args:
          submission_response (list): arrays storing the ids of the submission to check
          timeout_sec (int): time after the connection between the client of the HTC grid is killed (Default value = 0)

        Returns:
          str: the result of the submission

        """
        logging.info("Init get_results")
        start_time = time.time()

        session_tasks_count: int = len(submission_response["task_ids"])
        logging.info("session_tasks_count: {}".format(session_tasks_count))
        while True:
            session_results = self.invoke_get_results_lambda(
                {"session_id": submission_response["session_id"]}
            )
            logging.info("session_results: {}".format(session_results))
            # print("session_results: {}".format(session_results))

            if (
                "metadata" in session_results
                and session_results["metadata"]["tasks_in_response"]
                == session_tasks_count
            ):
                break
            elif 0 < timeout_sec < time.time() - start_time:
                # We have timed out!
                logging.error("Get Results Timed Out")
                break
            time.sleep(self.__dynamodb_results_pull_intervall)

        for i, completed_task in enumerate(session_results[TASK_STATE_FINISHED]):
            stdout_bytes = self.in_out_manager.get_output_to_bytes(completed_task)
            # print("stdout_bytes: {}".format(stdout_bytes))

            output = base64.b64decode(stdout_bytes).decode("utf-8")

            session_results[TASK_STATE_FINISHED + "_OUTPUT"][i] = output

        logging.info("Finish get_results")
        return session_results

    # TODO this should be private
    def submit(self, jobs):
        """This method submits jobs to the scheduler through API Gateway

        Args:
          jobs (dict): an array of jobs to submitted.

        Returns:
          dict: the submission ids of the jobs

        """
        logging.info("Start submit")
        # logging.warning("jobs = {}".format(jobs))
        raw_response: requests.Response
        if self.__task_input_passed_via_external_storage == 1:
            submission_payload_bytes = base64.urlsafe_b64encode(
                json.dumps(jobs).encode("utf-8")
            )
            session_id = jobs["session_id"]
            if session_id is None or session_id == "None":
                raise Exception("Invalid configuration : session id must be set")
            self.in_out_manager.put_payload_from_bytes(
                session_id, submission_payload_bytes
            )
        with ApiClient(self.__configuration) as api_client:
            # Create an instance of the API class
            api_instance = default_api.DefaultApi(api_client)
            try:
                raw_response = api_instance.submit_post(str(session_id))
                logging.warning(raw_response)
            except ApiException as e:
                logging.error("Exception when calling DefaultApi->ca_post: %s\n" % e)
                raise e

        logging.info("Finish submit")
        return raw_response

    # TODO make it private
    def invoke_get_results_lambda(self, session_id):
        """This method retrieve through API Gateway the result of the sessions
        Expected output format:
        {
            "finished": ["task_id_2", "task_id_0", "task_id_6"],
            "finished_OUTPUT": ["read_from_REDIS", "read_from_REDIS", "read_from_REDIS"],
            "cancelled": ["task_id_3", "task_id_4", "task_id_5"],
            "cancelled_OUTPUT": ["read_from_REDIS", "read_from_REDIS", "read_from_REDIS"],
            "metadata": {
                "tasks_in_response": 10
            }
        }
        The output can also contain section for failed task if there are such tasks.

        Args:
          session_id (dict): the session ID of the job to check

        Returns:
          dict: the result of the job

        """
        logging.info("Init get_results")
        submission_payload_string = base64.urlsafe_b64encode(
            json.dumps(session_id).encode("utf-8")
        ).decode("utf-8")
        with ApiClient(self.__configuration) as api_client:
            # Create an instance of the API class
            api_instance = default_api.DefaultApi(api_client)
            try:
                raw_response = api_instance.result_get(str(submission_payload_string))
                logging.warning(raw_response)
            except ApiException as e:
                logging.error("Exception when calling DefaultApi->result_get: %s\n" % e)
                raise e

        return raw_response

    def cancel_sessions(self, session_ids):
        """
        This method invokes cancel tasks lambda through API Gateway for a list of sessions

        Expected output on success is dictionary containing entries for eavery session.
        Each subsection contains counters indicating how many tasks were moved from their previous state to cancelled state
        {
            "62d2beea-6911-11eb-b5fb-060372291b89-part002": {
                "cancelled_retrying": 0,
                "cancelled_pending": 5,
                "cancelled_processing": 1,
                "total_cancelled_tasks": 6
            },
            "6398f57e-6911-11eb-b5fb-060372291b89-part024": {
                "cancelled_retrying": 0,
                "cancelled_pending": 9,
                "cancelled_processing": 0,
                "total_cancelled_tasks": 9
            }
        }

        Args:
            session_ids(list): a list of sessions to be cancelled.

        Returns:
            dict: containing number of cancelled tasks for each session in the list

        """

        logging.info("Init cancel session")

        cancellation_request = {"session_ids_to_cancel": session_ids}
        submission_payload_string = base64.urlsafe_b64encode(
            json.dumps(cancellation_request).encode("utf-8")
        ).decode("utf-8")
        with ApiClient(self.__configuration) as api_client:
            # Create an instance of the API class
            api_instance = default_api.DefaultApi(api_client)
            try:
                raw_response = api_instance.cancel_post(str(submission_payload_string))
                logging.warning(raw_response)
            except ApiException as e:
                logging.error(
                    "Exception when calling DefaultApi->cancel_post: %s\n" % e
                )
                raise e

        logging.info("Finish cancel session")
        return raw_response
