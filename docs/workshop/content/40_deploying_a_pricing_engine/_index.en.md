+++
title = "Deploying a Pricing Engine"
pre = "<b>4. </b>"
chapter = false
weight = 40
+++

So far we have deployed HTC-Grid and explored how to submit tasks using the example application. In this section we will deploy a Pricing Engine using [QuantLib](https://www.quantlib.org/docs.shtml) a free open source library for quantitative finance.

We will first understand how the worker is constructed and deploy a worker to HTC-Grid. Then we will construct and configure our client application and submit a few task to simulate portfolio pricing (A few models for European and American Options).

Let's begin !
