**DEPLOYSHOP · CORE REVIEW**

# AWS MSA 핵심 개념 복습

> 선택 이유 · 동작 원리 · 리소스 관계.

[문서 목록](../README.md) · [상세 복습](STUDY-NOTES.md) · [실행 결과](../VALIDATION.md)

---

- **인프라·인증** · [01 네트워크](#01-네트워크-경로를-구분해야-하는-이유) · [02 Terraform](#02-terraform이-자원과-상태를-관리하는-방식) · [03 권한·Secret](#03-인증권한secret을-분리하는-이유)
- **배포·운영** · [04 이미지·배포](#04-이미지-게시와-실제-배포를-구분하는-이유) · [05 Pod·노드 확장](#05-pod와-노드의-확장을-나누는-이유) · [06 DNS·TLS](#06-dnstls서비스-상태를-별도로-확인하는-이유)
- **데이터·검증** · [07 관측·영구 저장](#07-관측영구-저장복원을-분리하는-이유) · [08 최종 점검](#08-운영-검증과-재구축에서-기억할-것)

---

## 01. 네트워크 경로를 구분해야 하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| **Region·AZ·Subnet의 관계** | Region 안에 여러 AZ가 있고 Subnet은 한 AZ에 속함. 서비스별 전용 EC2가 아니라 여러 Pod를 노드에 배치 |
| **접속 목적지와 허용 출발지를 구분하는 이유** | Workbench의 목적지는 **RDS Endpoint**, 보안 그룹의 허용 출발지는 **PC 공인 IP/32**. 사설 IP·Gateway와 구분 |
| **Public·Private을 라우팅으로 판단하는 이유** | Subnet 이름보다 경로·주소·보안 조건 확인. 개인 프로젝트의 Private DB Subnet 정의가 실제 Private RDS 배치를 뜻하지 않음 |
| **NAT와 Load Balancer가 함께 필요한 이유** | NAT Gateway는 Private 자원이 시작한 외부 연결, LB는 외부 요청의 앱 전달을 담당. NAT Gateway는 임의의 외부 신규 연결을 받는 포트포워딩 대체재가 아님 |
| **NLB와 Ingress를 나누는 이유** | NLB는 L4 연결 전달, Ingress NGINX는 HTTP Host·Path 라우팅과 TLS 종료 담당 |
| **다중 AZ와 고가용성이 다른 이유** | 두 AZ에 Subnet이 있어도 Single-AZ RDS에 대기 DB가 생기지 않음. NAT 1개·Single-AZ DB는 각 장애의 영향 범위가 남음 |

> **암기** · 공인 IP는 출발지이고 Endpoint는 목적지입니다. NAT는 외부 통신을, LB는 요청 진입을 담당합니다. [AWS NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)

---

## 02. Terraform이 자원과 상태를 관리하는 방식

| 핵심 개념 | 원리·적용 |
|---|---|
| **Root·Child 변수 범위가 독립적인 이유** | 모듈은 별도 인터페이스. `bucket_name = var.s3_bucket_name`의 왼쪽은 Child 입력, 오른쪽은 Root 값. 자동 공유되지 않음 |
| **Provider·Resource·Data Source의 역할** | Provider는 API 연동, Resource는 자원 관리, Data Source는 조회, Output은 결과 전달 |
| **생성 순서가 파일 순서와 다른 이유** | 값 참조로 의존성을 구성. 참조에 드러나지 않는 선행 조건은 `depends_on`으로 표현 |
| **State를 보존해야 하는 이유** | 코드 주소와 실제 자원의 관계 등을 기록. **State 삭제는 AWS 자원 삭제가 아니며**, 관리 정보 손실을 일으킬 수 있음 |
| **sensitive와 실제 비밀값 보호의 차이** | 일반 출력 가림과 암호화는 별개. State·tfvars의 저장·접근·Git 추적을 따로 관리 |

> **암기** · validate는 구성 검사, plan은 변경 계획, apply는 실행입니다. 정적 검사만으로 실제 권한·연결·기능 성공을 보장하지 않습니다. [Terraform 의존성](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)

---

## 03. 인증·권한·Secret을 분리하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| **IAM 신원과 CLI Profile의 차이** | IAM은 AWS 신원, Profile은 로컬 인증 설정 이름. 구축 사용자·노드·Pod·CI의 권한은 용도별로 구분 |
| **DB 비밀번호와 Kubernetes Secret의 관계** | Terraform은 RDS 인증값을 설정하고 `my-app-secrets`는 앱에 `DB_HOST`·`DB_PW` 전달. 같은 값이어야 하며 수동 Secret은 자동 갱신되지 않음 |
| **Secret별 역할을 나누는 이유** | 앱 DB 인증, Product의 S3 키, Actions의 AWS 인증은 서로 다른 소비자·용도. 같은 관리자 키를 공통 사용하지 않음 |
| **IRSA에 신뢰 조건이 필요한 이유** | CA·EBS CSI의 ServiceAccount를 OIDC로 IAM Role과 연결. Trust의 audience·subject로 역할 사용 대상을 제한 |

> **암기** · 신뢰 정책은 역할 사용자, 권한 정책은 허용 작업, Secret은 앱에 전달할 값을 정의합니다.

---

## 04. 이미지 게시와 실제 배포를 구분하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| **Image·Container·ECR의 관계** | Image는 실행 내용, Container는 실행 인스턴스, ECR은 이미지 저장소. push 성공만으로 Pod가 교체되지 않음 |
| **latest와 버전별 태그의 차이** | latest는 같은 이름의 내용이 바뀔 수 있음. 커밋 태그·Digest는 실행 버전 추적·재현·롤백을 명확하게 함 |
| **직접 배포도 CD인 이유** | 개인 프로젝트는 Actions가 apply·restart로 배포하고 Argo CD가 선언을 동기화. Argo CD 단독 이미지 배포와 구분 |

> **암기** · 코드 변경·이미지 게시·배포·실제 응답은 각각 확인합니다. Actions 직접 배포와 Argo CD 선언 동기화를 병행합니다.

---

## 05. Pod와 노드의 확장을 나누는 이유

```text
Metrics Server → HPA가 Deployment 목표 replicas 변경
  → Deployment Controller가 ReplicaSet 조정
  → ReplicaSet Controller가 Pod 생성·삭제
  → Scheduler가 노드 선택 → kubelet이 실행 관리

배치할 공간 부족 → CA가 ASG 용량 조절 → 새 노드 → Pod 배치
```

| 핵심 개념 | 원리·적용 |
|---|---|
| **HPA·CA·Ingress의 역할 차이** | HPA는 목표 Pod 수, CA는 노드 용량, Ingress는 HTTP 라우팅. 서로 대신하지 않음 |
| **requests가 확장 해석에 중요한 이유** | 스케줄링 자원 기준이자 CPU HPA 이용률의 분모. 노드 전체 CPU 사용률과 같은 수치가 아님 |
| **Pending과 Ready를 구분하는 이유** | Phase와 준비 조건은 별개. CA가 미리 대기 Pod를 만드는 것이 아니라 스케줄링 불가능한 Pod 등을 고려 |
| **HPA와 Argo CD의 제어 책임을 나누는 이유** | replicas는 HPA, 나머지 선언은 Argo CD. `/spec/replicas` 제외와 `RespectIgnoreDifferences=true`로 충돌 방지 |

> **적용** · Product Pod `1→5→1`과 노드 `2→3`을 확인했습니다. replicas는 HPA가, 나머지 배포 선언은 Argo CD가 관리합니다.

---

## 06. DNS·TLS·서비스 상태를 별도로 확인하는 이유

```text
DNS: 도메인 → Route 53 레코드 → 접속 주소
요청: 사용자 → LB → 경로 라우팅 → Service → Pod
TLS: 발급 요청 → 도메인 검증 → 인증서 → TLS 종료 지점에서 사용
```

| 핵심 개념 | 원리·적용 |
|---|---|
| **DNS 반영이 앱 배포를 뜻하지 않는 이유** | DNS는 주소 해석. Ingress·Certificate·Secret·Pod는 별도 생성·검증 대상 |
| **인증서 발급과 TLS 종료를 구분하는 이유** | cert-manager가 발급·갱신을 관리하고 TLS Secret 생성. Ingress NGINX가 Secret을 참조해 HTTPS 처리 |
| **Synced·Healthy·실제 응답을 구분하는 이유** | 각각 선언 일치·리소스 상태 판정·관측한 요청 결과. 어느 하나가 전체 기능 성공을 보장하지 않음 |

> **암기** · 인증서 pending 발생 시 DNS·검증 경로·Issuer 순서로 원인을 확인합니다. [Alias·CNAME](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)

---

## 07. 관측·영구 저장·복원을 분리하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| **Prometheus·Grafana·HPA의 역할** | 지표 수집·저장 / 시각화 / 지표에 따른 확장 목표 조절. Metrics Server는 현재 CPU HPA의 지표 경로 |
| **Grafana 메모리와 저장소를 따로 개선한 이유** | OOM은 실행 자원 문제, 설정 소실은 영구 저장 문제. 메모리 조정과 EBS PVC 연결을 각각 적용 |
| **PVC·CSI·EBS의 관계** | StorageClass·PVC 요청을 바탕으로 CSI가 볼륨 생성·연결. EBS AZ·노드 자원·배치 조건이 함께 맞아야 함 |
| **데이터 유지와 백업 복원이 다른 이유** | 기존 PVC 유지·Bound는 연결 상태. 데이터 내용을 별도로 대조하며 Retain은 백업이 아님 |
| **경보 전달과 실제 부하 검증의 차이** | 수동 ALARM은 SNS 전달 경로 확인. 실제 CPU 임계값 초과 검증과 구분 |

> **적용 범위** · Grafana EBS 5Gi와 재시작 후 설정 유지를 확인했습니다. Prometheus에는 영구 볼륨을 적용하지 않았습니다.

---

## 08. 운영 검증과 재구축에서 기억할 것

- **배포 검증:** Workflow·rollout·Argo CD·웹/API·DB를 각각 확인합니다. 관측한 요청 표본을 무중단 보장으로 확대하지 않습니다.
- **문제 해결:** 증상→원인→조치→재검증으로 설명합니다. HPA replicas 충돌과 Certificate 중복 관리는 별개의 문제입니다. [문제 분석 및 해결](../TROUBLESHOOTING.md)
- **재구축:** OIDC·kubeconfig·NLB·RDS Endpoint·Secret·볼륨 연결을 다시 확인합니다. 코드 보존은 데이터 백업을 대신하지 않습니다.
- **종료:** Terraform 밖의 자원, EBS·스냅샷·S3 버전·로그를 별도로 확인합니다. 자원 중지·삭제·비용 종료는 다른 작업입니다.
