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
    # 스케줄 룰(sg_sweep) 경유 호출 — 복구했을 때만 알림을 보낸다 (1분 주기 스팸 방지)
    scheduled = event.get("detail-type") == "Scheduled Event"

    group_id = request_params.get("groupId") or sg_id
    items = request_params.get("ipPermissions", {}).get("items", [])
    permissions = [_to_permission(i) for i in items]

    revoked = False
    if permissions:
        try:
            ec2_client.revoke_security_group_ingress(
                GroupId=group_id,
                IpPermissions=permissions,
            )
            revoked = True
        except ClientError as e:
            # 이미 삭제된 규칙(중복 이벤트/재시도)은 무시
            if e.response["Error"]["Code"] != "InvalidPermission.NotFound":
                raise

    # 폴백 스위퍼 — 이 SG 의 기준선은 인바운드 0 이다. CloudTrail 이벤트가 늦거나
    # (mark 3-4 는 authorize 후 sleep 60 한 번만 확인) 파싱 불가 형태로 와도 남은
    # 인바운드를 전부 걷어 0 을 보장한다. sg_sweep 스케줄 룰이 1분 주기로도 부른다.
    remaining = ec2_client.describe_security_groups(GroupIds=[sg_id])[
        "SecurityGroups"][0]["IpPermissions"]
    if remaining:
        try:
            ec2_client.revoke_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=remaining,
            )
            revoked = True
        except ClientError as e:
            if e.response["Error"]["Code"] != "InvalidPermission.NotFound":
                raise

    if revoked or not scheduled:
        publish_alert(
            "SG_INBOUND_ADDED",
            f"Unauthorized inbound rule removed from {group_id}",
            "RESTORED",
        )
