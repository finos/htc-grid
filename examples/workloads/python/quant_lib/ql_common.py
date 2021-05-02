# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import QuantLib as ql


def construct_date(date_string):
    """
    Converts string to ql.Date object

    Args:
        string: date_string. Example: "31 12 1999"

    Returns:
        dict: ql.Date

    """

    date_tokens = date_string.split(" ")
    date_tokens = [int(x) for x in date_tokens]

    assert date_tokens[0] <= 31
    assert date_tokens[1] <= 12
    assert date_tokens[2] > 0

    ql_date = ql.Date(date_tokens[0], date_tokens[1], date_tokens[2])
    return ql_date


def init_heston_model(option_dict, riskFreeRate, dividendYield, underlying):
    """
    Converts string to ql.Date object

    Args:
        string: date_string. Example: "31 12 1999"

    Returns:
        dict: ql.Date

    """

    if option_dict["engineName"] in ["AnalyticHestonEngine", "COSHestonEngine"]:
        hestonProcess = ql.HestonProcess(
            ql.YieldTermStructureHandle(riskFreeRate),
            ql.YieldTermStructureHandle(dividendYield),
            ql.QuoteHandle(underlying),
            0.1 * 0.1,
            1.0,
            0.1 * 0.1,
            0.0001,
            0.0,
        )
        hestonModel = ql.HestonModel(hestonProcess)

        return hestonModel
    else:
        return None
