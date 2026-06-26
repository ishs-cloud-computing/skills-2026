import json
import os

import boto3
from boto3.dynamodb.conditions import Key

# Lambda 는 VPC 내에서 실행되며, DynamoDB 표준 엔드포인트(dynamodb.ap-northeast-2
# .amazonaws.com)는 Route53 Private Hosted Zone 을 통해 인터페이스 VPC 엔드포인트로
# 해석된다(인터넷/NAT 불필요).
_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(os.environ["TABLE_NAME"])
_index_name = os.environ["GSI_NAME"]
_cw = boto3.client("cloudwatch")
_metric_namespace = os.environ["METRIC_NAMESPACE"]

# 응답에 노출할 필드(요구사항 Reference03): username, email, concert_name
_FIELDS = ("username", "email", "concert_name")


def _project(item):
    return {k: item.get(k) for k in _FIELDS}


def _emit_metric(client_id):
    # 요구사항 14: client_id 별 호출 횟수. 전체(client_id 미지정) 조회는 ALL 로 집계.
    dimension = client_id if client_id else "ALL"
    _cw.put_metric_data(
        Namespace=_metric_namespace,
        MetricData=[
            {
                "MetricName": "Invocations",
                "Dimensions": [{"Name": "client_id", "Value": dimension}],
                "Value": 1,
                "Unit": "Count",
            }
        ],
    )


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    """GET /reservation[?client_id=Cxxxx] (Lambda Function URL, payload v2)."""
    params = event.get("queryStringParameters") or {}
    client_id = params.get("client_id")

    _emit_metric(client_id)

    if client_id:
        # GSI(client_id-index) Query → 해당 client 의 예약만 반환
        result = _table.query(
            IndexName=_index_name,
            KeyConditionExpression=Key("client_id").eq(client_id),
        )
        items = result.get("Items", [])
    else:
        # 전체 예약 조회 (Scan)
        items = []
        scan_kwargs = {}
        while True:
            result = _table.scan(**scan_kwargs)
            items.extend(result.get("Items", []))
            if "LastEvaluatedKey" not in result:
                break
            scan_kwargs["ExclusiveStartKey"] = result["LastEvaluatedKey"]

    return _response(200, [_project(i) for i in items])
