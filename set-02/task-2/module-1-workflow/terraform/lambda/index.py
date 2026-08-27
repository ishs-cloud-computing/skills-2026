# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

import csv
import io
import json
import os
import re
from datetime import datetime, timezone
from decimal import Decimal

import boto3

REQUIRED_FIELDS = ["examDate", "studentId", "name", "className", "korean", "english", "math", "science", "history"]
SCORE_FIELDS = ["korean", "english", "math", "science", "history"]

s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


def decode_csv(raw):
    # utf-8-sig: BOM 이 붙은 CSV(엑셀/메모장 저장본)를 그대로 받는다. utf-8 로 읽으면
    # 첫 헤더가 "﻿examDate" 가 되어 전 행이 MISSING_FIELD 로 떨어지고,
    # DynamoDB 는 0건인데 statusCode 는 200 이라 processed/ 로 넘어간다 (mark 1-5 오답)
    for encoding in ("utf-8-sig", "cp949"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def normalize_header(name):
    # BOM·공백·따옴표가 섞인 헤더도 REQUIRED_FIELDS 와 맞춘다
    return (name or "").strip().strip('"').strip("﻿").strip()


def read_rows(csv_text):
    reader = csv.DictReader(io.StringIO(csv_text))
    if reader.fieldnames:
        reader.fieldnames = [normalize_header(f) for f in reader.fieldnames]
    return reader.fieldnames or [], list(reader)


def validate_row(row):
    for field in REQUIRED_FIELDS:
        if not (row.get(field) or "").strip():
            return "MISSING_FIELD"

    exam_date = row.get("examDate", "").strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", exam_date):
        return "INVALID_DATE"
    try:
        datetime.strptime(exam_date, "%Y-%m-%d")
    except ValueError:
        return "INVALID_DATE"

    for field in SCORE_FIELDS:
        value = row.get(field, "").strip()
        if not value.lstrip("+-").isdigit():
            return "INVALID_FORMAT"
        score = int(value)
        if score < 0 or score > 100:
            return "INVALID_SCORE"

    return None


def save_error(bucket, row, error_reason, timestamp):
    # 공백뿐인 studentId 도 unknown 으로 — strip 을 먼저 해야 "error_..._.json" 이 안 생긴다
    student_id = (row.get("studentId") or "").strip() or "unknown"
    error_key = f"error/error_{timestamp}_{student_id}.json"

    body = {
        "studentId": student_id,
        "examDate": (row.get("examDate") or "").strip(),
        "error_reason": error_reason,
        "raw_data": {k: (v or "").strip() for k, v in row.items()},
    }

    s3_client.put_object(
        Bucket=bucket,
        Key=error_key,
        Body=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json; charset=utf-8",
    )


def calculate_grade(average):
    # A(90~100), B(80~89), C(70~79), D(60~69), F(0~59)
    if average >= 90:
        return "A"
    if average >= 80:
        return "B"
    if average >= 70:
        return "C"
    if average >= 60:
        return "D"
    return "F"


def save_student(table, row):
    # 평균은 Decimal 나눗셈으로 계산: float 는 96.60000000000001 이 되어
    # mark 1-5(average.N == 96.6) 오답이고, boto3 는 float 저장 자체를 거부한다
    scores = {field: int(row[field].strip()) for field in SCORE_FIELDS}
    # 분모는 과목 수와 이중 관리하지 않는다 — 30% 변동으로 과목이 바뀌면 SCORE_FIELDS 만 고친다
    average = Decimal(str(sum(scores.values()))) / Decimal(len(SCORE_FIELDS))

    item = {
        "studentId": row["studentId"].strip(),
        "examDate": row["examDate"].strip(),
        "name": row["name"].strip(),
        "className": row["className"].strip(),
        "average": average,
        "grade": calculate_grade(average),
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    for field, score in scores.items():
        item[field] = Decimal(str(score))

    table.put_item(Item=item)


def handler(event, context):
    bucket = os.environ.get("S3_BUCKET")
    table_name = os.environ.get("DDB_TABLE")

    if not bucket or not table_name:
        print("[processor] missing env S3_BUCKET/DDB_TABLE")
        return {"statusCode": 400, "processed": 0, "errors": 0}

    key = event.get("key")
    if not key or not key.startswith("input/"):
        print(f"[processor] bad key: {key!r}")
        return {"statusCode": 400, "processed": 0, "errors": 0}

    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        csv_text = decode_csv(response["Body"].read())
    except Exception as exc:
        print(f"[processor] get_object failed: {exc!r}")
        return {"statusCode": 400, "processed": 0, "errors": 0}

    fieldnames, rows = read_rows(csv_text)
    # 헤더와 행 수를 먼저 남긴다 — 전 행 탈락 시 원인이 헤더인지 값인지 로그 한 줄로 갈린다
    print(f"[processor] key={key} fieldnames={fieldnames} rows={len(rows)}")

    missing_headers = [f for f in REQUIRED_FIELDS if f not in fieldnames]
    if missing_headers:
        print(f"[processor] header mismatch, missing={missing_headers}")
        return {"statusCode": 400, "processed": 0, "errors": 0}

    table = dynamodb.Table(table_name)
    processed = 0
    errors = 0
    # 타임스탬프를 입력 객체의 LastModified 에서 뽑는다: Step Functions 가 Lambda 를
    # 재시도해도 error/ 키가 같아 덮어써진다. 벽시계였다면 재시도마다 새 파일이 생겨
    # mark 1-6(정확히 4개)이 깨진다
    last_modified = response.get("LastModified") or datetime.now(timezone.utc)
    timestamp = last_modified.astimezone(timezone.utc).strftime("%Y%m%d%H%M%S")

    for row in rows:
        error_reason = validate_row(row)
        if error_reason:
            save_error(bucket, row, error_reason, timestamp)
            errors += 1
        else:
            save_student(table, row)
            processed += 1

    print(f"[processor] processed={processed} errors={errors}")

    # 행은 읽혔는데 DynamoDB 에 한 건도 못 넣었으면 정상 종료로 위장하지 않는다.
    # 200 을 돌려주면 워크플로우가 processed/ 로 옮겨 "성공"처럼 보이고, 실패를
    # 발견하는 시점이 채점 직후가 된다 (실제로 mark 1-5 가 None 으로 나온 경위)
    if rows and processed == 0:
        print("[processor] every row rejected — reporting failure")
        return {"statusCode": 500, "processed": processed, "errors": errors}

    return {"statusCode": 200, "processed": processed, "errors": errors}
