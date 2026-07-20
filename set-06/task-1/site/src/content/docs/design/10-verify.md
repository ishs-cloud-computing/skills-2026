---
title: "검증 시드"
sidebar:
  order: 10
---

```bash
CF=https://$(cd terraform && terraform output -raw cloudfront_domain)

curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" $CF            # 200 Miss
curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" $CF/index.html # 200 Hit
curl -sX POST -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Busan2025"}' $CF/v1/book
curl -s $CF/reservation
curl -s "$CF/reservation?client_id=C001"
curl -s -w " %{http_code}\n" $CF/v1/book                       # Method Not Allowed 405
curl -s -w " %{http_code}\n" "$CF/reservation?client_id=123abc" # Access Denied 403
kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers   # gj2026.<id>.(addon|app).node
kubectl run nginx-test -n skills --image=<ECR>/ecr-public/nginx/nginx:latest --restart=Never
kubectl exec -n skills nginx-test -- curl -m 5 -sS http://book-svc:8080/health   # timeout 이어야 정상
aws logs describe-log-streams --log-group-name /eks/book-svc/access             # 스트림 2개
```

로컬 실측(동일 md5 바이너리를 set-08에서 확인): `GET /health`→200, 미정의 경로→404, DDB 미연결 POST→500, 액세스 로그는 위 §3.11 평문 형식.
