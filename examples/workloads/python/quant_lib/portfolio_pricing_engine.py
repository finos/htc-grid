# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import traceback
import json
import logging


from european_options import evaluate_european_option
from american_options import evaluate_american_option


def evaluate_option(option):
    try:
        if option["exercise"] == "European":
            return evaluate_european_option(option)
        elif option["exercise"] == "American":
            return evaluate_american_option(option)
        else:
            raise Exception(
                "Can not evaluate, exercise type is not supported: {}".format(
                    option["exercise"]
                )
            )

    except Exception as e:
        return f"Error in processing option [{option}] error: [{e}] trace: [{traceback.format_exc()}]"


def lambda_handler(event, context):
    results = [evaluate_option(opt) for opt in event["portfolio"]]
    logging.info(results)
    return {"results": results}


if __name__ == "__main__":
    """
    This code path is meant to be executed only for the testing purposes.
    """

    with open("./../../../client/python/sample_portfolio.json") as json_file:
        portfolio = json.load(json_file)

        results = lambda_handler(portfolio, None)
        print(results)

        # These numbers were ubtained by running QuantLib SQIG Python Examples for European and American option pricing
        european_options_expected_results = [
            0.030334,
            0.030334,
            0.030334,
            0.030334,
            0.030334,
            0.030287,
            0.030342,
            0.030392,
            0.030342,
            0.030303,
            0.030334,
            0.030334,
            0.033163,
            0.030293,
        ]
        american_options_expected_results = [
            4.462235,
            4.455663,
            4.488701,
            4.489087,
            4.489040,
            4.482594,
            4.489087,
            4.489066,
            4.488663,
            4.488663,
        ]

        all_expected_results = (
            european_options_expected_results + american_options_expected_results
        )

        for i, r in enumerate(results):
            # print(i, (abs(all_expected_results[i] - results[i])), all_expected_results[i], results[i])
            assert abs(all_expected_results[i] - results[i]) < 0.000001
