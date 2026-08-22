# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

import json
import os

import boto3

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def summarize(event):
    # CloudTrail 계열은 eventName, State-change 는 state, GuardDuty 는 type 이 핵심 식별자
    detail = event.get("detail") or {}
    return detail.get("eventName") or detail.get("state") or detail.get("type") or event.get("detail-type", "unknown")


def handler(event, context):
    detail_type = event.get("detail-type", "unknown")
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[ALERT] {detail_type}"[:100],
        Message=json.dumps({"event": detail_type, "summary": summarize(event), "detail": event.get("detail", {})}, default=str),
    )
    return {"status": "published", "event": detail_type}


if __name__ == "__main__":
    assert summarize({"detail-type": "AWS API Call via CloudTrail", "detail": {"eventName": "AuthorizeSecurityGroupIngress"}}) == "AuthorizeSecurityGroupIngress"
    assert summarize({"detail-type": "EC2 Instance State-change Notification", "detail": {"state": "stopped"}}) == "stopped"
    assert summarize({"detail-type": "Scheduled Event"}) == "Scheduled Event"
