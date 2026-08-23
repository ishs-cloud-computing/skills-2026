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

    # 타입 변조 복구(ec2_type_remediation)의 stop→modify→start 진행 중에도 stopping
    # 이벤트가 이 함수를 부른다. 그때 여기서 start 를 걸면 modify 가
    # IncorrectInstanceState 로 실패하고 타입이 변조된 채 남는다 — 현재 타입이
    # 기대값과 다르면 시작을 type remediation 에 맡기고 물러난다.
    expected_type = os.environ.get("INSTANCE_TYPE")
    if expected_type:
        current_type = ec2_client.describe_instances(InstanceIds=[instance_id])[
            "Reservations"][0]["Instances"][0]["InstanceType"]
        if current_type != expected_type:
            publish_alert(
                "EC2_STOPPED",
                f"Instance {instance_id} stopping with modified type {current_type} - restart deferred to type remediation",
                "ALERT_ONLY",
            )
            return

    # 'stopping' 시점에 트리거되므로 stopped 까지 대기 후 즉시 시작
    # (mark 3-4 는 stop 후 sleep 60 시점에 running 을 기대 — 짧은 폴링 주기가 핵심)
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
