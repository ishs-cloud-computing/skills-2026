# 2026년도 전국기능경기대회 제1과제 — Solution Architecture

| 직종명 | 클라우드컴퓨팅 | 과제명 | Solution Architecture | 과제번호 | 제 1과제 |
|---|---|---|---|---|---|
| 경기시간 | 4시간 | 비번호 | | 심사위원 확인 | (인) |

## 1. 요구사항

본 과제는 지급된 정적 웹 파일(index.html, main.jpeg)과 컨테이너 실행 파일(book)을 반드시 사용하여, 콘서트 예약 서비스를 AWS 상에 구축하는 과제이다. 선수는 정적 웹 호스팅, CDN, 네트워크, 컨테이너 실행 환경, 데이터베이스, 로드밸런서, 로그 수집 구성을 통합하여 서비스가 정상 동작하도록 구성하여야 한다.

(※ 원본 문제지에는 이 위치에 아키텍처 다이어그램 이미지가 포함되어 있습니다.)

### 필수 Software Stack

| AWS | 개발언어/프레임워크 |
|---|---|
| VPC | Golang |
| S3 | Gin |
| CloudFront | |
| ECS Fargate | |
| ECR | |
| Application Load Balancer | |
| DynamoDB | |
| CloudWatch Logs | |
| IAM | |
| Docker | |

### 사용 가능 Software Stack

| AWS | 개발언어/프레임워크 |
|---|---|
| Route53 | Docker |
| WAF | AWS CLI v2 |
| API Gateway | |

## 2. 선수 유의사항

1) AWS 서비스 사용 시 보안에 유의하고, IAM 사용자 정보 및 인증 정보를 외부에 노출하지 않도록 주의하시기 바랍니다.
2) 작업 중 리소스 생성 및 설정 변경 시 요구사항을 충분히 검토하여 서비스 장애가 발생하지 않도록 주의하시기 바랍니다.
3) AWS Console 및 AWS CLI 사용 시 입력값과 설정값을 정확하게 확인한 후 작업을 진행하시기 바랍니다.
4) 경기 시작 전 문제지와 지급 파일의 내용을 충분히 검토하고 작업 계획을 수립한 후 과제를 수행하시기 바랍니다.
5) 선수 계정에는 비용 제한이 존재하며, 이를 초과하여 과금이 발생할 경우 계정 사용이 제한될 수 있습니다.
6) 문제에 제시된 괄호(<>) 표기는 변수값을 의미하며, 선수는 요구사항에 맞게 적절한 값으로 변경하여 사용하여야 합니다.
7) 과제 종료 시 실행 중인 테스트 및 불필요한 프로세스를 종료하여 시스템에 과도한 부하가 발생하지 않도록 합니다.
8) 별도 언급이 없는 경우 모든 AWS 리소스는 ap-northeast-2(서울) 리전에 생성하여야 합니다.
9) 문제에 제시된 아키텍처 다이어그램은 논리적 구성을 표현한 것으로, 세부 구성은 요구사항을 만족하는 범위 내에서 자유롭게 구현할 수 있습니다.
10) 모든 리소스 이름(Name), 태그(Tag), 환경 변수(Environment Variable)는 대소문자를 구분합니다.
11) 문제에서 명시되지 않은 설정은 AWS Well-Architected Framework를 기준으로 합리적으로 구성하여야 합니다.
12) 불필요한 리소스를 생성한 경우 감점 요인이 될 수 있습니다. (예: 미사용 EC2, 미사용 Load Balancer, 불필요한 VPC 등)
13) 요구사항에 명시된 리소스의 종류, 수량, CPU 및 Memory 설정을 준수하여야 하며, 임의 변경 시 감점될 수 있습니다.
14) 모든 시간은 KST(UTC+9)를 기준으로 합니다.
15) 컨테이너 서비스는 Amazon ECS Fargate를 사용하여 구성하여야 하며, 별도 언급이 없는 한 Amazon EC2 기반 ECS 또는 AWS Lambda를 사용할 수 없습니다.
16) 지급된 index.html, main.jpeg, book 파일은 반드시 사용하여야 하며, 임의의 다른 애플리케이션 파일로 대체할 수 없습니다.
17) ECS Task는 채점 시점까지 정상적으로 Running 상태를 유지하여야 하며, CloudFront, ALB, DynamoDB, CloudWatch Logs가 정상 연동되어야 합니다.
18) CloudWatch Logs 로그 그룹 이름은 반드시 `/skillskorea/ecs/app`을 사용하여야 합니다.
19) 모든 리소스 이름에는 선수 식별이 가능한 접두어(선수ID)를 포함하여야 합니다.
20) CloudFront Distribution 생성에는 배포 시간이 소요될 수 있다. 채점 시 CloudFront 배포 상태 확인을 위해 최대 3분까지 대기할 수 있다.
21) Amazon Q는 웹 콘솔 채팅 기능만 사용 가능하며, Q Pro, Q Developer CLI, Kiro, MCP 연계 등 AI 코딩 도구는 사용할 수 없습니다.
22) `<선수ID>`는 선수의 비번호를 의미합니다. AWS Account ID가 아니며, 모든 리소스 이름 및 Name Tag에서 `<선수ID>`로 표시된 부분은 본인의 비번호로 치환하여 사용합니다.
23) 예시:
   - `<선수ID>-vpc` → `101-vpc`
   - `<선수ID>-static-site` → `101-static-site`
   - `<선수ID>-book-cluster` → `101-book-cluster`

## 3. 네트워크 구성

콘서트 예약 서비스를 운영하기 위한 네트워크 환경을 구성하여야 합니다. 모든 서비스는 해당 네트워크를 기반으로 통신하여야 하며, 인터넷을 통한 사용자 접근이 가능하여야 합니다.

- 1개의 VPC를 생성한다. (CIDR: 10.0.0.0/16)
- 최소 2개의 Public Subnet을 서로 다른 가용영역(AZ)에 생성한다.
- Internet Gateway를 생성하여 VPC에 연결(Attach)한다.
- Public Subnet용 라우팅 테이블을 생성하고, 기본 경로(0.0.0.0/0)를 Internet Gateway로 설정한 뒤 두 서브넷에 연결한다.
- VPC Endpoint(DynamoDB, S3, ECR 등)는 활용 가능하나, PrivateLink는 사용할 수 없다.

| 리소스 | 이름 예시 | CIDR / 값 | 비고 |
|---|---|---|---|
| VPC | `<선수ID>-vpc` | 10.0.0.0/16 | - |
| Public Subnet 1 | `<선수ID>-public-subnet-1` | 10.0.1.0/24 | ap-northeast-2a |
| Public Subnet 2 | `<선수ID>-public-subnet-2` | 10.0.2.0/24 | ap-northeast-2c |
| Internet Gateway | `<선수ID>-igw` | - | VPC에 Attach |
| Route Table | `<선수ID>-public-rt` | 0.0.0.0/0 → IGW | 두 서브넷에 연결 |

## 4. 정적 웹 호스팅(S3)

- S3 버킷을 생성한다. (버킷명: `<선수ID>-static-site`)
- 지급된 index.html과 main.jpeg를 반드시 해당 버킷에 업로드한다.
- CloudFront에서 S3를 오리진으로 사용할 수 있도록 OAI/OAC(Origin Access Identity/Control) 또는 버킷 정책을 구성한다.
- S3 버킷에 직접 퍼블릭 접근하는 것은 허용하지 않으며, 반드시 CloudFront를 통해서만 접근 가능하도록 구성하는 것을 권장한다.

## 5. CloudFront

- CloudFront Distribution은 S3와 ALB를 각각 오리진으로 구성하여야 한다.
- 기본 경로(/) 및 정적 파일 요청은 S3 오리진으로 전달한다.
- /v1/* 및 /health 요청은 ALB 오리진으로 전달한다.
- 사용자는 CloudFront 도메인을 통해 정적 웹 페이지와 API에 접근하여야 한다.
- Default Root Object는 index.html로 설정한다.

## 6. ECR (Elastic Container Registry)

- ECR 프라이빗 Repository를 생성한다. (이름: `<선수ID>-book-ecr`)
- 지급된 book 실행 파일을 사용하여 컨테이너 이미지를 빌드한다.
- 컨테이너 이미지는 Linux/AMD64 아키텍처를 사용하여야 한다.
- 빌드한 이미지를 ECR Repository에 업로드한다.
- 이미지 태그는 latest를 사용한다.
- ECS Task Definition은 latest 태그 이미지를 참조하여야 한다.

## 7. ECS (Fargate)

### 7.1 ECS Cluster

- ECS Cluster를 생성한다. (이름: `<선수ID>-book-cluster`)
- Capacity Provider는 FARGATE를 사용한다.
- 채점 시 ECS Cluster 상태는 ACTIVE 이어야 한다.

### 7.2 Task Definition

- Fargate 호환 Task Definition을 생성한다.
- 컨테이너 이미지는 ECR에 Push한 latest 태그 이미지를 참조한다.
- Runtime Platform은 Linux/AMD64를 사용한다.
- 컨테이너 포트 매핑은 TCP 8080을 사용한다.
- containerPort는 8080으로 설정한다.
- CPU는 256 CPU Units, Memory는 512 MiB를 사용한다.
- 반드시 지정된 CPU 및 Memory 값을 사용하여야 한다.

**환경 변수**

| 환경 변수 | 값 | 설명 |
|---|---|---|
| AWS_REGION | ap-northeast-2 | DynamoDB 등 AWS 서비스 호출 시 사용하는 리전 |
| TABLE_NAME | `<선수ID>-booking-table` | 예약 정보를 저장할 DynamoDB 테이블 이름 |

### 7.3 IAM Role

- Task Execution Role 및 Task Role을 구성한다.
- Task Role은 DynamoDB 저장 권한을 포함하여야 한다.

### 7.4 ECS Service

- ECS Service를 생성한다. (이름: `<선수ID>-book-service`)
- Launch Type은 FARGATE를 사용한다.
- Desired Count는 1 이상으로 설정한다.
- 채점 시 최소 1개의 Task가 Running 상태여야 한다.
- 생성한 2개의 Public Subnet을 사용한다.
- Assign Public IP는 ENABLED로 설정한다.
- 보안 그룹은 `<선수ID>-ecs-sg`를 사용한다.
- Application Load Balancer의 Target Group과 연결한다.
- 채점 시 Target Group의 대상(Target)은 Healthy 상태여야 한다.
- GET /health 요청 시 HTTP 200 OK를 반환하여야 한다.

## 8. Application Load Balancer

- ALB를 생성한다. (이름: `<선수ID>-book-alb`) / Scheme: Internet-facing
- 서브넷은 위에서 생성한 2개의 Public Subnet을 지정한다.
- Listener는 HTTP:80을 사용한다.
- Target Group은 HTTP:8080, Target Type은 IP로 구성한다.
- 헬스 체크 경로는 /health, 정상 응답 코드는 200으로 설정한다.
- ALB는 CloudFront에서 전달되는 /health 및 /v1/* 요청을 ECS Service로 전달하여야 한다.
- 사용자는 ALB DNS를 직접 호출하지 않고 CloudFront 도메인을 통해 API에 접근하여야 한다.

| 보안그룹 | 방향 | 프로토콜 | 포트 | 소스/대상 | 설명 |
|---|---|---|---|---|---|
| `<선수ID>-alb-sg` | 인바운드 | HTTP | 80 | 0.0.0.0/0 | CloudFront를 포함한 외부 요청 허용 |
| `<선수ID>-ecs-sg` | 인바운드 | TCP | 8080 | `<선수ID>-alb-sg` (SG ID) | ALB에서만 ECS 접근 허용 |
| `<선수ID>-ecs-sg` | 아웃바운드 | All | All | 0.0.0.0/0 | 외부 통신 허용 (ECR, DynamoDB, CloudWatch 등) |

※ ECS 보안그룹의 인바운드 소스를 CIDR(0.0.0.0/0)이 아닌 ALB 보안그룹 ID로 제한하여야 한다.

## 9. NoSQL 데이터베이스

- DynamoDB 테이블을 생성한다. (이름: `<선수ID>-booking-table`)
- Billing Mode: On-demand(PAY_PER_REQUEST) 또는 Provisioned 모두 가능
- book 애플리케이션이 POST /v1/book 호출 시 아래 스키마에 따라 데이터를 저장할 수 있어야 한다.

| 속성명 | 타입 | 키 유형 | 비고 |
|---|---|---|---|
| client_id | String (S) | Partition Key | 필수 — 변경 불가 |
| booking_id | String (S) | - | 유니크 예약ID (자동 생성) |
| username | String (S) | - | 예약자 이름 |
| email | String (S) | - | 예약자 이메일 |
| concert_name | String (S) | - | 콘서트명 |
| created_at | String (S) | - | 예약 생성 일시(자동 저장) |

## 10. 모니터링 시스템

book 애플리케이션에서 발생하는 로그를 수집하고 모니터링할 수 있도록 CloudWatch Logs를 구성하여야 합니다.

- ECS 컨테이너 로그를 CloudWatch Logs로 전송한다.
- 로그 그룹 이름: `/skillskorea/ecs/app` (고정)
- awslogs 로그 드라이버를 사용한다.

예약 생성 API 호출 시 아래와 같은 데이터가 저장될 수 있어야 합니다.

```json
{
  "client_id": "C001",
  "booking_id": "BK20260001",
  "username": "홍길동",
  "email": "hong@test.com",
  "concert_name": "Seoul2026",
  "created_at": "2026-01-01T09:00:00+09:00"
}
```

**로그 드라이버 옵션**

| 옵션 | 값 | 설명 |
|---|---|---|
| awslogs-group | /skillskorea/ecs/app | 로그 그룹 이름(고정) |
| awslogs-region | ap-northeast-2 | 로그 전송 리전 |
| awslogs-stream-prefix | ecs | 로그 스트림 접두어(Task ID 자동 부여) |

- 로그 스트림은 Task 단위로 자동 생성된다. (형식: `ecs/<컨테이너명>/<Task ID>`)
- /health 호출 로그 및 POST /v1/book 요청 로그가 CloudWatch Logs에서 확인 가능해야 한다.

## 11. 애플리케이션 동작 조건

| 구분 | Method | Path | 설명 | 응답 |
|---|---|---|---|---|
| 상태 확인 | GET | /health | 정상 구동 확인 | HTTP 200 OK `{"status":"OK","version":"1.0.1"}` |
| 예약 생성 | POST | /v1/book | 예약 정보를 DynamoDB에 저장 | HTTP 200 `{"booking_id":"<유니크ID>"}` |

**예약 생성 요청 Body (JSON)**

```json
{
  "client_id": "C001",
  "username": "Alice",
  "email": "kim@example.com",
  "concert_name": "Seoul2026"
}
```

**예약 생성 응답(JSON)**

```json
{
  "booking_id": "C2011YY"
}
```

※ 모든 필드는 String 타입이며, client_id는 DynamoDB 파티션 키로 사용된다.
※ POST 요청 시 body 필드 값과 created_at(예약 생성 일시) 필드가 DynamoDB 테이블에 함께 저장된다.
※ /health 및 /v1/book 요청은 CloudFront 도메인을 통해 호출되어야 한다.

---
*원본: 2026년_전국대회_1과제_문제지_v1.0.5.pdf (클라우드컴퓨팅 제1과제, 총 7페이지)*
