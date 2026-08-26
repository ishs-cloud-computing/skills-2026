# client-vpn 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

2과제 카탈로그 9 "VPN (Client VPN, VPC, EC2)" 스타터 키트 — 저장소에 구현이 없는 모듈.
당일 모듈 5·6 으로 출제되면 `_template/task-2/module-4` 를 복사한 빈 모듈의 `terraform/` 에 통째로 넣고 시작한다.
자족적(VPC 포함): Client VPN 엔드포인트(mutual TLS) + 서브넷 연결 + 인가 규칙 + CloudWatch 접속 로그 + 검증용 private EC2.
인증서는 Windows PowerShell `openssl` 로 만들어 ACM 에 import 하고 ARN 만 변수로 넘긴다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_vpn_server_cert_arn` | **필수** | ACM 에 import 한 서버 인증서 ARN (README 절차로 생성). 같은 리전이어야 한다 |
| `addon_vpn_name` | `"skills-client-vpn"` | Client VPN 엔드포인트 Name 태그·description. VPC·SG·로그 그룹 이름도 여기서 파생. 과제지 명시 이름과 정확히 일치시킨다 |
| `addon_vpn_vpc_cidr` | `"10.70.0.0/16"` | VPC CIDR. 클라이언트 CIDR 과 겹치면 안 된다 |
| `addon_vpn_private_subnets` | `{` | 프라이빗 서브넷 (key = Name 태그). 첫 번째가 VPN 대상 네트워크·EC2 배치 서브넷. 연결(association)은 서브넷당 과금이라 기본 1개 |
| `addon_vpn_client_cidr` | `"172.16.0.0/22"` | VPN 클라이언트에 배정할 CIDR. /22 이상 /12 이하, VPC CIDR·로컬 네트워크와 겹치지 않게 |
| `addon_vpn_client_root_cert_arn` | `""` | 클라이언트 루트 체인(CA) 인증서 ARN. 서버 인증서와 같은 CA 로 발급했으면 빈 문자열 → 서버 인증서 ARN 재사용 |
| `addon_vpn_split_tunnel` | `true` | split tunnel. true 면 VPC 대역만 터널로 가고 인터넷은 로컬. false(full tunnel)는 README 블록의 0.0.0.0/0 route·auth rule + NAT 가 추가로 필요 |
| `addon_vpn_transport_protocol` | `"udp"` | udp(기본) 또는 tcp |
| `addon_vpn_log_retention_days` | `30` | 접속 로그 그룹 보존 일수 |
| `addon_vpn_ec2_name` | `"skills-client-vpn-target"` | VPN 으로 접근할 private EC2 Name 태그 (SG 이름 파생) |
| `addon_vpn_ec2_instance_type` | `"t3.micro"` | 대상 EC2 인스턴스 타입 |
| `addon_vpn_ec2_key_name` | `""` | SSH 키 페어 이름. 빈 문자열이면 키 없이 생성 (ping·HTTP 검증만) |

## KEEP — 건드리지 않는다

- 기존 세트의 리소스·이름·CIDR. 이름이 충돌하면 기존 것을 지우지 말고 **이 KIT 쪽 변수를 리네임**한다.
- 공식 지급물 — `provided/`, `task.md`, `mark.md`, `mark*.sh`.
- `plan` 에 기존 리소스의 replace/delete 가 보이면 apply 하지 말고 멈춘다.

## CHECK — apply 전 계정·리전

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
```

## RUN

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

복사할 파일과 순서는 아래 본문을 따른다.

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

## 파일

- `vpc.tf` — VPC · private 서브넷 (IGW·NAT 없음)
- `vpn.tf` — 로그 그룹/스트림 · 엔드포인트 SG · `aws_ec2_client_vpn_endpoint` · `_network_association` · `_authorization_rule`
- `ec2.tf` — 대상 EC2 (AL2023, python http.server:80) + SG(ICMP·22·80 을 VPN 엔드포인트 SG 에서만)
- `outputs.tf` — 엔드포인트 ID·DNS · 대상 EC2 private IP
- `variables.tf` — `addon_vpn_*` 변수

## 부착 절차

1. **인증서 생성** (PowerShell, 작업 폴더에서; `openssl` 이 없으면 Git for Windows 동봉 `& "C:\Program Files\Git\usr\bin\openssl.exe"` 로 바꾼다):

   ```powershell
   # CA
   openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout ca.key -out ca.crt -subj "/CN=skills-vpn-ca"
   # 서버 인증서 (serverAuth 필수 — 없으면 ACM import 는 되지만 엔드포인트 생성이 실패한다)
   openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=server"
   "basicConstraints=CA:FALSE`nkeyUsage=digitalSignature,keyEncipherment`nextendedKeyUsage=serverAuth`nsubjectAltName=DNS:server" | Set-Content -Encoding ascii server.ext
   openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out server.crt -extfile server.ext
   # 클라이언트 인증서 (clientAuth)
   openssl req -newkey rsa:2048 -nodes -keyout client1.key -out client1.csr -subj "/CN=client1.skills.local"
   "basicConstraints=CA:FALSE`nkeyUsage=digitalSignature`nextendedKeyUsage=clientAuth" | Set-Content -Encoding ascii client.ext
   openssl x509 -req -in client1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out client1.crt -extfile client.ext
   ```
2. **ACM import** (엔드포인트와 같은 리전). 서버·클라이언트가 같은 CA 이므로 서버 인증서 1개만 import 하면 클라이언트 루트 체인으로도 쓸 수 있다:

   ```powershell
   $env:ADDON_VPN_CERT_ARN = aws acm import-certificate --certificate fileb://server.crt --private-key fileb://server.key --certificate-chain fileb://ca.crt --region ap-northeast-2 --query CertificateArn --output text
   $env:ADDON_VPN_CERT_ARN
   ```
3. 키트 파일 전부를 `set-XX/task-2/module-N-vpn/terraform/` 으로 복사한다. `versions.tf` 는 `_template` 것을 쓴다.
   기존 세트 VPC 에 붙일 때는 `vpc.tf` 를 지우고 `aws_vpc.addon_vpn` → `aws_vpc.<기존>`, `aws_subnet.addon_vpn_private` → 기존 프라이빗 서브넷 map 으로 바꾼다.
4. `terraform.tfvars`:

   ```hcl
   addon_vpn_name        = "skills-client-vpn"
   addon_vpn_vpc_cidr    = "10.70.0.0/16"
   addon_vpn_private_subnets = {
     "skills-client-vpn-private-a" = { cidr = "10.70.1.0/24", az = "ap-northeast-2a" }
   }
   addon_vpn_client_cidr      = "172.16.0.0/22"   # /22 이상, VPC·로컬 LAN 과 비중복
   addon_vpn_server_cert_arn  = "arn:aws:acm:ap-northeast-2:123456789012:certificate/..."
   addon_vpn_client_root_cert_arn = ""            # 같은 CA 면 비워 둔다
   addon_vpn_split_tunnel     = true
   addon_vpn_ec2_name         = "skills-client-vpn-target"
   addon_vpn_ec2_key_name     = ""                # SSH 검증 요구 시 키 페어 이름
   ```
5. `terraform fmt` → `terraform validate` → `terraform plan` (신규 모듈이면 전부 `+`) → `terraform apply`. 엔드포인트 생성 ~1분, 서브넷 연결 `associated` 까지 5~10분.
6. **클라이언트 설정 파일** — 내보낸 `.ovpn` 에 클라이언트 인증서·키를 인라인으로 붙인다:

   ```powershell
   $ID = terraform output -raw addon_vpn_endpoint_id
   aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $ID --output text | Set-Content -Encoding ascii skills-vpn.ovpn
   "<cert>`n$(Get-Content client1.crt -Raw)</cert>`n<key>`n$(Get-Content client1.key -Raw)</key>" | Add-Content -Encoding ascii skills-vpn.ovpn
   ```
7. **AWS VPN Client 설치·접속**: <https://aws.amazon.com/vpn/client-vpn-download/> (Windows 64-bit msi) → 실행 → File → Manage Profiles → Add Profile → `skills-vpn.ovpn` 선택 → Connect. 설치 불가 환경이면 OpenVPN Connect 도 같은 파일로 붙는다.
8. 검증 (접속 후 PowerShell):

   ```powershell
   $IP = terraform output -raw addon_vpn_target_private_ip
   ping $IP
   curl.exe http://$IP/           # "hello from ... via client vpn"
   ssh -i <키.pem> ec2-user@$IP   # 키 페어를 넣었을 때만
   ```
9. 채점 체크리스트:

   | 항목 | 확인 |
   | --- | --- |
   | 엔드포인트 상태 | `aws ec2 describe-client-vpn-endpoints --query 'ClientVpnEndpoints[].[ClientVpnEndpointId,Status.Code,ClientCidrBlock,SplitTunnel]'` → `available` |
   | 연결 CIDR | 위 `ClientCidrBlock` 이 과제지 값 |
   | 인증 방식 | `AuthenticationOptions[].Type` = `certificate-authentication` |
   | 서브넷 연결 | `aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id $ID` → `Status.Code`=`associated` |
   | 인가 규칙 | `aws ec2 describe-client-vpn-authorization-rules --client-vpn-endpoint-id $ID` → VPC CIDR `active` |
   | 라우트 | `aws ec2 describe-client-vpn-routes --client-vpn-endpoint-id $ID` → VPC CIDR 경로 `active` (연결 시 자동 생성) |
   | 접속 후 private EC2 | 8번 ping·curl 성공 |
   | 로깅 | `ConnectionLogOptions.Enabled`=true, `aws logs tail /aws/clientvpn/<name>` 에 connection-attempt/connection-reset 이벤트 |
   | 접속 중 세션 | `aws ec2 describe-client-vpn-connections --client-vpn-endpoint-id $ID` → `Status.Code`=`active` |

## 블록

full tunnel(인터넷까지 VPN 경유) 요구 시 — `addon_vpn_split_tunnel = false` 로 바꾸고 새 파일 `vpn-internet.tf` 에:

```hcl
resource "aws_ec2_client_vpn_route" "addon_internet" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.addon.id
  destination_cidr_block = "0.0.0.0/0"
  target_vpc_subnet_id   = values(aws_subnet.addon_vpn_private)[0].id

  depends_on = [aws_ec2_client_vpn_network_association.addon]
}

resource "aws_ec2_client_vpn_authorization_rule" "addon_internet" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.addon.id
  target_network_cidr    = "0.0.0.0/0"
  authorize_all_groups   = true
}
```

이때 대상 서브넷 RTB 에 NAT 경로가 있어야 실제로 인터넷이 나간다 — 이 키트 VPC 에는 NAT 가 없으므로 `rds-connection/vpc.tf` 의 NAT·RTB 블록을 가져온다.

대상 EC2 SG 를 "클라이언트 CIDR 에서 허용" 으로 채점할 때:

```hcl
# aws_vpc_security_group_ingress_rule.addon_vpn_target 안에서:
# referenced_security_group_id = aws_security_group.addon_vpn.id  →
cidr_ipv4 = var.addon_vpn_client_cidr
```

단 실제 트래픽은 엔드포인트 ENI IP 로 SNAT 되어 들어오므로 CIDR 규칙만으로는 ping 이 안 된다 — 두 규칙을 모두 두면 채점·동작 모두 만족한다.

## TROUBLESHOOT — 이 KIT 고유 함정
- **인증서가 먼저**: `addon_vpn_server_cert_arn` 은 기본값 없음 — ACM ARN 없이는 plan 이 멈춘다. 서버 인증서에 `extendedKeyUsage=serverAuth` 가 없으면 `InvalidParameterValue: certificate is not a server certificate`. CA 와 엔드포인트 리전이 같아야 한다.
- `client_cidr_block` 은 **/22~/12**, VPC CIDR·클라이언트 PC 의 로컬 대역(사내 192.168.x 등)과 겹치면 안 된다. 엔드포인트 생성 후 변경은 ⚠ 재생성.
- ⚠ 재생성 항목: `client_cidr_block`, `server_certificate_arn`, `authentication_options`, `transport_protocol`, `vpc_id`. in-place: `split_tunnel`, `security_group_ids`, `connection_log_options`, `description`.
- 네트워크 연결은 **서브넷당 시간 과금** + 연결 완료 5~10분. 서브넷 2개를 넣는 건 과제지가 HA 를 명시할 때만.
- 연결만 하면 VPC CIDR 라우트는 자동 생성되지만 **인가 규칙이 없으면 트래픽이 전부 드롭**된다. 인가 규칙 `active` 까지도 수 분.
- 로그 그룹·스트림은 엔드포인트보다 먼저 있어야 한다 (의존성으로 보장됨). `cloudwatch_log_stream` 이름은 임의.
- `.ovpn` 에 `<cert>/<key>` 를 안 넣으면 AWS VPN Client 가 "profile 이 유효하지 않음" 으로 거부한다. `Set-Content -Encoding ascii` 로 BOM 없이 저장 (UTF-8 BOM 이 붙으면 파싱 실패).
- 대회 PC 에 AWS VPN Client 설치 권한이 없을 수 있다 — 감독에게 먼저 확인. 설치 불가면 연결 검증은 건너뛰고 describe-* 체크리스트까지만.
- 클라이언트 IP 는 VPC 안에서 **엔드포인트 ENI IP 로 SNAT** 된다. 대상 EC2 SG 의 소스는 엔드포인트 SG (`aws_security_group.addon_vpn`) 로 잡는다. 클라이언트 CIDR 소스 규칙만 두면 ping 이 안 된다.
- 대상 EC2 는 인터넷 경로가 없어 SSM 으로 못 들어간다. 내부 확인은 VPN 접속 후 SSH(키 페어) 뿐.
- `terraform destroy` 는 네트워크 연결 해제에 수 분이 걸리고, 활성 VPN 세션이 있으면 클라이언트에서 먼저 Disconnect.
- `session_timeout_hours`·`self_service_portal`·`client_login_banner_options` 는 넣지 않았다 — 과제지가 요구하면 provider 6.x 문서로 인자명 **확인 필요** 후 `aws_ec2_client_vpn_endpoint` 에 추가.

## 실전 구현 (참고용)

없음. VPC 패턴만 set-08 task-2 module-3-event-handling `terraform/vpc.tf`.

---

## 막히면 여는 순서

인자 이름이나 조합에서 막히면 ① 위 **실전 구현**(이미 apply 가 통과한 코드) → ② 로컬 스키마 명령 → ③ 공식 문서 순으로 연다. 대회장 인터넷은 공식 문서까지 열려 있다. 그래도 ①②를 먼저 여는 건 브라우저보다 빠르고, 블로그에서 인자 이름을 베껴 프로바이더·차트 버전이 어긋나는 일이 없어서다.

```powershell
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["<리소스타입>"].block.attributes | keys'
aws <서비스> <명령> help
kubectl explain <리소스>.spec --recursive
```

리소스별 공식 문서 주소·이 저장소의 구현 위치·흔히 막히는 인자는 [DOC-LINKS 4절 리소스별 색인](../../../DOC-LINKS.md#4-리소스별-색인)에 한 줄씩 있다. 리소스 타입(`aws_s3_bucket` 등)으로 Ctrl+F 한다.

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), 세트별 리소스 주소는 [대조표](../../../KIT-INDEX.md#세트별-리소스-주소-대조표-task-1)(표에 없는 세트는 [주소 찾는 명령](../../../KIT-INDEX.md#표에-없는-세트는-직접-찾는다)), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
