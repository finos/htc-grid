# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import setuptools

with open("README.md", "r") as fh:
    long_description = fh.read()

setuptools.setup(
    name="api",
    version="0.1",
    author="AWS",
    author_email="aws-htc-grid@amazon.com",
    description="Describe the API for submitting jobs to the HTC Grid",
    long_description=long_description,
    long_description_content_type="text/markdown",
    packages=setuptools.find_packages(),
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
    install_requires=["redis", "requests", "warrant-lite", "apscheduler", "urllib3"],
    python_requires=">=3.6",
)
