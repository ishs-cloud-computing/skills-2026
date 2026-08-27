# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

import base64
import json
import os
from datetime import datetime

import boto3

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
S3_BUCKET = os.environ["S3_BUCKET"]

sns_client = boto3.client("sns")
s3_client = boto3.client("s3")


def log(msg):
    print(f"{datetime.now().strftime('%Y/%m/%d %H:%M:%S')} {msg}")


def handler(event, context):
    records = [r for batch in event.get("records", {}).values() for r in batch]
    log(f"Processing batch: {len(records)} messages")

    for record in records:
        data = json.loads(base64.b64decode(record["value"]))
        sensor_id = data.get("sensorId", "unknown")
        timestamp = data.get("timestamp", "")

        # 1) SNS 알림 (lambda.md: 센서 ID, 이상 값, 발생 시간)
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Sensor Alert: {sensor_id}",
            Message=json.dumps({
                "sensorId": sensor_id,
                "alert_reason": data.get("alert_reason", ""),
                "temperature": data.get("temperature"),
                "humidity": data.get("humidity"),
                "timestamp": timestamp,
            }),
        )

        # 2) S3 저장 — lambda.md 경로: /alert/{sensorId}/{date}/{timestamp}.json
        date = timestamp[:10] if timestamp else "unknown"
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=f"alert/{sensor_id}/{date}/{timestamp}.json",
            Body=json.dumps(data),
            ContentType="application/json",
        )
        log(f"{sensor_id}: alert forwarded (SNS + S3)")
