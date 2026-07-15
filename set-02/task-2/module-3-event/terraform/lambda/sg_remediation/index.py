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


def _to_permission(item):
    # CloudTrail requestParameters(camelCase, items 래핑) → boto3 IpPermissions 형태
    perm = {"IpProtocol": str(item["ipProtocol"])}
    if "fromPort" in item:
        perm["FromPort"] = item["fromPort"]
    if "toPort" in item:
        perm["ToPort"] = item["toPort"]
    ranges = [{"CidrIp": r["cidrIp"]} for r in item.get("ipRanges", {}).get("items", []) if "cidrIp" in r]
    if ranges:
        perm["IpRanges"] = ranges
    v6 = [{"CidrIpv6": r["cidrIpv6"]} for r in item.get("ipv6Ranges", {}).get("items", []) if "cidrIpv6" in r]
    if v6:
        perm["Ipv6Ranges"] = v6
    groups = [{"GroupId": g["groupId"]} for g in item.get("groups", {}).get("items", []) if "groupId" in g]
    if groups:
        perm["UserIdGroupPairs"] = groups
    return perm


def handler(event, context):
    sg_id = os.environ.get("SECURITY_GROUP_ID")
    detail = event.get("detail", {})
    request_params = detail.get("requestParameters", {})

    group_id = request_params.get("groupId") or sg_id
    items = request_params.get("ipPermissions", {}).get("items", [])
    permissions = [_to_permission(i) for i in items]

    if permissions:
        try:
            ec2_client.revoke_security_group_ingress(
                GroupId=group_id,
                IpPermissions=permissions,
            )
        except ClientError as e:
            # 이미 삭제된 규칙(중복 이벤트/재시도)은 무시
            if e.response["Error"]["Code"] != "InvalidPermission.NotFound":
                raise

    publish_alert(
        "SG_INBOUND_ADDED",
        f"Unauthorized inbound rule removed from {group_id}",
        "RESTORED",
    )
