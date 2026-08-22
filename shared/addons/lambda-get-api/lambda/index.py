# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

"""GET ?<KEY_NAME>=<값> → DynamoDB 조회 (ALB Lambda target / Function URL / API GW proxy 공용).

- KEY_NAME 누락 → 400 {"msg": "<key> is required"}
- 없음 → 404 {"msg": "Item not found"}
- INDEX_NAME 이 비면 테이블 PK GetItem, 있으면 GSI Query(최신 1건)
- 200 본문은 FIELDS 순서 그대로 (dict 삽입 순서 = json.dumps 출력 순서)
원본: set-07 task-1 lambda/index.py, set-03 task-1 lambda/index.py
"""

import json
import os
from decimal import Decimal
from urllib.parse import unquote_plus

import boto3
from boto3.dynamodb.conditions import Key

_table = None
KEY_NAME = os.environ.get("KEY_NAME", "booking_id")
INDEX_NAME = os.environ.get("INDEX_NAME", "")
FIELDS = [f for f in os.environ.get("FIELDS", "").split(",") if f]

_STATUS_TEXT = {200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"}


def _json_default(obj):
    if isinstance(obj, Decimal):
        return int(obj) if obj == obj.to_integral_value() else float(obj)
    return str(obj)


def _response(event, status, body):
    resp = {
        "statusCode": status,
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        # ensure_ascii=False: 채점지는 비ASCII 값(한글·일본어 이름)을 그대로 기대한다
        "body": json.dumps(body, ensure_ascii=False, default=_json_default),
    }
    # ALB Lambda target 통합 응답은 statusDescription 을 요구한다 (Function URL/API GW 이벤트엔 elb 키가 없다)
    if "elb" in (event.get("requestContext") or {}):
        resp["statusDescription"] = f"{status} {_STATUS_TEXT.get(status, '')}"
    return resp


def _lookup(value):
    global _table
    if _table is None:
        # 콜드스타트 1회 생성 후 재사용 (모듈 로드 시점에 만들면 로컬 self-check 가 리전 오류로 막힌다)
        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    table = _table
    if INDEX_NAME:
        items = table.query(
            IndexName=INDEX_NAME,
            KeyConditionExpression=Key(KEY_NAME).eq(value),
            ScanIndexForward=False,
            Limit=1,
        ).get("Items", [])
        return items[0] if items else None
    return table.get_item(Key={KEY_NAME: value}).get("Item")


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    value = params.get(KEY_NAME)
    if not value:
        return _response(event, 400, {"msg": f"{KEY_NAME} is required"})

    # ALB 는 쿼리스트링을 디코딩하지 않고 전달한다 (예: 2ND%20TINY_CON)
    item = _lookup(unquote_plus(value))
    if not item:
        return _response(event, 404, {"msg": "Item not found"})

    # 선택 필터: 추가 쿼리 파라미터가 오면 항목 값과 불일치 시 미반환 (set-07 요구사항 9)
    for k, v in params.items():
        if k != KEY_NAME and v and str(item.get(k)) != unquote_plus(v):
            return _response(event, 404, {"msg": "Item not found"})

    body = {k: item.get(k) for k in FIELDS} if FIELDS else item
    return _response(event, 200, body)


if __name__ == "__main__":
    # 응답 포맷 자가 점검 (boto3 호출 없음)
    alb_evt = {"requestContext": {"elb": {}}, "queryStringParameters": {}}
    r = _response(alb_evt, 400, {"msg": "x"})
    assert r["statusDescription"] == "400 Bad Request" and r["isBase64Encoded"] is False
    url_evt = {"requestContext": {"http": {}}, "queryStringParameters": {}}
    assert "statusDescription" not in _response(url_evt, 200, {})
    assert json.dumps({"a": Decimal("3"), "b": Decimal("1.5")}, default=_json_default) == '{"a": 3, "b": 1.5}'
    print("ok")
