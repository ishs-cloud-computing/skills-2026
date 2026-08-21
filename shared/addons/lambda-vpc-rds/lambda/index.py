# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

"""GET ?<KEY_COLUMN>=<값> → RDS Proxy(MySQL) 조회 (Function URL payload v2 / ALB 공용).

- 파라미터 누락 → 400, 행 없음 → 404, 있으면 200 + 행 배열(JSON)
- 자격증명은 Secrets Manager({username,password}) 를 콜드스타트 1회 읽어 재사용
- 연결은 전역에 캐시하고 ping 으로 재접속 (Proxy 가 서버 측 풀링을 맡는다)
- 테이블·컬럼은 SQL 식별자라 파라미터 바인딩이 안 된다 → 영숫자·_ 만 허용해 인젝션 차단
pymysql 은 zip 에 동봉: pip install pymysql -t lambda/
"""

import json
import os
import re
from datetime import date, datetime
from decimal import Decimal
from urllib.parse import unquote_plus

import boto3
import pymysql

TABLE = os.environ.get("TABLE", "product")
KEY_COLUMN = os.environ.get("KEY_COLUMN", "id")
_IDENT = re.compile(r"^[A-Za-z0-9_]+$")

_STATUS_TEXT = {200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"}
_conn = None


def _json_default(obj):
    if isinstance(obj, Decimal):
        return int(obj) if obj == obj.to_integral_value() else float(obj)
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    return str(obj)


def _response(event, status, body):
    resp = {
        "statusCode": status,
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False, default=_json_default),
    }
    if "elb" in (event.get("requestContext") or {}):
        resp["statusDescription"] = f"{status} {_STATUS_TEXT.get(status, '')}"
    return resp


def _connect():
    global _conn
    if _conn is not None:
        try:
            _conn.ping(reconnect=True)
            return _conn
        except Exception:
            _conn = None
    secret = json.loads(
        boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["SECRET_ARN"])["SecretString"]
    )
    _conn = pymysql.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "3306")),
        user=secret["username"],
        password=secret["password"],
        database=os.environ.get("DB_NAME", "dev"),
        connect_timeout=5,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )
    return _conn


def handler(event, context):
    if not (_IDENT.match(TABLE) and _IDENT.match(KEY_COLUMN)):
        return _response(event, 500, {"msg": "invalid TABLE/KEY_COLUMN"})

    params = event.get("queryStringParameters") or {}
    value = params.get(KEY_COLUMN)
    if not value:
        return _response(event, 400, {"msg": f"{KEY_COLUMN} is required"})

    with _connect().cursor() as cur:
        cur.execute(f"SELECT * FROM `{TABLE}` WHERE `{KEY_COLUMN}` = %s", (unquote_plus(value),))
        rows = cur.fetchall()

    if not rows:
        return _response(event, 404, {"msg": "Item not found"})
    return _response(event, 200, rows)


if __name__ == "__main__":
    assert _IDENT.match("product_v2") and not _IDENT.match("product; drop")
    assert json.dumps({"p": Decimal("9.5"), "d": date(2026, 8, 21)}, default=_json_default) == '{"p": 9.5, "d": "2026-08-21"}'
    assert "statusDescription" in _response({"requestContext": {"elb": {}}}, 200, [])
    print("ok")
