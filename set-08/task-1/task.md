# 2026년도 전국기능경기대회 과제출제 양식 (별첨3)

**분과**: IT·디자인 **직종명**: 클라우드컴퓨팅
**경기시간**: 4시간 (1과제)

## 시행 시 유의사항

### (시행 전)
1. 경기 시작 전 선수별 AWS 계정 접속 가능 여부를 확인한다.
2. 선수에게 제공되는 AWS 계정은 ap-northeast-2(서울) 리전에서 과제를 수행할 수 있어야 한다.
3. 선수에게 index.html, main.jpeg, book 바이너리를 배포 파일을 제공한다.
4. 선수에게 비번호를 부여하고, 모든 리소스명은 문제지의 명명 규칙을 따르도록 안내한다. (특히 S3와 같이 Global Unique한 리소스 명을 요구할 경우 비번호를 사용한다.)
5. 경기 시작 전 CloudShell, AWS CLI와 같은 도구 사용 가능 여부를 확인한다.
6. 경기 시작 전 인터넷 접속, DNS 질의, AWS Console 로그인, CloudShell 실행 상태를 확인한다.

### (시행 중)
1. 선수는 지급된 AWS 계정과 제공 파일만 사용하여 과제를 수행한다.
2. 별도의 지시가 없는 Region 선택형 AWS 리소스는 ap-northeast-2(서울) 리전에 생성한다. 단, CloudFront, IAM 등 Global 서비스는 예외로 한다.
3. 모든 리소스 이름, 태그, 환경 변수는 대소문자를 구분한다.

### (시행 후)
1. 경기 종료 후 선수는 배포된 리소스 및 리소스를 임의로 수정하지 않는다.
2. 경기 종료 후 채점 위원은 선수 제출 정보를 바탕으로 CloudShell에서 채점 스크립트를 실행한다.
3. 채점 중 CloudFront 배포, ECS Service 안정화, CloudWatch 메트릭 반영 등의 사유로 대기가 필요할 경우 항목당 최대 3분을 넘기지 않는다.
4. 이의신청 절차 종료 후 선수 AWS 계정에 생성된 리소스를 정리한다.

---

# Solution Architecture

| 직종명 | 클라우드컴퓨팅 | 과제명 | Solution Architecture |
| --- | --- | --- | --- |
| 경기시간 | 4시간 | 과제번호 | 제1과제 |
| 비번호 | | 심사위원 확인 | (인) |

## 1. 요구사항

본 과제는 AWS 기반 클라우드 인프라를 구축하고, 제공된 Book 애플리케이션을 ECS Fargate로 배포하여 CloudFront 단일 엔드포인트를 통해 정적 페이지와 API를 제공하는 것을 목표로 하며, 중요한 정보의 유출을 막고 고가용성을 확보하도록 설계되었습니다. 주어진 요구사항에 따라 고가용성, 보안, 확장성 등을 고려한 인프라를 구축해야 합니다.

## 2. 선수 유의사항

※ 다음 유의사항을 고려하여 요구사항을 완성하시오.

1) 기계 및 공구 등의 사용 시 안전에 유의하시고, 필요 시 안전장비 및 복장 등을 착용하여 사고를 예방하여 주시기 바랍니다.
2) 작업 중 화상, 감전, 찰과상 등 안전사고 예방에 유의하시고, 공구나 작업도구 사용 시 안전보호구 착용 등 안전수칙을 준수하시기 바랍니다.
3) 작업 중 공구의 사용에 주의하고, 안전수칙을 준수하여 사고를 예방하여 주시기 바랍니다.
4) 경기 시작 전 가벼운 스트레칭 등으로 긴장을 풀어주시고, 작업도구의 사용 시 안전에 주의하십시오.
5) 본 과제의 채점은 문제지에 명시된 고정 리소스 이름과 일부 고정 Name Tag를 기준으로 진행됩니다.
6) 문제지에서 명시하지 않은 리소스의 Name Tag는 자유롭게 지정할 수 있습니다.
7) 채점은 CloudShell에서 자동화 채점 스크립트를 실행하여 진행됩니다.
8) 경기 종료 후 채점 및 이의신청 절차가 완료될 때까지 생성한 리소스를 삭제하거나 임의로 수정하지 마십시오.
9) CloudFront, ECS Service, CloudWatch Metric 등 일부 리소스는 설정 반영에 시간이 걸릴 수 있으므로 경기 종료 전 정상 상태를 확인하십시오.
10) 불필요한 리소스나 과도한 크기의 컴퓨팅 리소스를 사용하는 경우 감점 요인이 될 수 있습니다.
11) 모든 리소스는 서울(ap-northeast-2) 리전에 구성합니다.

## 3. VPC

VPC는 아래 조건을 만족하도록 생성합니다. CIDR은 선수 자율로 지정하며, VPC의 DNS Hostname과 DNS Resolution 옵션은 활성화되어야 합니다. 또한 각각 두 개 이상의 Public, Private Subnet은 서로 다른 Availability Zone에 생성되어야 합니다. DynamoDB에 대한 접근은 VPC Endpoint를 구성하도록 합니다.

- VPC Name Tag: `skills-book-vpc`

## 4. S3

S3는 정적 페이지와 이미지를 저장하기 위해 사용합니다. 이때 S3 Bucket은 Public Access가 불가능해야 하며, CloudFront OAC를 통해 들어오는 요청만 허용하도록 구성해야 합니다.

- S3 Bucket Name: `skills-book-static-2026-<비번호>`

## CloudFront

CloudFront는 최종 사용자가 접근하는 단일 엔드포인트입니다. 하나의 CloudFront Distribution에서 S3 정적 리소스와 ALB API 요청을 모두 처리할 수 있어야 합니다.

- CloudFront Distribution Name Tag: `skills-book-cloudfront`
- Origin 1: S3 Bucket `skills-book-static-2026-<비번호>`
- Origin 2: ALB Origin
- S3 Origin Access: OAC 사용
- Default Root Object: `index.html`
- Default Cache Behavior: S3 Origin으로 전달
- Ordered Cache Behavior: `/v1/*` 경로를 ALB Origin으로 전달
- `/v1/*` Allowed Method: POST 포함
- ALB Origin Custom Header Name: `X-Origin-Verify`
- ALB Origin Custom Header Value: `<선수 자율 지정, 20자 이상>`

## 5. ALB

ALB는 CloudFront에서 전달된 API 요청을 ECS Fargate Service로 전달합니다. ALB는 skills-book-vpc의 Public Subnet에 위치하되, CloudFront에서 설정한 Custom Header가 없는 요청은 차단되어야 합니다.

- ALB Scheme: Internet-Facing
- ALB Subnet: skills-book-vpc 내 Public Subnet 2개 이상
- Listener: HTTP 80
- Target Group Type: IP
- Target Protocol: HTTP
- Target Port: 8080
- Health Check Path: `/health`
- Listener Rule 1: HTTP Header `X-Origin-Verify` 값이 CloudFront Origin Custom Header 값과 일치하는 경우 Target Group으로 Forward
- Default Listener Rule: Fixed Response 403
- ALB Direct Access: ALB DNS Name으로 직접 접근 시 403 응답 반환

## 6. ECR

ECR은 제공된 Book 애플리케이션 바이너리를 포함한 컨테이너 이미지를 저장하기 위해 사용합니다. 이미지는 Private Repository에 저장되어야 합니다.

- ECR Repository Name Tag: `skills-book-ecr`

## 7. ECS Fargate

ECS Fargate는 Book 애플리케이션을 실행하는 컴퓨팅 환경입니다. ECS Task는 Private Subnet에 배치하고, ALB를 통해 로드밸런싱 될 수 있어야 합니다. Fargate의 CPU와 메모리는 과도한 비용이 발생하지 않도록 적절히 최소 사양으로 배포합니다.

- ECS Cluster Name Tag: `skills-book-cluster`
- ECS Service Name Tag: `skills-book-service`
- ECS Task Definition Family: `skills-book-task`
- ECS Container Name: `skills-book-container`
- Desired Count: 2
- Container Port: 8080
- Log Group: `/ecs/skills-book-app`
- Log Stream Prefix: `book`
- Execution Role: `skills-book-ecs-execution-role`
- Task Role: `skills-book-ecs-task-role`

**Environment Variables**

| Key | Value |
| --- | --- |
| AWS_REGION | ap-northeast-2 |
| TABLE_NAME | skills-book-booking |

## 8. DynamoDB

DynamoDB는 Book API의 예약 데이터를 저장하기 위해 사용되는 서버리스 Key-Value 데이터베이스입니다. 이는 중요한 데이터가 포함되므로, 반드시 KMS CMK(Customer Managed Key)로 암호화되어야 합니다.

- DynamoDB Table Name: `skills-book-booking`
- Partition Key: `booking_id` (String)
- Attributes: booking_id, client_id, username, email, concert_name, created_at
- Encryption: KMS Customer Managed Key
- KMS Key Alias: `alias/skills-book-ddb`

## 9. CloudWatch

ECS Fargate Container의 stdout/stderr 로그는 CloudWatch Logs로 전송되어야 합니다.

- Log Group Name: `/ecs/skills-book-app`
- Log Stream Prefix: `book`

CloudWatch Metric Filter는 ECS Fargate Container Log에서 4xx, 5xx 오류 로그 수를 수집하기 위해 사용됩니다.

- Target Log Group: `/ecs/skills-book-app`
- 4xx Metric Filter Name: `skills-book-4xx-filter`
- 5xx Metric Filter Name: `skills-book-5xx-filter`
- Metric Namespace: `Skills/CloudComputing/Task1`
- 4xx Metric Name: `skills-book-4xx-count`
- 5xx Metric Name: `skills-book-5xx-count`
- Metric Value: 오류 로그 1건당 1
- Filter Pattern: 애플리케이션 로그 형식에 맞게 4xx, 5xx 상태 코드를 구분할 수 있어야 합니다.

CloudWatch Alarm은 4xx, 5xx 오류 로그가 1건 이상 발생한 경우 ALARM 상태가 되도록 구성합니다.

- 4xx Alarm Name: `skills-book-4xx-alarm`
- 5xx Alarm Name: `skills-book-5xx-alarm`
- Metric Namespace: `Skills/CloudComputing/Task1`
- 4xx Metric Name: `skills-book-4xx-count`
- 5xx Metric Name: `skills-book-5xx-count`
- Statistic: Sum
- Threshold: >= 1
- Period: 60 seconds
- Evaluation Periods: 1
- Datapoints to Alarm: 1
- Treat Missing Data: notBreaching

## 10. Application

Book 애플리케이션은 콘서트 예약 정보를 받아 데이터베이스에 저장하는 POST API를 제공합니다. 정상 구동 시 8080 포트가 바인딩되며 `/health` 호출 시 200 OK를 반환합니다. 제공된 book 바이너리는 컨테이너 이미지 빌드에 사용합니다.

| API | Request | Response | Description |
| --- | --- | --- | --- |
| GET `/health` | - | Code 200 (OK), application/json | Health Check |
| POST `/v1/book` | - client_id: Client ID (String)<br>- username: 구매자 이름 (String)<br>- email: 구매자 이메일 (String)<br>- concert_name: 콘서트 (String) | Code 200 (OK)<br>- booking_id: 유니크 ID 값 (String) | HTTP 요청의 Body에 있는 필드 값과 created_at 필드가 DynamoDB 테이블에 저장됩니다. |

그 외의 Security Group, Route Table, NACL 등의 네트워킹 구성은 보안을 고려하여 적절하게 구성합니다. IAM Role 및 Policy는 ECS Fargate 항목에서 요구한 Execution Role과 Task Role 분리 기준 및 최소 권한 원칙을 만족해야 합니다.

## 11. Software Stack

**AWS**
- VPC
- S3, CloudFront
- ECR, ECS
- DynamoDB
- KMS
- CloudWatch
- ALB
- IAM

**Language / Framework**
- Go
- Gin
