# ec2-asg-alb 부착 스니펫

기존 단일 EC2 + ALB 구성에 Launch Template + Auto Scaling Group + CPU target tracking 을 얹어 고가용성 변형에 대응한다.
2과제 분석 모듈(set-02 task-2 module-2-analytics) 의 당일 추가 문항("EC2 를 Auto Scaling 으로", "ALB 뒤 2대 이상 + CPU 스케일링") 용.
1과제는 인프라 스케일링 문항이 출제되지 않으므로 2과제 전용이다.

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체를 `init`/`apply` 하지 않으므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 파일

- `ec2-asg.tf` — AL2023 AMI 조회 · `aws_launch_template`(IMDSv2·인스턴스 프로파일·user data) · `aws_autoscaling_group`(기존 TG 등록, ELB 헬스체크) · `aws_autoscaling_policy`(target tracking CPU)
- `variables.tf` — `addon_asg_*` 변수. 서브넷·SG·인스턴스 프로파일·TG ARN 은 기존 리소스를 변수로 받는다

## 부착 절차

1. `ec2-asg.tf`·`variables.tf` 를 `set-XX/task-2/module-N/terraform/` 으로 복사한다.
2. `ec2-asg.tf` 의 `locals.addon_asg_user_data` 를 기존 `aws_instance` 의 `user_data` 표현식을 `base64encode(...)` 로 감싼 것으로 바꾼다 (tfvars 에서는 함수를 못 쓴다).

   ```hcl
   addon_asg_user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
     app_py       = file("${path.module}/../../provided/module2/app.py")
     requirements = file("${path.module}/../../provided/module2/requirements.txt")
     stream_name  = aws_kinesis_stream.orders.name
     region       = var.region
     app_port     = var.app_port
   }))
   ```

3. `terraform.tfvars` 에 값을 넣는다. 같은 state 의 리소스를 직접 참조하려면 `var.addon_asg_subnet_ids` 를 `[for n in ["analytics-priv-a", "analytics-priv-c"] : aws_subnet.this[n].id]`, `var.addon_asg_security_group_ids` 를 `[aws_security_group.app.id]`, `var.addon_asg_instance_profile_name` 을 `aws_iam_instance_profile.app.name`, `var.addon_asg_target_group_arns` 를 `[aws_lb_target_group.app.arn]` 으로 바꾼다.

   ```hcl
   addon_asg_name                  = "wsc2026-app-asg"
   addon_asg_instance_name         = "wsc2026-analytics-app"
   addon_asg_instance_type         = "t3.small"
   addon_asg_subnet_ids            = ["subnet-0aaa", "subnet-0bbb"]
   addon_asg_security_group_ids    = ["sg-0ccc"]
   addon_asg_instance_profile_name = "wsc2026-alaytics-ec2-role-profile"
   addon_asg_target_group_arns     = ["arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/wsc2026-app-tg/abc"]
   addon_asg_min_size              = 2
   addon_asg_max_size              = 4
   addon_asg_desired_capacity      = 2
   addon_asg_cpu_target            = 50
   ```

4. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 `aws_instance`·`aws_lb_target_group_attachment` 에 diff 가 없는지 확인한다.
5. `terraform apply`. 확인: `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <이름> --query 'AutoScalingGroups[0].Instances[].HealthStatus'`, `aws elbv2 describe-target-health --target-group-arn <TG>` 에 ASG 인스턴스가 `healthy`.

## 블록

기존 ALB 리스너·TG 는 그대로 쓴다. ASG 를 붙일 TG 를 새로 만들라는 문항이면 `set-02/task-2/module-2-analytics/terraform/alb.tf` 의
`aws_lb_target_group.app` 을 복사해 이름만 바꾸고 `addon_asg_target_group_arns` 에 넣는다.

### 스케줄·단계 정책 변형

```hcl
# CPU 대신 ALB 요청 수 기준이면 aws_autoscaling_policy 의 target_tracking_configuration 을:
predefined_metric_specification {
  predefined_metric_type = "ALBRequestCountPerTarget"
  resource_label         = "${aws_lb.analytics.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
}
target_value = 100
```

## 함정

- **기존 단일 EC2 를 지우지 않는다**(당일 변동은 추가 방식). TG 에 기존 인스턴스 + ASG 인스턴스가 같이 등록된다. 기존 채점 항목이 "인스턴스 1대" 를 세거나 Name 태그로 1대를 고르면 `addon_asg_instance_name` 을 기존 인스턴스와 **다른 이름** 으로 둔다.
- user data 가 NAT 경유 pip 설치를 하면 `health_check_grace_period` 를 설치 시간보다 길게(기본 300) 둔다 — 짧으면 ELB 헬스체크 실패로 인스턴스가 계속 교체된다.
- Launch Template 은 `name_prefix` + `create_before_destroy` 라 변경 시 새 버전이 만들어지고 ASG 는 `$Latest` 를 따른다. 기존 인스턴스는 자동 교체되지 않는다 — 교체가 필요하면 `aws autoscaling start-instance-refresh --auto-scaling-group-name <이름>`.
- `desired_capacity` 는 `ignore_changes` 다 — 스케일링 후 plan 에 diff 가 나지 않게 하기 위함. 값을 바꾸려면 tfvars 수정 후 `terraform apply -replace` 가 아니라 콘솔/CLI 로 조정하거나 ignore_changes 를 잠시 뺀다.
- ASG 이름·min/max/desired·정책 타입은 채점 스크립트가 describe-auto-scaling-groups 로 읽는 값이다. tfvars 로만 바꾼다.
- 인스턴스 프로파일에 `AmazonSSMManagedInstanceCore` 가 없으면 채점용 send-command 가 실패한다 — 기존 프로파일을 그대로 쓴다.
- 기존 SG 가 ALB SG 로부터 앱 포트 ingress 만 허용하는지 확인한다 — ASG 인스턴스도 같은 SG 를 쓰므로 추가 규칙 불필요.

## 실전 구현 (참고용)

- `set-02/task-2/module-2-analytics/terraform/ec2.tf` — 단일 인스턴스(IMDSv2·gp3·user data)
- `set-02/task-2/module-2-analytics/terraform/userdata.sh.tpl` — 앱 설치 + systemd
- `set-02/task-2/module-2-analytics/terraform/alb.tf` — ALB·TG·리스너
- ASG 실전 구현: 없음
