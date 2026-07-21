# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

import base64
import json
import os
from datetime import datetime, timedelta, timezone

import boto3
from boto3.dynamodb.conditions import Key

KST = timezone(timedelta(hours=9))
GSI_NAME = "booking_id-index"


def _resolve_table_name():
    """환경변수 TABLE_NAME 은 function CMK 암호문(base64) — 런타임에 복호화한다.

    (요구사항 10: 전송 중/저장 중 CMK 암호화. 로컬 테스트 등 평문이 들어오면 그대로 사용)
    """
    raw = os.environ["TABLE_NAME"]
    try:
        plaintext = boto3.client("kms").decrypt(CiphertextBlob=base64.b64decode(raw))["Plaintext"]
        return plaintext.decode("utf-8")
    except Exception:
        return raw


table = boto3.resource("dynamodb").Table(_resolve_table_name())


def _to_kst(value):
    """저장된 created_at 을 'YYYY-MM-DD HH:MM:SS KST' 로 변환한다.

    book 앱이 저장하는 포맷이 고정 문서화되어 있지 않아 epoch / RFC3339 /
    'YYYY-MM-DD HH:MM:SS' 계열을 모두 파싱한다. (배포 후 실측으로 확인 — README)
    """
    if value is None:
        return ""
    s = str(value)

    dt = None
    # epoch (초/밀리초)
    try:
        num = float(s)
        if num > 1e12:
            num /= 1000.0
        dt = datetime.fromtimestamp(num, tz=timezone.utc)
    except ValueError:
        pass

    if dt is None:
        # RFC3339 / ISO 8601 ('Z' 포함), 'YYYY-MM-DD HH:MM:SS' 계열
        try:
            dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except ValueError:
            return s  # 파싱 불가 시 원본 유지

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(KST).strftime("%Y-%m-%d %H:%M:%S KST")


def _response(status, body_obj):
    # 필드 순서 보존: Python dict 는 삽입 순서를 유지하고 json.dumps 가 그대로 직렬화
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body_obj, ensure_ascii=False),
    }


def handler(event, context):
    """GET /v1/book?booking_id=... (Lambda Function URL, payload v2)"""
    params = event.get("queryStringParameters") or {}
    booking_id = params.get("booking_id")

    if not booking_id:
        return _response(400, {"msg": "booking_id is required"})

    items = table.query(
        IndexName=GSI_NAME,
        KeyConditionExpression=Key("booking_id").eq(booking_id),
        Limit=1,
    ).get("Items", [])

    if not items:
        return _response(404, {"msg": "Item not found"})

    item = items[0]
    # 응답 컬럼 순서 고정: client_id, username, email, concert_name, created_at (mark 9-3)
    return _response(
        200,
        {
            "client_id": item.get("client_id"),
            "username": item.get("username"),
            "email": item.get("email"),
            "concert_name": item.get("concert_name"),
            "created_at": _to_kst(item.get("created_at")),
        },
    )