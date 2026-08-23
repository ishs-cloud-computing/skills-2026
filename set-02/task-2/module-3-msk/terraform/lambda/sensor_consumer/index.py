import base64
import json
import os
from datetime import datetime
from decimal import Decimal

import boto3
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
from kafka import KafkaProducer
from kafka.net.sasl.oauth import AbstractTokenProvider

DDB_TABLE = os.environ["DDB_TABLE"]
ALERT_TOPIC = os.environ["ALERT_TOPIC"]
BOOTSTRAP_SERVER = os.environ["BOOTSTRAP_SERVER"]
REGION = os.environ["AWS_REGION"]

table = boto3.resource("dynamodb").Table(DDB_TABLE)


def log(msg):
    # lambda.md 로그 출력 형식: 2026/05/30 14:00:00 <message>
    print(f"{datetime.now().strftime('%Y/%m/%d %H:%M:%S')} {msg}")


# kafka-python 3.x 는 sasl_oauth_token_provider 가 AbstractTokenProvider 서브클래스일 것을 강제한다
# (duck typing 불가) — 미상속 시 KafkaConfigurationError 로 producer 생성이 실패한다.
class TokenProvider(AbstractTokenProvider):
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
        return token


_producer = None


def get_producer():
    # 콜드스타트 비용이 커서 첫 ALERT 발생 시에만 생성, 이후 컨테이너 재사용
    global _producer
    if _producer is None:
        _producer = KafkaProducer(
            bootstrap_servers=BOOTSTRAP_SERVER.split(","),
            security_protocol="SASL_SSL",
            sasl_mechanism="OAUTHBEARER",
            sasl_oauth_token_provider=TokenProvider(),
            key_serializer=lambda k: k.encode(),
            value_serializer=lambda v: json.dumps(v).encode(),
        )
    return _producer


def check_anomaly(temperature, humidity):
    # lambda.md 이상 탐지 규칙 · 사유 문자열 정확 일치
    if temperature > 80:
        return f"Temperature exceeded threshold: {temperature}°C"
    if temperature < 10:
        return f"Temperature below threshold: {temperature}°C"
    if humidity > 90:
        return f"Humidity exceeded threshold: {humidity}%"
    if humidity < 20:
        return f"Humidity below threshold: {humidity}%"
    return None


def handler(event, context):
    records = [r for batch in event.get("records", {}).values() for r in batch]
    log(f"Processing batch: {len(records)} messages")

    alerted = False
    for record in records:
        data = json.loads(base64.b64decode(record["value"]))
        sensor_id = data.get("sensorId", "unknown")
        temperature = float(data["temperature"])
        humidity = float(data["humidity"])

        reason = check_anomaly(temperature, humidity)
        if reason:
            data["status"] = "ALERT"
            data["alert_reason"] = reason
            get_producer().send(ALERT_TOPIC, key=sensor_id, value=data)
            alerted = True
            log(f"{sensor_id}: ALERT - temp={temperature}°C ({reason.split(':')[0]})")
        else:
            # 속성 타입은 과제지 6. DynamoDB 표를 그대로 따른다 — humidity 만 Number,
            # 나머지는 String. 채점 3-5 가 temperature.S / status.S 로 조회하므로
            # temperature 를 Number 로 바꾸면 그 항목이 빈다.
            # boto3 는 float 저장을 거부해 Decimal 로 넣는다.
            table.put_item(Item={
                "sensorId": sensor_id,
                "timestamp": str(data.get("timestamp", "")),
                "temperature": str(temperature),
                "humidity": Decimal(str(humidity)),
                "location": str(data.get("location", "")),
                "status": "NORMAL",
            })
            log(f"{sensor_id}: NORMAL - temp={temperature}°C, humidity={humidity}%")

    if alerted:
        get_producer().flush()
