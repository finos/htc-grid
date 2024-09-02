# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

from api.connector import AWSConnector

from utils.mock_compute_engine_job_wrapper import MockComputeEngineJobWrapper as JW

import timeit
import argparse
import time
import traceback
import random
import logging
import sys
import json
import os

# TODO We are not using Queue as it is too small to hold entire batch and would requre an online producer
# so falling back to simple locking + atomic counter
from multiprocessing import Process


# TODO: check this, only for debug ?? add to PYTHONPATH dependencies of another modules
# perf_tracker = PerformanceTrackerInitializer(os.environ["METRICS_ARE_ENABLED"], os.environ["metrics_submit_tasks_lambda_connection_string"])

# If sending failed for any reason we will try to resubmit.
MAX_JOB_SEND_ATTEMPTS = 1000
MAX_WAITING_ON_SESSION_RESULTS_SEC = 3600


def submit_tasks_batch(
    n_jobs_per_thread,
    job_size,
    job_batch_size,
    worker_arguments,
    generate_payload_options,
    thread_id,
    do_print,
):
    try:
        agent_config_file = os.environ["AGENT_CONFIG_FILE"]
    except:
        agent_config_file = "/etc/agent/Agent_config.tfvars.json"

    logging.info("Agent config file:{}".format(agent_config_file))
    with open(agent_config_file, "r") as file:
        agent_config_data = json.loads(file.read())

    logging.info("Batch mode {}".format(thread_id))
    adapter = AWSConnector()
    try:
        username = os.environ["USERNAME"]
    except KeyError:
        username = ""
    try:
        password = os.environ["PASSWORD"]
    except KeyError:
        password = ""  # nosec B105
    adapter.init(agent_config_data, username=username, password=password)
    adapter.authenticate()
    logging.info("connector ready to submit tasks")

    jw = JW(worker_arguments, job_size, generate_payload_options)

    time.sleep(random.uniform(0, 2.0 * thread_id))

    for J in range(0, n_jobs_per_thread):
        saved_submission_responses = []
        batch_of_jobs = []

        # <1.> Generate a batch of jobs, i.e., list of lists of tasks
        for B in range(0, job_batch_size):
            # Generate a vector of tasks that forms a single job
            bin_job = jw.generate_binary_job()

            batch_of_jobs.append(bin_job)

        time_start_ms = int(round(time.time() * 1000))

        # <2.> For every Job in the Batch send vector of tasks, remember session ids for each job
        for i, job in enumerate(batch_of_jobs):
            logging.info("len {}".format(batch_of_jobs))
            retries = 0
            while True:
                try:
                    submission_resp = adapter.send(job)
                except Exception as e:
                    retries += 1
                    if retries > MAX_JOB_SEND_ATTEMPTS:
                        logging.error(
                            "TERMINAL ERROR IN SENDING EXITING (retries {}) \n{} {}".format(
                                retries, e, traceback.format_exc()
                            )
                        )
                        exit(1)
                        raise e
                    else:
                        logging.error(
                            "ERROR IN SENDING, retrying {} \n{} {}".format(
                                retries, e, traceback.format_exc()
                            )
                        )
                        continue
                break

            print(
                "[Jobid:{},thrdid:{},batchid:{}] Submitted session [{}] ".format(
                    J, thread_id, i, submission_resp["session_id"]
                )
            )
            saved_submission_responses.append(submission_resp)

        # <3.> Reiterate over session ids and attempt to retrieve all results.
        for task_index, sub_respo in enumerate(saved_submission_responses):
            print(
                "[iter:{},tid:{}] Waiting for session {}/{}  [{}]...".format(
                    J,
                    thread_id,
                    task_index + 1,
                    len(saved_submission_responses),
                    sub_respo["session_id"],
                ),
                end="",
                flush=True,
            )

            submission_results = adapter.get_results(
                sub_respo, timeout_sec=MAX_WAITING_ON_SESSION_RESULTS_SEC * 1000
            )

            results_ok = True
            msg = ""
            for i, stdout in enumerate(submission_results["finished_OUTPUT"]):
                verification_res, msg = jw.verify_results(stdout)
                if not verification_res:
                    print(
                        "[iter:{},tid:{}] Failed on result verification for session [{}] msg: {}".format(
                            J, thread_id, sub_respo["session_id"], msg
                        )
                    )

                    sys.exit(1)

                if do_print:
                    print(stdout.rstrip())

                # out_file = "./results/{}.{}.{}.out".format(file_name, submission_resp["session_id"], i)
                # with open(out_file, "wb") as f:
                #     f.write(stdout)

            msg = msg + "x{}".format(len(submission_results["finished_OUTPUT"]))
            time_end_ms = int(round(time.time() * 1000))
            print(
                "{} \nTime from start: {:.2f} sec".format(
                    msg, (time_end_ms - time_start_ms) / 1000.0
                )
            )
    logging.info("successfully submit batch execution")
    return True


def multiprocessing_execute_py(
    n_threads,
    n_jobs_per_thread,
    job_size,
    job_batch_size,
    worker_arguments,
    generate_payload_options,
    do_print,
):
    procs = []
    for thread_index in range(0, n_threads):
        p = Process(
            target=submit_tasks_batch,
            args=(
                n_jobs_per_thread,
                job_size,
                job_batch_size,
                worker_arguments,
                generate_payload_options,
                thread_index,
                do_print,
            ),
        )

        p.start()
        procs.append(p)

    for p in procs:
        logging.info("Wainting on {}".format(p))
        p.join()

    for p in procs:
        if p.exitcode != 0:
            logging.error(
                "One process did not exit successfully {}".format(p.exitcode())
            )
            raise Exception("Exit code not null")


def get_construction_arguments():
    parser = argparse.ArgumentParser(
        """ Multithreaded client, demonstrates batch execution. """,
        add_help=True,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "-n",
        "--njobs",
        type=int,
        default=1,
        help="""Number of jobs to generate per thread.
        Jobs are made of tasks and Jobs are sent in batches.
        Example if njobs=4, job_size=10, job_batch_size=2 then
        client will send 4 API cals grouped in pairs of 2:
        send[10] send[10] <check results, 1, 2> send[10] send[10] <check results, 1, 2>""",
    )

    parser.add_argument(
        "--job_size",
        type=int,
        default=1,
        help="""Determines how many tasks will be sent as a vector in a single API
        call. A single submitted vector will get 1 session ID. Session will be considered completed
        only when all tasks in the vector are completed""",
    )

    parser.add_argument(
        "--job_batch_size",
        type=int,
        default=1,
        help="""Determines how many Jobs to send in a batch. We send a batch
        of jobs and wait for all of them to complete, then send another set.""",
    )

    parser.add_argument(
        "--nthreads", type=int, default=1, help="Number of threads to run in parallel."
    )

    parser.add_argument(
        "--do_print", type=bool, default=False, help="Skip Visualisation."
    )

    parser.add_argument(
        "--generate_payload_options",
        type=str,
        default=None,
        help="""Option to upload a binary protbuff message as an input.
        Accepted options: proto_file <file_name>
                        : generated <size_in_bytes>""",
    )

    parser.add_argument(
        "--worker_type",
        type=str,
        help="Set the type of tasks to generate.",
        default="mock_compute_engine",
        choices=["mock_compute_engine"],
    )

    parser.add_argument(
        "--worker_arguments",
        type=str,
        default="1000 1 100",
        help="""A string that will be splitted by spaces and passed to the worker
        process by the agent.py. Used only with mock_compute_engine worker types.""",
    )

    parser.add_argument(
        "--log",
        "-l",
        type=str,
        default="warning",
        help="""
    log level for the python client:
        * critical
        * error
        * warning
        * info
        * debug
    """,
    )
    return parser


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.WARNING)
    FLAGS = get_construction_arguments().parse_args()
    logging.warning("Loggging status {}".format(FLAGS.log))
    if FLAGS.log:
        numeric_level = getattr(logging, FLAGS.log.upper(), None)
        if not isinstance(numeric_level, int):
            raise ValueError("Invalid log level: %s" % FLAGS.log)
        logging.getLogger().setLevel(numeric_level)

    if FLAGS.worker_type == "mock_compute_engine":
        execution_time = timeit.timeit(
            lambda: multiprocessing_execute_py(
                FLAGS.nthreads,
                FLAGS.njobs,
                FLAGS.job_size,
                FLAGS.job_batch_size,
                FLAGS.worker_arguments,
                FLAGS.generate_payload_options,
                FLAGS.do_print,
            ),
            number=1,
        )
        nb_jobs_processed = FLAGS.job_size * FLAGS.njobs * FLAGS.job_batch_size
        logging.warning("Execution times in second = {}".format(execution_time))
        logging.warning(
            "Observed Throuput (job/second) = {}".format(
                execution_time / nb_jobs_processed
            )
        )

    logging.warning("All threads completed. All results are verified!")
