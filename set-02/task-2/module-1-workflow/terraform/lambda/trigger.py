# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

import json
import os
import urllib.parse

import boto3

sfn = boto3.client("stepfunctions")


def handler(event, context):
    # S3 Event Notification (prefix input/, suffix .csv) → 워크플로우 시작 (lambda.md B)
    for record in event.get("Records", []):
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        sfn.start_execution(
            stateMachineArn=os.environ["STATE_MACHINE_ARN"],
            input=json.dumps({"key": key}),
        )
