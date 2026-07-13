# 2026년도 전국기능경기대회 과제 — 제2과제

| 직종명 | 클라우드컴퓨팅 |
|---|---|
| 과제명 / 과제번호 | 제2과제 |
| 경기시간 | 4시간 |

## 1. 요구사항

1) Workflow
2) Real-time data analytics
3) Cloud event handling
4) MSK

## 2. 선수 유의사항

※ 다음 유의사항을 고려하여 요구사항을 완성하시오.

1) 기계 및 공구 등의 사용 시 안전에 유의하시고, 필요시 안전장비 및 복장 등을 착용하여 사고를 예방하여 주시기 바랍니다.
2) 작업 중 화상, 감전, 찰과상 등 안전사고 예방에 유의하시고, 공구나 작업도구 사용 시 안전보호구 착용 등 안전수칙을 준수하시기 바랍니다.
3) 작업 중 공구의 사용에 주의하고, 안전수칙을 준수하여 사고를 예방하여 주시기 바랍니다.
4) 경기 시작 전 가벼운 스트레칭 등으로 긴장을 풀어주시고, 작업도구의 사용 시 안전에 주의하십시오.
5) 문제에 제시된 괄호 `<>`는 변수를 뜻함으로 선수가 적절히 변경하여 사용해야 합니다.
6) Security Group의 80/443 outbound는 anyopen하여 사용할 수 있도록 합니다.
7) Bastion EC2는 채점을 위해 사용합니다. 서버들에 접속 문제가 생겨 채점에 불이익을 받지 않도록 합니다.
8) 과제 종료 전 실행 중인 테스트 및 부하를 중지하여 서버에 문제가 없도록 해야 합니다.
9) Tag 정보가 맞지 않거나 권한 문제가 생겨 채점이 불가하지 않도록 주의합니다.
10) 채점을 위한 Bastion을 생성하고, Bastion은 모든 Resource를 Access 할 수 있어야 합니다.
11) 채점지와 문제지 마다 사용하는 Region이 모두 다르니 확인 하도록 합니다.

---

## 1) Workflow

### 개요

S3, Lambda, DynamoDB, Step Functions를 활용하여 학생 성적 데이터를 자동으로 수집, 변환, 저장하는 서버리스 데이터 처리 워크플로우를 구성합니다. Region은 **ap-southeast-1**을 사용합니다.

### 과제 설명

#### 1. S3

학생 성적 원본 데이터를 저장하기 위한 S3 버킷을 구성합니다. 사용자는 학생 이름이 포함된 CSV 파일을 S3에 업로드하며, Step Functions는 해당 파일을 기준으로 워크플로우를 실행합니다. 채점 시 S3의 `/processed/`, `/error/` 폴더는 비어있어야 하며, 배포된 `test.csv` 파일을 S3의 `/input` 경로에 업로드 해야합니다.

- **Bucket Name** : `wsc2026-student-score-bucket-<비번호>`

| Folder Prefix | Folder Description |
|---|---|
| `/input/` | 원본 학생 성적 csv 파일 저장 |
| `/processed/` | 처리 완료된 파일 저장 |
| `/error/` | 검증 실패 데이터 및 워크플로우 오류 로그 저장 |

#### 2. Lambda

S3에 업로드된 학생 성적 데이터를 읽고, 평균 점수와 등급을 계산한 뒤 DynamoDB에 저장하기 위한 Lambda 함수를 구성합니다. Lambda Function에 대한 세부 사항은 `lambda.md`를 참고하세요.

#### 3. DynamoDB

Lambda에서 처리한 학생 성적 데이터를 저장하기 위한 DynamoDB 테이블을 구성합니다. 채점 시 DynamoDB의 모든 데이터를 삭제해야합니다.

- **Table Name** : `wsc2026-student-score`
- **Key** : (PK : `studentId`) (SK : `examDate`)

#### 4. Step Functions

학생 성적 데이터 처리 과정을 오케스트레이션하기 위한 Step Functions State Machine을 구성합니다. Step Functions는 S3 데이터 읽기, 성적 변환, DynamoDB 저장 과정을 순차적으로 실행합니다. Workflow에 대한 자세한 정보는 `workflow.md`를 참고하세요.

- **State Machine Name** : `wsc2026-student-score-workflow`
- **State Machine Type** : Standard

#### 5. IAM

Lambda와 Step Functions가 S3, DynamoDB에 접근할 수 있도록 IAM Role과 Policy를 구성합니다. IAM Role에는 최소권한을 적용하도록 합니다.

| Role Name | Used By |
|---|---|
| `wsc2026-lambda-student-role` | Lambda |
| `wsc2026-stepfunction-student-role` | Step Function |

---

## 2) Real-time data analytics

### 개요

애플리케이션에서 발생하는 주문 로그 데이터를 기반으로 실시간 데이터 분석 환경을 구성합니다. Region은 **ap-northeast-2**를 사용합니다.

### 과제 설명

#### 1. VPC

실시간 분석 시스템 운영을 위한 네트워크를 구성합니다. VPC는 고가용성을 고려하여 구성합니다.

| VPC Name | VPC CIDR |
|---|---|
| analytics-vpc | 10.20.0.0/16 |

| Subnet Name | Subnet CIDR | Route Table | Internet Access |
|---|---|---|---|
| analytics-pub-a | 10.20.0.0/24 | analytics-pub-rtb | analytics-igw (IGW) |
| analytics-pub-b | 10.20.1.0/24 | analytics-pub-rtb | analytics-igw (IGW) |
| analytics-priv-a | 10.20.100.0/24 | analytics-priv-a-rtb | analytics-ngw (NAT) |
| analytics-priv-b | 10.20.101.0/24 | analytics-priv-b-rtb | analytics-ngw (NAT) |

#### 2. EC2

주문 로그를 발생시키는 Python 애플리케이션 서버를 구성합니다. EC2는 Private Subnet에 배치하며, Load Balancer를 통해서만 외부 접근이 가능하도록 합니다. 애플리케이션에 대한 자세한 설명은 배포파일의 `Application.md`를 참고하세요. 채점시 SSM을 사용하므로 SSM으로 접근이 가능하도록 구성해야 합니다.

- **Instance Name** : `wsc2026-analytics-ec2`
- **Instance Type** : t3.small

#### 3. Load Balancer

EC2에 대한 외부 트래픽을 처리하는 Application Load Balancer를 구성합니다.

- **Load Balancer Name** : `wsc2026-analytics-alb`
- **Load Balancer Listener** : HTTP 80
- **Target Group Name** : `wsc2026-analytics-tg`

#### 4. Kinesis Data Stream

애플리케이션에서 발생하는 주문 로그를 수집하기 위한 Kinesis Data Stream을 구성합니다.

- **Stream Name** : `wsc2026-order-stream`
- **Capacity Mode** : On-demand

#### 5. Managed Apache Flink

Kinesis Data Stream에 수집된 주문 로그를 실시간으로 분석하기 위한 Managed Apache Flink Studio Notebook을 구성합니다. Flink 애플리케이션 프로그래밍은 금지하며, Notebook에서 SQL 언어로 쿼리를 수행합니다.

- **Application Name** : `wsc2026-analytics-flink`
- **Runtime** : Apache Flink 1.19

Notebook에서 아래 SQL 쿼리가 정상 실행되어야 합니다.

**1) 최근 1분간 총 주문 수**

```sql
SELECT COUNT(*) as order_count
FROM order_stream
WHERE event_time > CURRENT_TIMESTAMP - INTERVAL '1' MINUTE;
```

**2) 상품별 누적 매출**

```sql
SELECT product_name, SUM(price * quantity) as total_revenue
FROM order_stream
GROUP BY product_name;
```

#### 6. IAM

EC2와 Managed Flink가 Kinesis Data Stream에 접근할 수 있도록 IAM Role을 구성합니다. IAM Role에는 최소권한이 적용되어야 합니다.

- **EC2 Role** : `wsc2026-alaytics-ec2-role`
- **Managed Flink Role** : `wsc2026-analytics-flink-role`

---

## 3) Cloud Event Handling

### 개요

보안 또는 비용 상 위협이 발생할 시, 원래 상태로 복구하거나 관리자에게 알림을 발송하는 자동화 시스템을 구성합니다. Region은 **eu-west-1**을 사용합니다.

### 과제 설명

#### 1. VPC

보안 정책 자동화 대상이 되는 네트워크를 구성합니다.

| VPC Name | VPC CIDR |
|---|---|
| event-vpc | 172.16.0.0/16 |

| Subnet Name | Subnet CIDR | Route Table | Internet Access |
|---|---|---|---|
| event-pub-a | 172.16.0.0/24 | event-pub-rtb | event-igw (IGW) |
| event-pub-b | 172.16.1.0/24 | event-pub-rtb | event-igw (IGW) |

#### 2. EC2

보안 정책 모니터링 대상이 되는 EC2 인스턴스를 구성합니다.

- **Instance Name** : `wsc2026-event-ec2`
- **Instance Type** : t3.micro
- **IAM Role Name** : `wsc2026-event-ec2-role`
- **Subnet** : event-pub-a

#### 3. Security Group

EC2에 연결된 보안 그룹을 구성합니다. 보안그룹은 최소한으로 구성해야합니다.

- **Security Group Name** : `wsc2026-event-sg`

#### 4. EventBridge

보안 및 비용에 관한 문제가 발생할 경우를 감지하는 EventBridge Rule을 각각 구성합니다.

| Rule Name | Detection conditions |
|---|---|
| `wsc2026-sg-change-rule` | EC2 Security Group 인바운드 규칙 추가 |
| `wsc2026-role-change-rule` | EC2 IAM Role 변경 |
| `wsc2026-ec2-terminate-rule` | EC2 인스턴스 종료 |
| `wsc2026-ec2-type-change-rule` | EC2 인스턴스 타입 변경 |

#### 5. CloudTrail

EventBridge가 API 호출 이벤트를 감지할 수 있도록 CloudTrail을 구성합니다.

- **Trail Name** : `wsc2026-event-trail`
- **Management Events** : Read/Write

#### 6. Lambda

정책 위반을 감지하여 자동 복구 및 SNS 알림을 수행하는 Lambda 함수를 구성합니다. Lambda 함수에 대한 자세한 설명은 배포파일의 `lambda.md`를 참고하세요.

- **Role Name** : `wsc2026-event-lambda-role`

#### 7. SNS

정책 위반 발생 시 알림 메시지를 발행하기 위한 SNS Topic을 구성합니다. Lambda 함수는 위반 감지 시 해당 Topic에 메시지를 Publish합니다.

- **Topic Name** : `wsc2026-event-alert`

---

## 4) MSK

### 개요

Amazon MSK를 활용한 이벤트 스트리밍 파이프라인을 구성합니다. 데이터를 실시간 수집하여 이상치를 감지하고 알림을 발송하는 시스템을 구성합니다. MSK 클러스터는 IAM 인증을 통해서만 접근 가능해야 합니다. Region은 **ap-northeast-1**을 사용합니다.

### 과제 설명

#### 1. VPC

MSK 클러스터와 Producer 서버를 위한 네트워크를 구성합니다.

| VPC Name | VPC CIDR |
|---|---|
| msk-vpc | 192.168.0.0/16 |

| Subnet Name | Subnet CIDR | Route Table | Internet Access |
|---|---|---|---|
| msk-pub-a | 192.168.0.0/24 | msk-pub-rtb | msk-igw (IGW) |
| msk-pub-d | 192.168.1.0/24 | msk-pub-rtb | msk-igw (IGW) |
| msk-priv-a | 192.168.10.0/24 | msk-priv-a-rtb | msk-ngw (NAT) |
| msk-priv-d | 192.168.11.0/24 | msk-priv-d-rtb | msk-ngw (NAT) |

#### 2. MSK

센서 데이터를 스트리밍하기 위한 Amazon MSK 클러스터를 구성합니다. 클러스터는 Private 환경에 구성해야 하며 고가용성을 고려해야합니다.

- **Cluster Name** : `wsc2026-msk-cluster`
- **Kafka Version** : 3.6.0
- **Broker Instance Type** : kafka.t3.small

#### 3. MSK Topic

메시지를 발행하고 Consumer가 구독할 Kafka Topic을 생성합니다.

| Topic Name | Partitions | Replication Factor |
|---|---|---|
| `wsc2026-sensor-raw` | 3 | 2 |
| `wsc2026-sensor-alert` | 1 | 2 |

- **PK** : `sensorId`

#### 4. EC2

Producer 애플리케이션을 실행하는 EC2 인스턴스를 구성합니다. EC2는 Private 환경에 구성하며 MSK 클러스터와 통신할 수 있어야 합니다. EC2의 IAM 권한은 최소로 설정해야 합니다. 애플리케이션에 대한 자세한 설명은 배포파일의 `Application.md`를 참고하세요.

- **Instance Name** : `wsc2026-sensor-producer`
- **Instance Type** : t3.small
- **Role Name** : `wsc2026-msk-ec2-role`

#### 5. Lambda

MSK 토픽에서 메시지를 소비하여 처리하는 Lambda Consumer를 구성합니다. Lambda 함수의 IAM 권한은 최소로 설정해야 합니다. Lambda 함수에 대한 자세한 설명은 배포파일의 `lambda.md`를 참고하세요.

- **Role Name** : `wsc2026-msk-lambda-role`
- **Runtime** : Python 3.14
- **Trigger** : MSK

| Function Name | Trigger |
|---|---|
| `wsc2026-sensor-consumer` | `wsc2026-sensor-raw` |
| `wsc2026-sensor-alert-consumer` | `wsc2026-sensor-alert` |

#### 6. DynamoDB

Lambda Consumer가 처리한 센서 데이터를 저장하기 위한 DynamoDB 테이블을 구성합니다.

- **Table Name** : `wsc2026-sensor-data`
- **Key** : (PK: `sensorId`) (SK: `timestamp`)

| Attribute | Type | Description |
|---|---|---|
| studentId | String | PK |
| examDate | String | SK |
| name | String | Student Name |
| average | Number | Average Score |
| grade | String | Grade (A~F) |
| korean, english, math, science, social | Number | Score |

#### 7. S3

오류 데이터를 저장하기 위한 S3 버킷을 구성합니다.

- **Bucket Name** : `wsc2026-sensor-alert-bucket-<비번호>`
