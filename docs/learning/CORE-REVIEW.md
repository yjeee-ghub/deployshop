# AWS MSA 핵심 개념 복습

여러 프로젝트에서 반복해 확인한 개념을 **선택 이유·동작 원리·검증 기준**으로 정리했습니다. 세부 명령과 구축 순서는 [상세 복습 노트](STUDY-NOTES.md), 개인 프로젝트 실행 근거는 [검증 결과](../VALIDATION.md)를 참고합니다.

## 프로젝트별 구현 범위

| 영역 | 개인 deployshop | 팀 aws-eks-final-project |
|---|---|---|
| 진입·TLS | NLB · Ingress NGINX · cert-manager | 공유 ALB · ACM |
| 배포 | Access Key · latest · Actions 직접 배포 + Argo CD 동기화 | OIDC · 커밋 태그 · PR 승인 · Argo CD 배포 |
| Terraform State | Local State | Bootstrap · S3 원격 State · 잠금 |
| DB 접근·인증값 | Public RDS · 최종 PC /32 · 수동 Secret | Private RDS · Secrets Manager · ESO |
| 운영·데이터 | Grafana EBS · 메트릭·경보 | 내부 배포 검증 · 주문 알림 · 스냅샷 복원 추가 |

팀의 기술을 개인 프로젝트 완료 기능으로 합치지 않습니다. 아래 **[팀]**은 팀 프로젝트에서 추가로 학습한 내용입니다.

## 01. 네트워크 경로를 구분해야 하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| Region·AZ·Subnet의 관계 | Region 안에 여러 AZ가 있고 Subnet은 한 AZ에 속함. 서비스별 전용 EC2가 아니라 여러 Pod를 노드에 배치 |
| 접속 목적지와 허용 출발지를 구분하는 이유 | Workbench의 목적지는 **RDS Endpoint**, 보안 그룹의 허용 출발지는 **PC 공인 IP/32**. 사설 IP·Gateway와 구분 |
| Public·Private을 라우팅으로 판단하는 이유 | Subnet 이름보다 경로·주소·보안 조건을 확인. 개인 프로젝트의 Private DB Subnet 정의가 실제 Private RDS 배치를 뜻하지 않음 |
| NAT와 Load Balancer가 함께 필요한 이유 | NAT Gateway는 Private 자원이 시작한 외부 연결, LB는 외부 요청의 앱 전달을 담당. NAT Gateway는 임의의 외부 신규 연결을 받는 포트포워딩 대체재가 아님 |
| NLB와 ALB의 선택 기준 | NLB는 L4 연결, ALB는 HTTP Host·Path 기반 L7 처리. **[팀]** 웹 라우팅·TLS를 ALB·ACM으로 통합 |
| 다중 AZ와 고가용성이 다른 이유 | 두 AZ에 Subnet이 있어도 Single-AZ RDS에 대기 DB가 생기지 않음. NAT 1개·Single-AZ DB는 각 장애의 영향 범위가 남음 |

**암기:** 공인 IP는 출발지, Endpoint는 목적지. NAT는 외부 통신, LB는 요청 진입. [AWS NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)

## 02. Terraform이 자원과 상태를 관리하는 방식

| 핵심 개념 | 원리·적용 |
|---|---|
| Root·Child 변수 범위가 독립적인 이유 | 모듈은 별도 인터페이스. `bucket_name = var.s3_bucket_name`의 왼쪽은 Child 입력, 오른쪽은 Root 값. 자동 공유되지 않음 |
| Provider·Resource·Data Source의 역할 | Provider는 API 연동, Resource는 자원 관리, Data Source는 조회, Output은 결과 전달 |
| 생성 순서가 파일 순서와 다른 이유 | 값 참조로 의존성을 구성. 참조에 드러나지 않는 선행 조건은 `depends_on`으로 표현 |
| State를 보존해야 하는 이유 | 코드 주소와 실제 자원의 관계 등을 기록. **State 삭제는 AWS 자원 삭제가 아니며**, 관리 정보 손실을 일으킬 수 있음 |
| sensitive와 실제 비밀값 보호의 차이 | 일반 출력 가림과 암호화는 별개. State·tfvars의 저장·접근·Git 추적을 따로 관리 |
| Bootstrap·State 분리가 필요한 이유 **[팀]** | 원격 State용 S3를 먼저 준비하고 infra·클러스터 내부 구성은 별도 Root/State로 관리. Bootstrap 자체는 Local State |
| 버전 관리와 잠금이 다른 이유 **[팀]** | S3 버전 관리는 과거 State 보관, `.tflock`은 동시 변경 충돌 방지. 주문 중복 방지용 DynamoDB와 별개 |

**암기:** validate는 구성 검사, plan은 변경 계획, apply는 실행. 정적 검사 성공이 실제 권한·연결·기능 성공을 보장하지 않습니다. [Terraform 의존성](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)

## 03. 인증·권한·Secret을 분리하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| IAM 신원과 CLI Profile의 차이 | IAM은 AWS 신원, Profile은 로컬 인증 설정 이름. 구축 사용자·노드·Pod·CI의 권한은 용도별로 구분 |
| DB 비밀번호와 Kubernetes Secret의 관계 | Terraform은 RDS 인증값을 설정하고 `my-app-secrets`는 앱에 `DB_HOST`·`DB_PW` 전달. 같은 값이어야 하며 수동 Secret은 자동 갱신되지 않음 |
| Secret별 역할을 나누는 이유 | 앱 DB 인증, Product의 S3 키, Actions의 AWS 인증은 서로 다른 소비자·용도. 같은 관리자 키를 공통 사용하지 않음 |
| OIDC에 신뢰 조건이 필요한 이유 **[팀]** | Provider 등록만으로 허용되지 않음. Trust Policy의 repo·branch 등 조건으로 Role 사용자를 제한하고 권한 정책으로 작업 범위 제한 |
| ESO와 비밀번호 변경이 다른 작업인 이유 **[팀]** | ESO는 Secrets Manager 값을 Kubernetes Secret으로 동기화. DB 비밀번호 자체 변경과 앱 재연결은 별도 단계 |
| 비밀번호 갱신 후 Pod 교체가 필요한 이유 **[팀]** | 환경 변수로 주입된 값은 기존 프로세스에 자동 재주입되지 않음. 동기화 → 새 Pod → DB-ready·로그인/API로 복구 확인 |

**암기:** 신뢰 정책은 **누가**, 권한 정책은 **무엇을**, Secret은 **어떤 값을 앱에 전달하는가**입니다. [GitHub OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) · [ESO](https://external-secrets.io/latest/introduction/overview/)

## 04. 이미지 게시와 실제 배포를 구분하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| Image·Container·ECR의 관계 | Image는 실행 내용, Container는 실행 인스턴스, ECR은 이미지 저장소. push 성공만으로 Pod가 교체되지 않음 |
| latest와 버전별 태그의 차이 | latest는 같은 이름의 내용이 바뀔 수 있음. 커밋 태그·Digest는 실행 버전 추적·재현·롤백을 명확하게 함 |
| 직접 배포도 CD인 이유 | 개인 프로젝트는 Actions가 apply·restart로 배포하고 Argo CD가 선언을 동기화. Argo CD 단독 이미지 배포와 구분 |
| PR 승인과 GitOps를 연결하는 이유 **[팀]** | 이미지 게시 → 배포 선언 PR → 리뷰·병합 → Argo CD 반영. 승인과 병합은 별개이며 보호 규칙으로 조건 강제 |
| Terraform·Helm·Kustomize의 책임 **[팀]** | Terraform은 EKS 등 인프라, Helm은 운영 도구 패키지, Kustomize는 앱 매니페스트·이미지 설정. 앱 YAML이 EKS 자체를 만드는 것은 아님 |
| CodeBuild 내부 검증을 사용하는 이유 **[팀]** | Actions가 요청하고 Private Subnet의 CodeBuild가 EKS 상태·HTTPS·API를 확인. 검증 역할에는 필요한 조회만 허용 |
| 권한 거부가 정상 검증 결과인 이유 **[팀]** | Secret 조회·배포 수정처럼 금지한 작업의 Forbidden은 기대 결과. 네트워크 접근·인증·Kubernetes 권한을 각각 검증 |

**암기:** 코드 저장 → 이미지 게시 → 승인된 선언 → 배포 → 실제 응답은 별도 단계입니다.

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
| HPA·CA·Ingress의 역할 차이 | HPA는 목표 Pod 수, CA는 노드 용량, Ingress는 HTTP 라우팅. 서로 대신하지 않음 |
| requests가 확장 해석에 중요한 이유 | 스케줄링 자원 기준이자 CPU HPA 이용률의 분모. 노드 전체 CPU 사용률과 같은 수치가 아님 |
| Pending과 Ready를 구분하는 이유 | Phase와 준비 조건은 별개. CA가 미리 대기 Pod를 만드는 것이 아니라 스케줄링 불가능한 Pod 등을 고려 |
| HPA와 Argo CD의 제어 책임을 나누는 이유 | replicas는 HPA, 나머지 선언은 Argo CD. `/spec/replicas` 제외와 `RespectIgnoreDifferences=true`로 충돌 방지 |
| 상태 검사와 종료 대기가 필요한 이유 **[팀]** | startup은 시작 완료, readiness는 요청 준비, liveness는 재시작 판단. 종료 유예·preStop은 대상 제외와 진행 중 요청 처리를 고려 |

**적용:** 개인 Product Pod `1→5→1`, 노드 `2→3` 확인. 노드 `3→2`는 사용자 완료 보고입니다. **[팀]** PDB는 자발적 축출의 가용성 예산이며 모든 장애나 Deployment 교체를 막는 기능은 아닙니다. [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) · [Probe](https://kubernetes.io/docs/concepts/workloads/pods/probes/)

## 06. DNS·TLS·서비스 상태를 별도로 확인하는 이유

```text
DNS: 도메인 → Route 53 레코드 → 접속 주소
요청: 사용자 → LB → 경로 라우팅 → Service → Pod
TLS: 발급 요청 → 도메인 검증 → 인증서 → TLS 종료 지점에서 사용
```

| 핵심 개념 | 원리·적용 |
|---|---|
| DNS 반영이 앱 배포를 뜻하지 않는 이유 | DNS는 주소 해석. Ingress·Certificate·Secret·Pod는 별도 생성·검증 대상 |
| cert-manager와 ACM의 선택 기준 | 개인은 cert-manager·Let's Encrypt와 NGINX의 TLS 처리, 팀은 ALB Listener에서 ACM 사용. 인증서가 사용되는 지점을 기준으로 설계 |
| Hosted Zone과 도메인 위임의 차이 **[팀]** | 새 계정 Zone 생성만으로 공개 DNS가 바뀌지 않음. 등록기관의 권한 네임서버를 새 Zone의 NS로 연결 |
| Synced·Healthy·실제 응답을 구분하는 이유 | 각각 선언 일치·리소스 상태 판정·관측한 요청 결과. 어느 하나가 전체 기능 성공을 보장하지 않음 |

**암기:** 인증서 pending은 상태이며, 원인은 DNS·검증 경로·Issuer 등을 확인해 좁힙니다. [Alias·CNAME](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)

## 07. 관측·영구 저장·복원을 분리하는 이유

| 핵심 개념 | 원리·적용 |
|---|---|
| Prometheus·Grafana·HPA의 역할 | 지표 수집·저장 / 시각화 / 지표에 따른 확장 목표 조절. Metrics Server는 현재 CPU HPA의 지표 경로 |
| CloudWatch·Alertmanager·CloudTrail의 역할 **[팀]** | AWS 지표·로그·경보 / Prometheus 경보 그룹화·전달·억제 / AWS API 관리 작업 이력 |
| Grafana 메모리와 저장소를 따로 개선한 이유 | OOM은 실행 자원 문제, 설정 소실은 영구 저장 문제. 메모리 조정과 EBS PVC 연결을 각각 적용 |
| PVC·CSI·EBS의 관계 | StorageClass·PVC 요청을 바탕으로 CSI가 볼륨 생성·연결. EBS AZ·노드 자원·배치 조건이 함께 맞아야 함 |
| 데이터 유지와 백업 복원이 다른 이유 | 기존 PVC 유지·Bound는 연결 상태. 데이터 내용을 별도로 대조하며 Retain은 백업이 아님 |
| EKS 재구축과 스냅샷 복원이 다른 이유 **[팀]** | EKS는 코드로 재구축, RDS·모니터링 EBS는 스냅샷에서 데이터 복원. 새 볼륨 ID여도 백업에서 만든 데이터는 존재 |
| 경보 전달과 실제 장애 검증의 차이 | 개인의 수동 ALARM은 SNS 전달 경로 확인. 실제 CPU 임계값 초과 검증과 구분. DB 변경 중 경보도 재연결 성공의 증거는 아님 |

**적용 범위:** 개인은 Grafana EBS 5Gi와 재시작 후 설정 보존을 확인했고 최종 보존은 사용자 보고입니다. Prometheus에는 영구 볼륨이 없습니다. 팀의 S3 이미지는 보존 객체 대조, RDS·모니터링 EBS는 스냅샷 복원입니다.

## 08. 주문 저장과 알림 전달을 분리하는 이유 [팀]

```text
주문 + Outbox 이벤트를 같은 DB 트랜잭션에 저장
 → 별도 발행 로직 → SNS → SQS → Lambda → 중복 확인·SES 발송
```

| 핵심 개념 | 원리·적용 |
|---|---|
| Outbox를 사용하는 이유 | 주문 완료와 발행할 이벤트를 함께 commit/rollback. 외부 SNS 전송까지 같은 DB 트랜잭션이 되는 것은 아님 |
| SQS·DLQ가 필요한 이유 | 비동기 대기·재시도와 반복 실패 메시지 분리. DLQ 보관 자체가 자동 복구를 보장하지 않음 |
| DynamoDB 중복 방지의 한계 | SES 접수 직후 SENT 기록 전에 실패하면 재시도 시 중복 가능. 중복 감소와 exactly-once는 다름 |
| 메일 접수와 도착을 구분하는 이유 | SES API 접수와 받은편지함 도착은 별개. 인증·반송·스팸 등 수신 결과도 확인 |

개인 deployshop의 주문 SNS 발송은 앱 연동 완료 범위가 아닙니다. [SQS·Lambda 처리](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)

## 09. 운영 검증과 재구축에서 기억할 것

- **배포 검증:** Workflow·rollout·Argo CD 상태·웹/API·DB를 각각 확인합니다. PASS는 해당 비교 조건의 통과이며 관측한 요청 표본을 무중단 보장으로 확대하지 않습니다.
- **문제 해결:** 증상 → 근거 → 원인 → 조치 → 재검증으로 설명합니다. HPA의 replicas 충돌과 Certificate 중복 관리는 서로 다른 문제입니다. [문제 분석 및 해결](../TROUBLESHOOTING.md)
- **재구축:** EKS OIDC·kubeconfig·NLB/ALB 대상·RDS Endpoint·Secret·볼륨 연결을 다시 확인합니다. 코드 보존은 데이터 백업을 대신하지 않습니다.
- **종료:** Terraform 밖의 자원, Retain EBS·스냅샷·S3 버전·로그를 별도 확인합니다. 중지·삭제·비용 종료는 같은 의미가 아닙니다.

<details>
<summary>분석 근거와 범위</summary>

정리일 2026-11-02. 실제 질문을 주제별로 재구성했으며 로그인·메뉴 조작·셸 문법 등 단순 사용법은 제외했습니다. 반복이 확인된 우선 복습 주제는 변수 범위, 공인 IP·CIDR, Secret, CD·GitOps, NAT·ALB, State·복원, ESO, 검증 권한, 주문 중복 방지입니다. 질문하지 않은 내용을 반복 질문으로 집계하지 않았습니다.

- ChatGPT ‘파이널 프로젝트’: 앞서 확인한 대화 11개·사용자 메시지 46개. 일부 반환 본문과 첨부 원문은 제한되어 전체 과거 이력을 보장하지 않습니다.
- Codex ‘yjeee-deployshop’: `프로젝트 디렉토리 구조 검토`, `수업 자료 흐름대로 실행 과정 정리`, `프로젝트 내용 파악`, `비교해 프로젝트 구성 제안`의 17페이지·148턴과 현재 대화 맥락.
- Codex ‘aws-eks-final-project’: `개인 프로젝트 발표 자료 준비`, `발표 대본 추가수정`, `발표 대본 수정`, `PPT`, `프로젝트 발표 흐름 정리`, `오늘 실행한 리소스 삭제`, `최종 프로젝트 실행 및 검증`, `최종 프로젝트 흐름 설명 생성`, `도메인 호스팅 영역 삭제 확인`의 45페이지·509턴.
- Codex 대상 대화는 추가 페이지 없음까지 확인했습니다. 턴에는 단순 작업·완료 보고도 포함되며 기술 질문 횟수와 같지 않습니다.

개인 사례는 2026-10-16 [검증 기록](../VALIDATION.md), 팀 사례는 [배포](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/02-deployment.md)·[State](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/07-terraform-state.md)·[운영·복원](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/16-integrated-operations.md) 기록 및 로컬 설정과 대조했습니다. 팀의 초기·최종·별도 계정 실행은 구분했으며 이번 문서 수정 중 AWS를 재실행하지 않았습니다.

</details>
