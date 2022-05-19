#!/bin/bash
PASSWORD=$(aws ecr get-login-password)
ctr images pull -u AWS:$PASSWORD $1