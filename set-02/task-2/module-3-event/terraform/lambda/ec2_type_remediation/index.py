import json
import os
from datetime import datetime, timezone

import boto3

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
    instance_id = os.environ.get("INSTANCE_ID")
    original_type = os.environ.get("INSTANCE_TYPE")
    detail = event.get("detail", {})

    changed_type = (
        detail.get("requestParameters", {}).get("instanceType", {}).get("value")
    )
    if changed_type == original_type:
        # 원복 자체가 유발한 이벤트 — 무한 루프 방지 (룰의 anything-but 과 이중 방어)
        return

    ec2_client.stop_instances(InstanceIds=[instance_id])
    ec2_client.get_waiter("instance_stopped").wait(
        InstanceIds=[instance_id],
        WaiterConfig={"Delay": 5, "MaxAttempts": 50},
    )
    ec2_client.modify_instance_attribute(
        InstanceId=instance_id,
        InstanceType={"Value": original_type},
    )
    ec2_client.start_instances(InstanceIds=[instance_id])

    publish_alert(
        "EC2_TYPE_CHANGED",
        f"Instance {instance_id} type was changed and restored to {original_type}",
        "RESTORED",
    )
