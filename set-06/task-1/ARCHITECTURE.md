# set-06 / task-1 — 설계 근거·함정·검증

README 런북이 "어떻게 배포하나"라면, 이 문서는 "왜 이렇게 설계했나 / 무엇을 검증해야 하나"이다.

## 네트워크 (요구사항 3, 채점 1-1~1-3)

- Private subnet 2개(`10.0.10.0/24` a, `10.0.11.0/24` b)만 둔다. public/NAT 없음 → `describe-nat-gateways length=0`.
- IGW(`gj2026-igw`)는 **VPC 에 attach 만** 한다(CloudFront VPC Origin 요건). 어떤 라우트 테이블에도 IGW 라우트를 넣지 않으므로 인터넷 통신 불가.
- 라우트 테이블 `gj2026-private-rtb-a/b` 는 **local(10.0.0.0/16) 라우트만** 존재해야 한다(채점 1-2 정확 일치). 따라서 `aws_route` 를 만들지 않고, **S3/DynamoDB 도 Gateway EP 가 아닌 Interface EP**(+ Route53 PHZ)로 붙인다. Gateway EP 는 RTB 에 prefix-list 라우트를 추가해 1-2 를 깨뜨린다.
- `eks`/`eks-auth` Interface EP 는 만들지 않는다(그 PHZ 가 `oidc.eks.*` 조회를 가로채 IRSA 파괴). 대신 클러스터 endpoint 는 public+private 둘 다 ON 이라 CloudShell 에서 kubectl 이 동작한다(채점 4-1).
- Bastion 없음: public subnet 이 없고 관리가 CloudShell(public endpoint)로 가능하다.

## 노드명 커스텀 (채점 4-3) — ⚠️ 실 AWS 검증 필요(R1)

요구: 노드명 `gj2026.<instance_id>.{addon,app}.node` (채점은 `cut -d. -f2` 로 instance-id 추출).
Bottlerocket 의 `hostname-override-source=instance-id` 는 `i-xxxx` 만 만들 뿐 prefix/suffix 보간이 안 된다. 그래서 부팅 시 IMDS 로 instance-id 를 읽어 `apiclient set kubernetes.hostname-override=...` 를 호출하는 **bootstrap container** 를 사용한다(`app/bootstrap/`). eksctl `managedNodeGroups[].bottlerocket.settings.bootstrap-containers` 로 주입하며 role("addon"/"app")은 base64 user-data 로 전달한다.

검증 포인트:
1. EKS managed nodegroup 이 주입하는 `settings.kubernetes.{api-server,cluster-certificate,cluster-name}` 가 bootstrap container 설정과 **머지**되어 노드가 정상 조인하는지(1개 노드로 먼저).
2. `kubectl get nodes` 가 `gj2026.i-xxxx.app.node` 로 보이는지.
3. bootstrap 이미지(`gj2026-bootstrap`)가 노드 부팅 시 ECR(인스턴스 롤)로 pull 되는지.

## book 앱 "ALB만 수신" (요구사항 8, 채점 4-5)

클러스터 내 Pod(`nginx-test`)→`book-svc:8080` 은 timeout, ALB→book 은 정상이어야 한다.
- **NetworkPolicy 불가**: Pod 와 ALB ENI 가 같은 /24 에서 IP 를 받아 ipBlock 으로 구분 불가. default-deny 는 ALB(504)도 막는다.
- **Security Groups for Pods** 채택: vpc-cni `ENABLE_POD_ENI=true` + `POD_SECURITY_GROUP_ENFORCING_MODE=strict`. `SecurityGroupPolicy`(app=book) 로 `gj2026-book-pod-sg`(ALB SG→8080 만 허용) 부여. strict 라 동일 노드 트래픽도 Pod SG 로 강제 → nginx-test 가 어느 노드에 뜨든 차단.
- strict 는 kubelet probe 도 막으므로 book Deployment 는 **probe 없음**. 헬스는 ALB TG health check(`/health`, ALB SG 출처)로 판정. scratch 이미지라 exec probe 도 불가.
- grafana Pod 는 SGP 미적용(노드 ENI). ALB→grafana(3000)는 `gj2026-eks-shared-node-sg`(애드온 노드 attach)로 허용.

## book 이미지 <3MB (채점 2-2)

제공 바이너리(8.7MB static Go, **수정 금지**)를 그대로 scratch 에 담는다. 단독 gzip≈3.34MB(초과), **zstd(level19)≈2.6MB**. ECR 은 zstd 레이어를 그대로 저장하므로 `imageSizeInBytes`<3MB. 바이너리는 미변경(zstd 는 전송 압축일 뿐). CA 인증서(~230KB)는 DynamoDB(VPCe) HTTPS 검증에 필요해 포함. scratch 라 ECR 스캔은 불가하나 채점 2-2 는 크기만 본다.

## DynamoDB 쓰기 제한 (채점 3-3)

리소스 기반 정책에서 쓰기 액션을 `aws:PrincipalArn` 가 `gj2026-book-app-role`(및 assumed-role)이 **아닌** 모든 principal 에 대해 explicit Deny. 명시적 Deny 가 admin 의 identity Allow 도 무력화 → CloudShell admin put-item 이 AccessDenied. 읽기(Lambda/book read)는 영향 없음. 역할명은 eksctl `roleName` 으로 고정해 정책과 일치시킨다.

## CDN + Lambda + WAF (채점 8·9)

- CloudFront `gj2026-cdn`: 기본=S3(캐시) + viewer-request CloudFront Function(확장자 없으면 `/index.html`). `/v1/*`·`/grafana*`→ALB VPC origin(무캐시, 쿼리 전달), `/reservation*`→Lambda Function URL(무캐시).
- Lambda(`gj2026-book-reservation`, py3.14, VPC): `client_id` 없으면 Scan, 있으면 GSI Query. 응답은 `[{username,email,concert_name},...]`. 매 호출 client_id별(없으면 ALL) CloudWatch `PutMetricData`.
- WAF(CLOUDFRONT scope, us-east-1):
  - `/v1/book` 에 POST 외 메서드 → 405 "Method Not Allowed".
  - `/reservation` 의 client_id 가 유효형식이 아니면 → 403 "Access Denied". RE2 는 lookahead 미지원이라 **유효=`^[A-Za-z][A-Za-z0-9]*$` AND `[0-9]` 포함** 두 정규식 AND 로 표현하고 NOT 으로 차단. 벡터: `C001`✓ / `123abc`✗ / `C@001`✗ / `홍길동`✗.

## 모니터링 (채점 10)

- Lambda → CloudWatch `gj2026/Reservation` `Invocations`(dim client_id). Grafana(IRSA)가 CloudWatch 데이터소스로 `WSI Dashboard` 에 시각화. admin/`Skills53#`, `/grafana` sub-path.
- Fluent Bit DaemonSet `aws-for-fluent-bit`(logging): book 액세스 로그(JSON, `remote_addr`)를 Lua 필터로 IP 3옥텟 판별(10→a, 11→b) → `log_stream_template $(az_stream)` 로 `/eks/book-svc/access` 의 AZ별 스트림 분리. 채점 10-1 이 로그 그룹을 매번 삭제하므로 `auto_create_group true`.

## 검증 시드 (CloudFront 배포 후, mark.sh 와 동일 흐름)

```bash
# 8-2 예약 생성(앱→DynamoDB)
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Busan2025"}' \
  "https://$CF_DOMAIN/v1/book"
# 8-3 전체 조회 / 8-4 단건 조회(Lambda)
curl -s "https://$CF_DOMAIN/reservation"
curl -s "https://$CF_DOMAIN/reservation?client_id=C001"
# 9-1 405 / 9-2 403
curl -s -w ' %{http_code}\n' "https://$CF_DOMAIN/v1/book"
curl -s -w ' %{http_code}\n' "https://$CF_DOMAIN/reservation?client_id=123abc"
# 4-5 ALB-only (timeout 이어야 정상)
kubectl run nginx-test -n skills --image=$ECR_PUBLIC_NGINX --restart=Never -- sleep 3600
kubectl exec -n skills nginx-test -- curl -m 5 -sS http://book-svc:8080/health
```

## 잔존 위험 (실 AWS 검증 항목)

- **R1** Bottlerocket bootstrap container + EKS user-data 머지(노드 조인·노드명). 최우선 검증.
- **R6** Lambda Function URL 을 CloudFront custom origin(`https-only`)으로 사용. 필요 시 OAC(lambda) 추가 또는 AuthType 유지.
- vpc-cni `ENABLE_POD_ENI` 가 book Pod 스케줄 **전에** 적용되는지(addon 먼저).
- Grafana CloudWatch 데이터소스가 `monitoring` Interface EP 로 GetMetricData/ListMetrics 에 도달하는지.
- addon 버전은 클러스터 기본값 사용. 대회 당일 `eksctl utils describe-addon-versions --kubernetes-version 1.35` 로 확인 후 고정 가능.
