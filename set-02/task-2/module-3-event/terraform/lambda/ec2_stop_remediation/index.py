import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

ec2_client = boto3.client("ec2")
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
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id") or os.environ.get("INSTANCE_ID")

    # 'stopping' 시점에 트리거되므로 stopped 까지 대기 후 즉시 시작
    # (mark 3-4 는 stop 후 약 40초 뒤 running 을 기대 — 짧은 폴링 주기가 핵심)
    ec2_client.get_waiter("instance_stopped").wait(
        InstanceIds=[instance_id],
        WaiterConfig={"Delay": 5, "MaxAttempts": 50},
    )
    try:
        ec2_client.start_instances(InstanceIds=[instance_id])
    except ClientError as e:
        # 중복 이벤트로 이미 시작 중이면 무시
        if e.response["Error"]["Code"] != "IncorrectInstanceState":
            raise

    publish_alert(
        "EC2_STOPPED",
        f"Instance {instance_id} was stopped and restarted",
        "RESTORED",
    )
