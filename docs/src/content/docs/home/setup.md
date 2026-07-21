---
title: 환경설정
description: 환경설정 방법을 안내합니다.
---

skills-2026을 위한 환경설정을 하는 방법을 안내합니다.

## 요구 사항

- [Git](https://git-scm.com/), [Git-LFS](https://git-lfs.com/)
- [mise](https://mise.jdx.dev/)
- terraform (mise로 설치됨)
- eksctl
- kubectl

> [lab-bootstrap](https://github.com/ishs-cloud-computing/lab-bootstrap)을 사용하여 실습실에서 간편하게 설치할 수 있습니다.

## 설치

1. 저장소 복제 또는 다운로드

```bash
git clone https://github.com/ishs-cloud-computing/skills-2026.git
cd skills-2026
```

2. mise로 툴 설치

```bash
mise install
```

> mise는 nodejs 24 LTS, terraform을 설치합니다.

## 로컬 문서

저장소 `docs/` 폴더에 있는 문서를 로컬로 실행할 수 있습니다.

```bash
cd docs/
npm install
cd ../
mise docs
```