# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import QuantLib as ql

from ql_common import construct_date, init_heston_model


def evaluate_european_option(input_dict):

    tparams = input_dict["tradeParameters"]

    # Option Construction
    todaysDate = construct_date(tparams["evaluationDate"])
    ql.Settings.instance().evaluationDate = todaysDate

    exercise = ql.EuropeanExercise(construct_date(tparams["exerciseDate"]))
    payoff = ql.PlainVanillaPayoff(ql.Option.Call, tparams["payoff"])

    option = ql.VanillaOption(payoff, exercise)

    # Market Data
    underlying = ql.SimpleQuote(tparams["underlying"])
    dividendYield = ql.FlatForward(todaysDate, tparams["dividendYield"], ql.Actual365Fixed())
    volatility = ql.BlackConstantVol(todaysDate, ql.TARGET(), tparams["volatility"], ql.Actual365Fixed())
    riskFreeRate = ql.FlatForward(todaysDate, tparams["riskFreeRate"], ql.Actual365Fixed())

    process = ql.BlackScholesMertonProcess(
        ql.QuoteHandle(underlying),
        ql.YieldTermStructureHandle(dividendYield),
        ql.YieldTermStructureHandle(riskFreeRate),
        ql.BlackVolTermStructureHandle(volatility),
    )

    hestonModel = init_heston_model(input_dict, riskFreeRate, dividendYield, underlying)

    if input_dict["engineName"] == "AnalyticEuropeanEngine":
        option.setPricingEngine(ql.AnalyticEuropeanEngine(process))

    elif input_dict["engineName"] == "AnalyticHestonEngine":
        option.setPricingEngine(ql.AnalyticHestonEngine(hestonModel))

    elif input_dict["engineName"] == "COSHestonEngine":
        option.setPricingEngine(ql.COSHestonEngine(hestonModel))

    elif input_dict["engineName"] == "IntegralEngine":
        option.setPricingEngine(ql.IntegralEngine(process))

    elif input_dict["engineName"] == "FdBlackScholesVanillaEngine":
        timeSteps = input_dict["engineParameters"]["timeSteps"]
        gridPoints = input_dict["engineParameters"]["gridPoints"]
        option.setPricingEngine(ql.FdBlackScholesVanillaEngine(process, timeSteps, gridPoints))

    elif input_dict["engineName"] == "BinomialVanillaEngine":
        timeSteps = input_dict["engineParameters"]["timeSteps"]
        # possible tree settings: ["JR", "CRR", "EQP", "Trigeorgis", "Tian", "LR", "Joshi4"]
        tree = input_dict["engineParameters"]["tree"]
        option.setPricingEngine(ql.BinomialVanillaEngine(process, tree, timeSteps))

    elif input_dict["engineName"] == "MCEuropeanEngine":

        if input_dict["engineParameters"]["random_source"] == "pseudorandom":
            option.setPricingEngine(ql.MCEuropeanEngine(
                process,
                "pseudorandom",
                timeSteps=input_dict["engineParameters"]["timeSteps"],
                requiredTolerance=input_dict["engineParameters"]["requiredTolerance"],
                seed=input_dict["engineParameters"]["seed"]
            )
            )

        elif input_dict["engineParameters"]["random_source"] == "lowdiscrepancy":

            option.setPricingEngine(ql.MCEuropeanEngine(
                process,
                "lowdiscrepancy",
                timeSteps=input_dict["engineParameters"]["timeSteps"],
                requiredSamples=input_dict["engineParameters"]["requiredSamples"]
            )
            )

        else:
            raise Exception("Unimplemented engineName [{}]".format(input_dict["engineName"]))

    else:
        raise Exception("Unimplemented engineName [{}]".format(input_dict["engineName"]))

    value = option.NPV()
    return value
