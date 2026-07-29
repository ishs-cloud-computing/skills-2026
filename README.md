# 2026 전국기능경기대회 클라우드컴퓨팅

![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)

2026 전국기능경기대회 **클라우드컴퓨팅** 직종의 사전 공개 과제(1·2과제)를
**Terraform / eksctl / Kubernetes manifest** 로 관리하는 저장소.

대회 전 약 10세트가 공개되며 이 중에서 출제된다. 세트마다 사용 서비스 조합이 다르므로
**구조만 통일하고 내용은 세트별로 채운다.** 트러블슈팅 시 항상 과제지(`task.pdf`)와
채점지(`mark.pdf`)를 확인한다.

## 시작하기

### 요구사항

- [Git](https://git-scm.com/), [Git-LFS](https://git-lfs.com/)
- [mise](https://github.com/jdx/mise)

### 설치

1. Repository 클론 또는 다운로드

```bash
git clone https://github.com/ishs-cloud-computing/skills-2026.git
cd skills-2026
```

2. `mise`로 툴 설치

```bash
mise install
```

3. 로컬 문서 시작
```bash
cd docs/
npm install
cd ..
mise docs
```

## 학습 가이드

치트시트, 트러블슈팅 관련 문서는 해당 학습 가이드를 참고해주세요!

- 주소: https://skills-learn.zenru.net/ ( 임시 로그인: user / bruh1004pass )
- 기여: 김우진 @rladnwls122

## 진행 상황

세트는 `set-01` ~ `set-10` 으로 구성된다.

상태: ⬜ 미착수 · 🟡 진행 중 · ✅ 완료

| 세트 | 1과제 | 2과제 | 비고 |
|------|:-----:|:-----:|------|
| [set-01](set-01/) | ⬜ | ⬜ | |
| [set-02](set-02/) | ✅ | ✅ | 1, 2과제 🥇 |
| [set-03](set-03/) | ✅ | ⬜ | 1과제 🥉 |
| set-04 | - | - | 폐기됨 |
| [set-05](set-05/) | ✅ | 🟡 | |
| [set-06](set-06/) | 🟡 | ⬜ | 1과제 🥉 |
| [set-07](set-07/) | ✅ | ⬜ | 1, 2과제 🥈, 1과제 채점 9-1 A 9-2 A 미해결|
| [set-08](set-08/) | ✅ | ⬜ | 2과제 🥈 |
| [set-09](set-09/) | ✅ | ⬜ | |
| [set-10](set-10/) | ⬜ | ⬜ | |

## 대회 구조

- 1·2과제만 사전 공개되며 이 중에서 출제된다.
- **1과제**: 단일 과제. 보통 단일 리전 종합 인프라.
- **2과제**: 독립 모듈 여러 개로 구성.
- **3과제**: 1시간 이내에 요구된 서비스를 구축 후 트래픽 처리.
- 각 세트의 구체적인 서비스 구성은 해당 세트의 README나 과제지를 참고한다.

## 디렉토리 구조

```
skills-2026/
├── set-01/ ~ set-10/        # set-08 제외, 모두 동일 구조
│   ├── task-1/              # 단일 과제
│   │   ├── terraform/       # AWS 리소스
│   │   ├── eksctl/          # 클러스터/노드그룹 (EKS 과제일 때만)
│   │   ├── k8s/             # k8s 리소스 (번호 prefix로 apply 순서)
│   │   ├── app/             # 컨테이너 소스 (필요할 때만)
│   │   ├── task.pdf         # 과제지
│   │   ├── mark.pdf         # 채점지
│   │   └── mark.sh          # 채점 스크립트
│   └── task-2/              # 독립 모듈 여러 개
│       ├── module-N-<name>/ # 구현: 모듈별 terraform/ eksctl/ k8s/ app/ 중 필요한 것만
│       ├── provided/        # 대회 제공 소스 (세트마다 다름), module1/ module2/ ... 모듈별 분리
│       ├── mark/            # 모듈별 채점 스크립트 mark2-1.sh, mark2-2.sh ...
│       └── ...              # 모듈 수는 세트마다 다름
├── shared/
│   ├── modules/             # 재사용 Terraform 모듈 (vpc, eks 등)
│   └── scripts/
└── .github/                 # 세트 트래킹용 이슈 / PR 템플릿
```

하위 디렉토리(`terraform/`, `eksctl/`, `k8s/`, `app/`)는 **해당 과제에 필요한 것만** 만든다.

## Maintainer

- 성준혁 ([@zenru1023](https://github.com/zenru1023))

## License

This project is licensed under the [Apache License 2.0](LICENSE).
