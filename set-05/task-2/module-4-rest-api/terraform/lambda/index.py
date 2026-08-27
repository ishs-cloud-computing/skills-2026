# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

"""REST API Lambda (과제지 6. REST API Implement).

- POST /v1/user : 사용자 생성. DynamoDB Conditional Write 로 중복 저장 방지.
                  Retry(Lambda/API GW/Client) 상황에서도 중복 시 "User already exists".
- GET  /v1/user : 사용자 조회. 없으면 "User not found".
- /v1/healthcheck 는 API Gateway MOCK 으로 처리하므로 Lambda 에서 다루지 않는다.

boto3 client/resource 는 모듈 스코프에서 1회 생성하여 재사용한다(Connection Reuse).
Exception 의 Stack Trace 는 외부로 노출하지 않는다.
"""
import json
import logging
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 모듈 스코프 재사용 (Cold Start 시 1회 생성)
_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(os.environ["TABLE_NAME"])


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _create_user(event):
    try:
        data = json.loads(event.get("body") or "{}")
    except (TypeError, ValueError):
        return _resp(400, {"message": "Invalid request body"})

    name = data.get("name")
    age = data.get("age")
    country = data.get("country")

    # 입력 Validation (잘못된 요청은 저장하지 않음)
    if (
        not isinstance(name, str)
        or not name
        or isinstance(age, bool)
        or not isinstance(age, int)
        or not isinstance(country, str)
        or not country
    ):
        return _resp(400, {"message": "Invalid request body"})

    try:
        # Conditional Write: 동일 name(PK)이 없을 때만 저장 -> 멱등/Retry-safe
        _table.put_item(
            Item={"name": name, "age": age, "country": country},
            ConditionExpression="attribute_not_exists(#n)",
            ExpressionAttributeNames={"#n": "name"},
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _resp(200, {"message": "User already exists"})
        logger.error("put_item failed: %s", exc.response["Error"]["Code"])
        return _resp(500, {"message": "Internal server error"})

    return _resp(200, {"message": "User created successfully"})


def _get_user(event):
    params = event.get("queryStringParameters") or {}
    name = params.get("name")
    if not name:
        return _resp(400, {"message": "Missing required request parameters: [name]"})

    try:
        result = _table.get_item(Key={"name": name})
    except ClientError as exc:
        logger.error("get_item failed: %s", exc.response["Error"]["Code"])
        return _resp(500, {"message": "Internal server error"})

    item = result.get("Item")
    if not item:
        return _resp(200, {"message": "User not found"})

    age = item.get("age")
    if isinstance(age, Decimal):
        age = int(age)

    return _resp(200, {"name": item.get("name"), "country": item.get("country"), "age": age})


def handler(event, context):
    try:
        method = event.get("httpMethod")
        if method == "POST":
            return _create_user(event)
        if method == "GET":
            return _get_user(event)
        return _resp(405, {"message": "Method not allowed"})
    except Exception:  # noqa: BLE001 - Stack Trace 외부 비노출
        logger.exception("unhandled error")
        return _resp(500, {"message": "Internal server error"})
