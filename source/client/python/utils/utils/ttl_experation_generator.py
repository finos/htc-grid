# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

import random
import time


class TTLExpirationGenerator:
    def __init__(self, task_ttl_refresh_interval_sec, task_ttl_expiration_offset_sec):
        # This is how often we send heart beats, i.e., how often we extend TTL value
        self.refresh_interval_sec = task_ttl_refresh_interval_sec
        # This is by how much inot the future we extend TTL value
        self.expriation_offset_sec = task_ttl_expiration_offset_sec

        if self.refresh_interval_sec >= self.expriation_offset_sec:
            raise Exception(
                """Refresh interval [{}] must be smaller then expiration offset [{}].
                Otherwise TTL will always expire before we have chance to extend it!""".format(
                    self.refresh_interval_sec, self.expriation_offset_sec
                )
            )
        self.next_refresh_timestamp = 0
        self.next_expiration_timestamp = 0

    def generate_next_ttl(self):
        self.next_refresh_timestamp = int(time.time()) + random.randint(
            self.refresh_interval_sec, int(self.refresh_interval_sec * 1.1)
        )
        self.next_expiration_timestamp = self.next_refresh_timestamp + (
            self.expriation_offset_sec - self.refresh_interval_sec
        )
        return self

    def get_next_expiration_timestamp(self):
        return self.next_expiration_timestamp

    def get_next_refresh_timestamp(self):
        return self.next_refresh_timestamp
