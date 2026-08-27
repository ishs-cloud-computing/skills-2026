# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

"""wskorea26-book-lambda — 콘서트 예매 정보 조회 (Reference03).

ALB(Lambda TargetGroup) 로 호출되며 GET ?concert_name=<이름> 을 처리한다.
- concert_name 누락 시 400 Bad Request
- 결과 없음 → 빈 배열 [] + 200 OK
- GSI(concert_name-created_at-index) Query + ScanIndexForward=False 로
  "데이터베이스 레벨" 최신순 정렬을 보장한다.
- 연결 정보는 하드코딩 금지 → TABLE_NAME/INDEX_NAME 은 환경변수,
  리전은 Lambda 런타임 기본 환경변수(AWS_REGION)를 그대로 사용.
"""

import json
import os
from urllib.parse import unquote_plus

import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
index_name = os.environ.get("INDEX_NAME", "concert_name-created_at-index")

_STATUS_TEXT = {200: "OK", 400: "Bad Request", 500: "Internal Server Error"}

# mark 9-2 예상 출력과 동일한 키 순서 (json.dumps 는 dict 삽입 순서를 유지)
_KEYS = ["username", "created_at", "email", "booking_id", "client_id", "concert_name"]


def _response(status, body):
    # ALB(Lambda target) 통합 응답 형식
    return {
        "statusCode": status,
        "statusDescription": f"{status} {_STATUS_TEXT.get(status, '')}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        # ensure_ascii=False: mark 9-2 는 "akaね" 처럼 비ASCII 값을 그대로 기대한다
        "body": json.dumps(body, ensure_ascii=False, default=str),
    }


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    concert_name = params.get("concert_name")

    if not concert_name:
        return _response(400, {"msg": "concert_name is required"})

    # ALB 는 쿼리 스트링을 디코딩하지 않고 전달한다 (예: 2ND%20TINY_CON)
    concert_name = unquote_plus(concert_name)

    items = []
    kwargs = {
        "IndexName": index_name,
        "KeyConditionExpression": Key("concert_name").eq(concert_name),
        "ScanIndexForward": False,  # created_at DESC = 최신순 (Reference03)
    }
    while True:
        page = table.query(**kwargs)
        items.extend(page.get("Items", []))
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]

    return _response(200, [{k: item.get(k) for k in _KEYS} for item in items])
