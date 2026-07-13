import json
import os
from datetime import datetime, timezone

import boto3

sns_client = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def publish_alert(event_type, detail, action):
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps({
            "event": event_type,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "detail": detail,
            "action": action,
        }),
    )


def handler(event, context):
    # Config Rules Compliance Change (NON_COMPLIANT) 이벤트 수신 → 알림만 발송
    detail = event.get("detail", {})
    resource_id = detail.get("resourceId", "unknown")
    compliance = (detail.get("newEvaluationResult") or {}).get("complianceType", "NON_COMPLIANT")

    publish_alert(
        "TAG_NON_COMPLIANT",
        f"Resource {resource_id} is {compliance} for required tags",
        "ALERT_ONLY",
    )
