import json
import os
from decimal import Decimal

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

_STATUS_TEXT = {200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"}


class _DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return str(obj)
        return super().default(obj)


def _response(status, body):
    # ALB(Lambda target) 통합 응답 형식
    return {
        "statusCode": status,
        "statusDescription": f"{status} {_STATUS_TEXT.get(status, '')}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=_DecimalEncoder),
    }


def handler(event, context):
    """GET /v1/book?booking_id=...&email=...&concert_name=...

    booking_id(필수, PK)로 조회하고, email / concert_name(선택)이 주어지면
    해당 조건도 만족하는 경우에만 반환한다. (요구사항 9)
    """
    params = event.get("queryStringParameters") or {}
    booking_id = params.get("booking_id")

    if not booking_id:
        return _response(400, {"msg": "booking_id is required"})

    item = table.get_item(Key={"booking_id": booking_id}).get("Item")
    if not item:
        return _response(404, {"msg": "Item not found"})

    # 선택 필터: 주어진 값과 불일치하면 미반환
    for key in ("email", "concert_name"):
        if params.get(key) and item.get(key) != params.get(key):
            return _response(404, {"msg": "Item not found"})

    return _response(
        200,
        {
            "booking_id": item.get("booking_id"),
            "client_id": item.get("client_id"),
            "username": item.get("username"),
            "email": item.get("email"),
            "concert_name": item.get("concert_name"),
            "created_at": item.get("created_at"),
        },
    )
