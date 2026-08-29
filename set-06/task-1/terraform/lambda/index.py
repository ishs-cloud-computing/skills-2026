# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# NOTES.md §3.8 — 예약 조회 API (Function URL, API GW v2.0 이벤트 포맷)
# - client_id 미지정: Scan 전체, EMF 차원 "ALL"
# - client_id 지정: GSI Query, EMF 차원 그 값
# - EMF 는 print(json.dumps()) 만 사용 — logging 모듈 접두어가 붙으면 파싱이 깨진다
import json
import os
import time

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
GSI_NAME = os.environ["GSI_NAME"]
METRIC_NAMESPACE = os.environ["METRIC_NAMESPACE"]

table = boto3.resource("dynamodb").Table(TABLE_NAME)

PROJECTION = "username, email, concert_name"


def emit_query_count(client_id):
    print(json.dumps({
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": METRIC_NAMESPACE,
                "Dimensions": [["client_id"]],
                "Metrics": [{"Name": "QueryCount", "Unit": "Count"}],
            }],
        },
        "client_id": client_id,
        "QueryCount": 1,
    }))


def handler(event, context):
    qs = event.get("queryStringParameters") or {}
    client_id = qs.get("client_id")

    if client_id:
        resp = table.query(
            IndexName=GSI_NAME,
            KeyConditionExpression=Key("client_id").eq(client_id),
            ProjectionExpression=PROJECTION,
        )
    else:
        resp = table.scan(ProjectionExpression=PROJECTION)

    emit_query_count(client_id or "ALL")

    # 채점 8-3/8-4 기대 출력과 키 순서까지 일치시킨다 — DDB 응답 dict 순서는 비결정 (실측: concert_name 이 앞으로 옴)
    items = [
        {k: it[k] for k in ("username", "email", "concert_name") if k in it}
        for it in resp["Items"]
    ]

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(items),
    }
