# AWS MSA 질문 기반 핵심 복습 노트

ChatGPT ‘파이널 프로젝트’ + Codex ‘yjeee-deployshop’·‘aws-eks-final-project’ 질문을 통합한 개인 복습 자료입니다. **원리와 연결 관계를 빠르게 확인하는 용도**이며, 명령 순서는 [상세 복습 노트](STUDY-NOTES.md), 실행 근거는 [검증 결과](../VALIDATION.md)를 참고합니다.

**01~09의 ‘현재 프로젝트’는 개인 deployshop, 10은 팀 aws-eks-final-project 기준입니다.** 팀의 ALB·ESO·주문 알림·복원 실습을 개인 프로젝트의 완료 기능으로 합치지 않습니다.

## 먼저 복습할 것

상: 반복·재질문 확인 / 중: 원리 질문·오류 분석 / 하: 사용법 확인. 보충은 실제 질문을 확인하지 못한 연관 개념으로 취약도를 매기지 않았습니다. 우선순위 1이 가장 높습니다.

| 개념 | 취약도 | 우선순위 | 질문 근거 |
|---|---|---:|---|
| Root·Child 변수 범위 | 상 | 1 | 버킷 변수 오류 의문 → 두 변수 존재 여부 재확인 |
| PC 공인 IP·RDS 주소·CIDR | 상 | 1 | 공인 IP 의미, Workbench 입력 주소, 다른 PC 이동 시 변경 여부 재질문 |
| DB 비밀번호·Kubernetes Secret | 상 | 1 | 두 Secret 차이 → Terraform 비밀번호와 관계 → 다시 확인 |
| DNS 생성 단계·관리 도구 | 상 | 1 | Terraform에 레코드가 있는지 여러 세션에서 확인 |
| 직접 배포·CD·GitOps | 상 | 1 | Healthy면 CD 완료인지 → 직접 배포면 CD가 아닌지 재확인 |
| HPA·Deployment·ReplicaSet·CA | 중 | 1 | 실제 Pod 생성 주체, CA와 Ingress 역할 차이 질문 |
| Local State·sensitive·Data Source | 중 | 1 | 정의·값 확인·모듈 간 중복 조회 질문 |
| IAM 정책·OIDC | 중 | 2 | 사용자 정책 선택·추가 정책 필요 여부·OIDC 적용 위치 질문 |
| Grafana 초기화·PVC·EBS | 중 | 1 | 설정 소실·OOM·PVC 미생성 오류 기록 |
| Git·YAML·대시보드 조작 | 하~중 | 3 | git 저장소 오류, ignore 위치, YAML 계층, 데이터 소스·legend 질문 |
| NAT·ALB·AZ·도메인 위임 | 상 | 1 | NAT가 ALB를 대체하는지, 양방향 통신인지, 새 계정 NS 연결을 재질문 |
| 스냅샷·EKS 재구축·EBS 복원 | 상 | 1 | EKS도 스냅샷인지, 새 볼륨 ID에 데이터가 어떻게 남는지 반복 확인 |
| ESO·DB 비밀번호 변경 | 상 | 1 | 정의 → 기존 수동 방식과 차이 → 실제 변경·재연결을 재질문 |
| CodeBuild·검증 권한·Forbidden | 상 | 1 | 내부 검증 사용 이유와 조회/수정 거부 의미 재확인 |
| Outbox·SQS·DynamoDB | 상 | 1 | 역할 구분과 DB 트랜잭션, 중복 방지의 보장 범위를 재확인 |
| Bootstrap·원격 State·PR 승인 | 상 | 2 | 단계별 State 의미, 동시 작업·버전 관리, 동료 승인 흐름을 재질문 |

위 추가 항목은 팀 프로젝트 대화에서 확인했습니다. 개념을 이해하려는 연속 질문을 묶은 분류이며 실제 질문 횟수를 임의로 계산하지 않았습니다.

## 01. AWS·네트워크 — 주소의 주체부터 구분

| 질문·혼동 | 핵심 정답 | 내 프로젝트 적용 |
|---|---|---|
| IAM 사용자가 있는데 Profile에는 왜 없지? | IAM 사용자는 AWS 신원, Profile은 **내 PC의 인증 설정 이름**. 자동 연동되지 않음 | 로컬 Profile과 실제 호출 계정을 함께 확인 |
| 정책은 무엇을 붙여야 하지? ReadOnly·ChangePassword도 추가? | 정책 이름보다 대상과 허용 작업을 확인. 관리자 정책과 겹치는 Allow를 더해도 범위가 줄지 않으며, 명시적 Deny·조직 제한 등은 별도 적용 | 실습 구축 사용자의 넓은 권한을 노드·Pod·CI에 그대로 공유하지 않음 |
| Access Key는 어디서 받지? | 콘솔 비밀번호와 API 키는 별개. Secret Access Key는 생성 시 확인·보관하며 기존 값을 다시 조회할 수 없음 | 로컬·Actions·상품 S3 키의 용도를 구분 |
| Workbench에 PC IP를 넣어? RDS 주소를 넣어? | **접속 목적지 = RDS Endpoint / SG 허용 출발지 = PC 공인 IP/32** | Endpoint는 Workbench Hostname, PC 공인 IP는 `workbench_allowed_cidr` |
| 공인 IP가 Gateway·WSL 주소야? 집으로 옮기면? | AWS가 보는 인터넷 출발지 주소. 로컬 사설 IP·기본 Gateway와 다름. 장소 변경 시 재확인 | 새 공인 IP가 달라지면 CIDR 변경·apply |
| `0.0.0.0/0`도 되지? | 모든 IPv4 출발지를 허용. `/32`는 한 주소. DB 인증은 여전히 별도 | 실습 중 전체 허용, 최종 PC `/32`. RDS 공개 접근 자체는 유지 |

**보충:** VPC는 네트워크 범위, Subnet은 AZ별 주소 영역. 노드는 Private App Subnet에 있고 외부 통신은 NAT를 사용합니다. Private DB Subnet이 정의돼 있어도 실제 RDS는 Public Subnet입니다.

## 02. Terraform — 값·조회·생성·상태

| 질문·혼동 | 핵심 정답 |
|---|---|
| `bucket_name`과 `s3_bucket_name`이 둘 다 있어? | `bucket_name = var.s3_bucket_name`: **왼쪽은 Child 입력, 오른쪽은 Root 값**. 변수 두 개가 버킷 두 개를 뜻하지 않음 |
| 계정 조회를 다른 모듈에서 또 해도 돼? | 모듈마다 범위가 독립적. Root 값을 Child가 자동 참조할 수 없음. 입력으로 전달하거나 별도 조회 |
| Provider·Resource·Data Source 차이? | Provider = API 연동 / Resource = 자원 관리 / Data Source = 조회 / Output = 결과 전달 |
| 생성 순서를 명시하고 싶어 | 참조로 생기는 의존성이 기본. 참조에 드러나지 않는 선행 조건에 `depends_on` 사용. 파일 작성 순서대로 실행되지 않음 |
| Local State가 뭐야? | 코드 주소와 실제 자원의 관계 등을 로컬 파일에 기록. **State 삭제 ≠ AWS 삭제** |
| tfvars가 왜 없어? | 환경별 입력값 파일이며 Git 제외 대상일 수 있음. `variables.tf`의 선언과 실제 값은 별개 |
| sensitive 값을 볼 수 있어? | 일반 출력만 가림. 필요한 Output은 `terraform output -raw <이름>`으로 표시 가능하며 State 암호화 기능이 아님 |
| 폴더 옮기면 코드에 영향 있어? | module `source`, Docker Context, Workflow 경로 필터, Argo CD `path`, 문서 링크를 함께 수정 |

**암기:** `init` 준비 → `validate` 구성 검사 → `plan` 변경 계획 → `apply` 실행. 정적 검사 성공은 실제 권한·연결·기능 성공을 보장하지 않습니다. 현재는 **Root 실행 + Local State**입니다. [의존성 설명](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)

## 03. Secret — 같은 값을 다른 시스템에 전달하는 과정

실제 질문: “my-app-secrets와 aws-secret 차이?”, “Terraform db_password와 무슨 차이?”, “같은 값을 Secret으로 만드는 과정인가?”

| 항목 | 사용하는 곳 | 역할 |
|---|---|---|
| Terraform `db_password` | RDS 생성·변경 | DB 인증 비밀번호 설정 |
| `my-app-secrets` | 앱 Pod | `DB_HOST`, `DB_PW` 전달 |
| `aws-secret` | Product Pod | S3 API용 Access Key 전달 |
| GitHub Secrets | Actions Runner | Workflow AWS 인증값 전달 |

```text
RDS에 설정한 비밀번호 ── 같은 값이어야 함 ── DB_PW → 앱의 DB 로그인
S3 접근용 AWS 키 ── aws-secret → Product의 S3 API 호출
```

**암기:** Secret은 비밀번호를 새로 만드는 동작이 아니라 **앱에 필요한 값을 전달하는 리소스**입니다. Terraform 값을 바꿔도 수동 생성한 Secret이 자동 갱신되지는 않습니다. 환경 변수로 주입한 변경값은 새 Pod에서 확인합니다.

## 04. Docker·Git·CI/CD — 저장과 배포는 다름

| 질문·혼동 | 핵심 정답·프로젝트 적용 |
|---|---|
| 직접 배포면 CD가 안 되는 거야? | **CD는 됨.** Actions가 build → ECR push → `kubectl apply` → `rollout restart`. Argo CD도 선언 동기화를 수행 |
| GitOps로 발전시키려면? | 버전별 이미지 → Git YAML 이미지 갱신 → Argo CD 배포. Actions 직접 배포 제거는 향후 전환 방향 |
| OIDC Module은 AWS·GitHub 어디에 적용? | AWS: Provider·Role·신뢰/권한 정책. GitHub: 토큰 요청·Role 사용 Workflow. EKS 배포 권한도 별도 필요 |
| git 설치 안 된 것 같은데? `not a git repository` | Git 설치와 현재 폴더의 `.git` 유무는 별개. 작업 폴더와 저장소 초기화·clone 상태 확인 |
| `.gitignore`를 루트에 합쳐도 돼? | 가능하지만 패턴 기준 경로를 확인. 이미 추적한 파일은 자동 제외되지 않음 |

**보충:** Image는 배포 내용, Container는 실행 인스턴스, ECR은 이미지 저장소입니다. 현재 backend는 JDK 빌드 → JRE 실행의 Multi-stage이며, `latest` push만으로 기존 Pod가 자동 교체되지는 않습니다.

**현재/계획 구분:** 현재 Actions는 **Access Key**, 이미지는 **latest**입니다. GitHub OIDC·SHA 태그·Argo CD 단독 이미지 배포를 완료 기능으로 쓰지 않습니다. OIDC는 신뢰 정책의 “누가”와 권한 정책의 “무엇을”을 구분합니다. [GitHub OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)

## 05. Kubernetes·자동 확장 — 누가 Pod를 만드는가

실제 질문: “replicas를 바꾸는 건 누구?”, “HPA가 실제 Pod를 늘리는 건 아니지?”, “Ingress가 있는데 CA도 필요해?”, “ASG가 생성되는 게 맞아?”

```text
Metrics Server → HPA → Deployment의 목표 replicas 변경
                         ↓ Deployment Controller
                      ReplicaSet의 목표 수 조정
                         ↓ ReplicaSet Controller
                      Pod 생성·삭제
                         ↓ Scheduler가 노드 선택 / kubelet이 실행 관리

배치할 공간 부족 → CA가 ASG 용량 조절 → 새 EC2 노드 → Pod 배치
```

| 요소 | 맡은 역할 |
|---|---|
| HPA | 메트릭에 맞춰 목표 Pod 수 조절. HPA 자체도 Controller |
| Deployment·ReplicaSet | 배포·복제 상태를 조정하고 Pod 수 유지 |
| Service | selector로 대상 Pod를 연결. `port`와 `targetPort` 구분 |
| Ingress NGINX | HTTP 요청 라우팅. 노드 증설을 대신하지 않음 |
| Cluster Autoscaler | 스케줄링할 수 없는 Pod 등을 고려해 노드 용량 조절 |
| EKS Managed Node Group | AWS가 ASG를 연결해 노드 관리. 별도 ASG Resource가 없어도 ASG가 존재할 수 있음 |

**프로젝트:** Product CPU request `0.5`, HPA 목표 30%, Pod `1→5→1`. CPU 이용률은 request 기준이며 노드 전체 CPU 비율과 다릅니다. 노드 `2→3` 확인, `3→2`는 사용자 완료 보고입니다. [Deployment 원리](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

**작업 팁:** 파일 수정 후 apply/Sync가 필요합니다. YAML은 들여쓰기가 구조이므로 “최상위”는 `metadata` 안을 뜻하지 않습니다. `Running`뿐 아니라 Ready·Events·Service 대상을 확인합니다.

## 06. DNS·NLB·Ingress·TLS — 연결 단계 구분

```text
DNS 조회: 도메인 → Route 53 레코드 → 접속 주소
실제 요청: 사용자 → NLB → Ingress NGINX
                              ├─ / → Frontend Service → Pod
                              └─ API → Gateway → Backend Service → Pod
```

| 질문·혼동 | 핵심 정답 |
|---|---|
| Route 53 레코드는 어느 단계? Terraform에 있나? | 현재는 NLB 확인 후 별도 연결. DNS는 주소 해석이며 앱·인증서를 자동 생성하지 않음 |
| DNS INSYNC인데 Ingress·Certificate가 없어 | Route 53 반영과 Kubernetes 생성은 별개. Context·Namespace·apply/Sync 확인 |
| 인증서 pending·`no such host` | DNS 해석부터 확인. HTTP-01 검증 경로가 도달 가능해야 발급 진행 |
| Alias 레코드와 NS·SOA는 뭐가 달라? | Alias는 서비스 대상 연결, NS는 권한 DNS 서버, SOA는 영역 관리 정보. 서비스 레코드 삭제와 Hosted Zone·도메인 등록 삭제는 별개 |

**TLS 암기:** cert-manager는 발급·갱신 자동화, Let’s Encrypt는 CA. `Certificate → Request → Order/Challenge → TLS Secret → Ingress`로 연결됩니다. 현재는 Ingress에서 TLS 처리하며 ACM 사용으로 바꿔 설명하지 않습니다.

**기록 보정:** 초기 ChatGPT 설명에는 CNAME, 이후 Codex의 실제 조회에는 **NLB를 가리키는 A Alias 4개**가 확인됩니다. 시점별 기록을 구분하며 지금도 레코드가 살아 있다고 단정하지 않습니다. [Alias와 CNAME](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html)

## 07. Argo CD — 일치·상태·제어 책임

| 개념·질문 | 핵심 정답 |
|---|---|
| Synced / Healthy | Git과 실제 선언 일치 / 리소스 health 판정. 서로 독립 |
| selfHeal / prune | 실제 이탈을 Git 상태로 복구 / Git에서 제거한 관리 자원 삭제 |
| HPA 충돌이 Certificate 충돌이야? | **별개.** HPA는 replicas 제어, Certificate는 인증서 생성·선언 경로 충돌 |
| HPA와 함께 쓰려면? | replicas는 HPA, 나머지 선언은 Argo CD. `/spec/replicas` 제외와 `RespectIgnoreDifferences=true` 적용 |
| Git에 PVC를 올렸는데 왜 없어? | Argo CD가 읽은 리비전·경로·Sync부터 확인. 파일 push가 곧 적용 완료는 아님 |

**암기:** Workflow 성공·Synced·Healthy만으로 주문 성공을 증명할 수 없습니다. rollout·웹/API·DB를 별도로 확인합니다.

## 08. 모니터링·저장소·트러블슈팅

| 질문·증상 | 원리 → 조치·검증 |
|---|---|
| Prometheus는 어디서 선택? legend는? | Grafana Data Source는 조회 대상, legend는 시계열 표시 이름. 실제 시계열 label과 패널 쿼리를 확인 |
| Grafana 계정·대시보드 초기화 | `OOMKilled`로 종료, 영구 저장도 없었음 → 메모리 조정 + `/var/lib/grafana`에 PVC → 재시작 후 설정 확인 |
| EBS는 어떻게 생성돼? | StorageClass + PVC 요청 → EBS CSI가 권한으로 볼륨 생성·연결 → Pod 마운트. CSI용 IAM 연결도 필요 |
| PVC 없음 / Pending | 없음: 적용·리비전 확인. Pending: Events·소비 Pod·CSI·권한·AZ 확인. `WaitForFirstConsumer`의 배치 대기는 정상일 수 있음 |
| monitoring 반복 OutOfSync | 명시적 Certificate와 Ingress 자동 생성 경로 중복 → issuer annotation 제거, Certificate·TLS 참조 유지 |
| CA `Failed to acquire lease` | 다른 인스턴스가 Leader일 수 있음. 이 문구만으로 장애 단정 금지. 현재 Leader·Pod·로그·실제 확장을 확인 |
| S3 생성 409 / HeadBucket 404 | 이름 충돌과 조회 결과를 구분. HeadBucket 오류만으로 이름 사용 가능을 보장하지 않음 |
| Route 53 JSON 디코딩 오류 | 로컬 인코딩·JSON 문제와 AWS API 문제 분리. Hosted Zone ID에 도메인 문자열을 넣지 않음 |
| HTTP 308 / 재고 부족 400 | HTTPS 전환·업무 거절일 수 있음. Location·최종 응답·재고/주문 유지로 판정 |
| SQL에 `/product-detail.html?id=2` 입력? | URL 전체가 아닌 상품 ID 값 `2`로 조회. 웹·API·DB에서 같은 상품인지 대조 |

**보충·암기:** Prometheus = 수집·저장 / Grafana = 시각화 / Node Exporter·Actuator = 지표 노출 / Metrics Server = 현재 CPU HPA의 지표 경로. `up=1`은 수집 성공이지 구매 성공이 아닙니다.

**현재 저장:** Grafana EBS gp3 5Gi·RWO·Recreate. 같은 AZ 재연결을 고려하며 Retain은 백업이 아닙니다. Prometheus에는 영구 데이터 볼륨이 없습니다. Grafana 재시작 후 보존은 사용자 완료 보고입니다.

**CloudWatch/SNS:** EKS 제어 영역 로그와 노드 CPU 경보를 연결했습니다. 평균 CPU 80% 이상, 5분 구간 2회 조건이며, 수동 상태 변경으로 알림 경로를 확인했습니다. 실제 10분 부하 검증·앱 로그 전체 수집·주문 SNS 발송은 완료 범위 밖입니다.

**교육용 오류 기록:** Windows ECR 로그인 400은 PowerShell 경로에서 실패하고 cmd 경로에서 성공했습니다. 정확한 원인은 확정하지 않았습니다. kubectl selector/JSONPath 오류는 셸 인자·이스케이프도 점검합니다. Workbench 1046은 기본 DB 미선택으로 `USE ordermsa;` 후 해결했습니다.

## 09. 삭제·재구축 — 소스가 남아도 연결은 바뀜

실제 질문: “중지만 할 수 있나?”, “콘솔로 만든 것도 과금되나?”, “다시 apply하면 주소가 바뀌어 오류가 나나?”

| 다시 생성할 대상 | 다시 확인할 연결 |
|---|---|
| EKS | kubeconfig·Access Entry·클러스터 OIDC와 IRSA Trust Policy |
| NLB | Route 53 Alias/CNAME 대상 |
| RDS | Endpoint·DB Secret·데이터 복원 여부 |
| Grafana·EBS | 볼륨 존재·AZ·PVC 연결·저장 데이터 |
| SNS | 이메일 구독 확인 상태 |

**암기:** 노드가 없어도 EKS 등 다른 자원은 남을 수 있습니다. Terraform 밖에서 만든 자원, Retain EBS·스냅샷·S3 버전·로그·Hosted Zone은 별도 조회합니다. 중지 가능 여부와 남는 비용은 자원별로 다르므로 삭제 전 확인합니다. 소스 보존은 데이터 백업과 다릅니다.

## 10. 팀 프로젝트 질문 추가 — 개인 구성과 구분해서 암기

### 두 프로젝트 차이

| 영역 | 개인 deployshop | 팀 aws-eks-final-project |
|---|---|---|
| 외부 진입·TLS | NLB + Ingress NGINX + cert-manager | 공유 ALB + ACM, LB Controller |
| RDS | Public 접근·최종 PC /32 | Private 접근·Single-AZ |
| 배포 | Access Key·latest·Actions 직접 배포 병행 | OIDC·커밋 태그·PR 승인·Argo CD 반영 |
| State | Local State | Bootstrap + S3 원격 State·잠금, infra/k8s 분리 |
| 비밀값 | 수동 Kubernetes Secret 전달 | Secrets Manager → ESO → Kubernetes Secret |
| 운영·알림 | Prometheus·Grafana·CloudWatch·SNS | Alertmanager·CloudTrail·CodeBuild·주문 알림 추가 |
| 데이터 복구 | Grafana Pod 교체 후 보존 확인 | RDS·모니터링 EBS 스냅샷 복원 기록 |

팀의 초기 실습 구성과 최종 구성, 별도 계정 재구축은 서로 다른 시점입니다. 과거 환경의 성공을 새 계정 전체의 성공으로 바꿔 쓰지 않습니다.

### 네트워크·TLS — NAT가 ALB를 대신할 수 있나?

| 실제 질문 요지 | 핵심 정답 |
|---|---|
| AZ가 리전 아니야? 서비스마다 EC2 한 대야? | Region 안에 여러 AZ, Subnet은 한 AZ에 속함. 여러 서비스 Pod가 한 노드에 배치될 수 있음 |
| ALB가 있는데 NAT는 언제 써? NAT로 ALB를 대신해? | ALB는 외부 웹 요청을 앱에 전달, NAT Gateway는 Private 자원이 시작한 외부 연결과 응답 처리. 역할이 다름 |
| NAT는 원래 양방향 아닌가? 포트포워딩과 차이? | 일반 NAT에는 여러 방식이 있지만 AWS NAT Gateway는 외부의 임의 신규 연결을 내부로 받는 포트포워딩 기능이 아님 |
| Public A의 ALB가 Private A의 DB에 연결해? | AZ를 일대일 통로로 보지 않음. ALB는 Target Group의 앱으로 연결하고 앱이 DB에 접속. DB가 웹용 ALB의 직접 대상은 아님 |
| DB Subnet이 두 AZ인데 RDS는 Single-AZ? | 배치 후보가 두 AZ인 것과 실제 대기 DB가 있는 것은 다름. Single-AZ는 Multi-AZ 장애 전환 구성이 아님 |
| NAT 1개·DB Single-AZ면 어떤 한계? | 해당 NAT/AZ 장애 시 의존하는 외부 통신, DB 장애 시 DB 의존 기능이 영향받을 수 있음. 장애가 반드시 발생했다는 뜻은 아님 |
| NLB와 ALB 차이? 왜 ALB·ACM으로 변경? | NLB는 L4 연결, ALB는 HTTP Host/Path 기반 L7 처리. 팀에서는 웹 진입·라우팅·TLS를 AWS 관리 경로로 정리 |
| NGINX+ACM, ALB+cert-manager는 안 돼? | 인증서가 **어디서 종료·사용되는지**가 기준. 팀은 ALB Listener에서 ACM 사용. NGINX 뒤에서 TLS를 추가할지는 별도 설계이며 무조건 금지 조합은 아님 |
| 새 계정에 Zone을 만들면 도메인도 옮겨져? | 도메인 등록과 Hosted Zone은 별개. 등록기관의 권한 네임서버를 새 Zone의 NS로 위임해야 공개 DNS가 새 Zone을 사용 |

**암기:** 들어오는 웹 연결은 ALB, Private 앱이 시작하는 외부 연결은 NAT. [AWS NAT Gateway 원리](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)

### State·배포·권한 — 저장, 승인, 배포, 검증을 구분

| 실제 질문 요지 | 핵심 정답 |
|---|---|
| Bootstrap이 뭐야? 상태파일을 분리했다는 건? | State 저장용 S3를 먼저 준비하는 단계. AWS infra와 클러스터 내부 구성은 서로 다른 Root·State로 관리. 팀의 Bootstrap 자체는 Local State |
| S3 버전 관리와 잠금은 같은 기능? | 버전 관리는 과거 State 보관, 잠금은 동시 Terraform 변경 충돌 방지. 팀은 S3 `.tflock` 사용. 메일 중복 방지용 DynamoDB와 혼동 금지 |
| Kustomize·image YAML로 EKS도 만들어? | EKS 자체는 Terraform, 앱 Deployment·이미지 선언은 Kustomize/Argo CD. Helm은 운영 도구 설치 패키지에 사용 |
| PR 승인 후 다른 팀원은 어떻게 해? | 작업 브랜치 → PR → 검사·리뷰 → 병합 → 다른 팀원은 최신 main 반영 후 작업. 승인과 병합은 별개이며 보호 규칙이 승인 조건을 강제 |
| ECR 저장과 서비스 반영이 왜 별도야? | 이미지는 실행 후보. 승인된 Git의 이미지 선언이 바뀌고 Argo CD가 반영해야 새 Pod 실행 |
| OIDC는 어떤 리포든 쓸 수 있어? | Provider 등록만으로 허용되지 않음. Role Trust Policy의 `aud`·`sub` 등 조건이 해당 repo·브랜치와 맞아야 함 |
| 새 계정에서 AssumeRoleWithWebIdentity 오류 | 실제 Workflow repo/main과 역할 신뢰 조건을 대조. AWS STS 인증 실패와 EKS RBAC 거부는 다른 단계 |
| CodeBuild를 왜 Actions와 연결해? | Actions가 작업을 요청하고 Private Subnet의 CodeBuild가 내부 EKS 배포 상태를 조회·검증. CodeBuild는 AWS 관리형 서비스이며 앱 배포 주체와 구분 |
| Secret 조회·patch가 Forbidden인데 성공이야? | 검증 역할은 Deployment 등 필요한 조회만 허용. **금지한 작업이 거부되는 것이 권한 테스트의 기대 결과**. 해당 변경 검사는 server dry-run이며 실제 수정이 아님 |

**암기:** 네트워크 도달 가능성과 인증·권한은 각각 필요합니다. CodeBuild 검증 성공이 배포 권한·Secret 조회 권한까지 있다는 뜻은 아닙니다.

### ESO·Pod 교체·데이터 복원 — 무엇이 바뀌고 무엇이 남나?

| 실제 질문 요지 | 핵심 정답 |
|---|---|
| ESO가 기존 수동 입력을 자동화해? | External Secrets Operator가 Secrets Manager 값을 Kubernetes Secret으로 동기화. 앱 환경 변수 반영에는 Pod 교체 등 별도 동작 필요 |
| 비밀번호 로테이션이 뭐고 실제로 뭘 바꿔? | DB 비밀번호 변경·보관·전달·재연결 과정. ESO 자체가 DB 비밀번호를 바꾸는 것은 아님. 팀 기록에서는 변경 후 동기화·새 Pod의 DB 재연결 확인 |
| 경보 발생이 재연결 성공의 증거야? | 경보는 영향 감지. 복구는 새 값 동기화·DB-ready·로그인/API 결과로 따로 증명. 무영향 변경이라고 설명하지 않음 |
| PodPhase Pending과 Ready=False는 같아? CA가 미리 대기 Pod를 만들어? | Phase와 Ready 조건은 별개. CA는 대기 Pod를 만드는 도구가 아니라 스케줄링 불가능한 Pod 등을 보고 노드를 확장 |
| 이름이 바뀌고 replicas Ready=2면 교체·데이터 유지 성공? | 새 Pod UID/이름은 교체, Ready는 준비 상태. 데이터 유지는 같은 주문·재고·대시보드를 따로 대조 |
| startup/readiness/liveness 차이? | 시작 완료까지 대기 / 요청 수신 준비 / 비정상 컨테이너 재시작 판단. 설정 존재와 각 검사 효과의 검증은 별개 |
| 교체 대기 10초·preStop 15초·유예 40초는? | 각각 `minReadySeconds`·종료 전 Hook·전체 종료 유예. 같은 대기 시간을 세 번 더하는 의미가 아님. ALB 대상 제외·진행 중 요청 처리 시간을 고려 |
| EKS도 스냅샷이 있어? 새 EBS ID인데 데이터는? | 이 실습은 **EKS는 코드로 재구축, RDS·EBS 데이터는 스냅샷으로 복원**. 새 EBS를 스냅샷에서 만들면 새 ID에도 백업 데이터가 있음 |
| 스냅샷은 어디 저장돼? PVC/PV unchanged·Bound는? | EBS 스냅샷은 AWS 관리 S3 기반 저장이며 내 일반 버킷 객체가 아님. RDS 백업도 별도 관리. unchanged는 기존 연결 객체 유지, Bound는 PVC-PV 연결이며 데이터 내용 검증은 별도 |
| EBS는 PVC 규격대로 만들어? 왜 다른 AZ 노드로 안 돼? | 동적 생성 시 StorageClass·PVC를 바탕으로 CSI가 생성. 볼륨 AZ·노드 자원·배치 조건이 함께 맞아야 함. 스냅샷 복원은 별도 복원 경로 사용 |

**보충:** PDB는 자발적 축출의 가용성 예산이며 모든 장애나 Deployment 교체를 막는 장치가 아닙니다. 팀의 S3 이미지는 보존한 객체 대조이고, RDS·모니터링 EBS는 스냅샷 복원입니다. [ESO 역할](https://external-secrets.io/latest/introduction/overview/) · [Probe 구분](https://kubernetes.io/docs/concepts/workloads/pods/probes/)

### 관측·주문 알림·오류 해석 — 보장 범위를 과장하지 않기

| 실제 질문 요지 | 핵심 정답 |
|---|---|
| 내부 지표는 HPA가 담당하는 거 아냐? | HPA는 지표를 사용해 확장 목표를 조절. Prometheus는 수집·저장·규칙 평가, Grafana는 시각화 |
| CloudWatch 있는데 Alertmanager는 왜? 둘 다 써? | 팀은 둘 다 사용. CloudWatch는 AWS 지표·로그·경보, Alertmanager는 Prometheus 경보의 그룹화·전달·억제. AWS 서비스 자체가 아니라 Prometheus 생태계 구성요소 |
| CloudTrail은 CloudWatch와 뭐가 달라? | CloudTrail은 AWS API 관리 작업 이력, CloudWatch는 지표·로그·경보. 앱 로그와 관리 감사 기록도 구분 |
| DB 트랜잭션으로 주문·이벤트를 저장한다는 뜻? | 같은 DB 트랜잭션에서 주문 완료와 Outbox 이벤트를 함께 commit/rollback. SNS 발행까지 같은 DB 트랜잭션이 되는 것은 아님 |
| Outbox·SQS·DynamoDB가 각각 왜 필요해? | Outbox: 발행할 이벤트 보존 / SNS: 전달·분배 / SQS: 대기·재시도 / Lambda: 처리 / DynamoDB: 중복 처리 기록 / SES: 메일 발송 |
| DynamoDB가 있으면 메일이 정확히 한 번 아냐? | SES 접수 후 SENT 기록 전에 실패하면 재시도 시 중복 가능. 중복 감소와 exactly-once 보장은 다름 |
| DLQ 메시지 1개와 경보는 뭘 뜻해? | 반복 처리 실패가 DLQ에 쌓였고 설정한 지표 조건으로 경보 발생. 정리·재평가 후 정상 복귀. DLQ가 자동 복구를 보장하지 않음 |
| SES 접수면 도착한 거 아냐? | API 접수와 받은편지함 도착은 별개. 발신 인증·수신 환경·스팸·반송 등 추가 상태를 고려 |
| HTTP 200·PASS·292건·112개 테스트의 근거? | 200은 해당 HTTP 요청 성공. PASS는 스크립트의 비교 조건 통과. 292는 특정 로그의 관측 요청 수, 112는 당시 자동화 회귀 테스트 수이며 둘 다 전체 운영 무결점의 증거는 아님 |
| 삭제 중 이메일 오류면 앱도 오류여야 해? | 삭제 시 Terraform 입력 검증·설정 전달 경로가 앱 실행 경로와 다를 수 있음. 당시 오류와 수정 파일·입력 전달을 대조 |

**주문 흐름:** 주문+Outbox 저장 → 별도 발행 로직이 SNS 전송 → SQS → Lambda → 중복 확인·SES 발송. DB 이벤트 기록·큐 전달·발송 부작용을 서로 다른 단계로 봅니다. [SQS·Lambda 중복 처리 주의](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)

**검증 암기:** 백엔드 교체 시 상품 API 15회와 별도 계정 Frontend 롤백의 292회를 섞지 않습니다. 요청 표본·기간·서비스·배포 버전이 달라지면 별개 결과입니다. 회귀 테스트도 실제 AWS 삭제·복원 성공을 대신하지 않습니다.

## 11. 면접 전 TOP 10 — 한 문장으로 답하기

| 확인 질문 | 답변 핵심 |
|---|---|
| 1. Root 값은 Child로 어떻게 가나? | 호출부 입력 매핑으로 전달, 모듈 범위는 독립 |
| 2. Workbench 주소와 CIDR은? | 접속 대상 RDS / 허용 출발지 PC 공인 IP |
| 3. DB 비밀번호와 Secret 차이? | RDS 인증값 설정 / 앱에 같은 인증값 전달 |
| 4. 누가 Pod를 생성하나? | HPA 목표 변경 → Deployment·ReplicaSet 조정 → Pod 생성·배치·실행 |
| 5. Ingress와 CA 차이? | HTTP 라우팅 / 노드 용량 조절 |
| 6. 직접 배포도 CD인가? | 맞음. 현재 Actions 직접 배포 + Argo CD 선언 동기화 |
| 7. DNS가 정상인데 TLS는 왜 실패하나? | 리소스 존재·HTTP 검증·인증서·Ingress는 별도 단계 |
| 8. Grafana 장애는 어떻게 해결했나? | 메모리 부족과 저장소 소실을 분리해 조치·검증 |
| 9. HPA·Argo CD 충돌은? | replicas 관리 책임을 HPA로 분리 |
| 10. 재구축 시 무엇이 바뀌나? | OIDC·Endpoint·LB 대상·Secret 등 연결을 재확인 |

**추가 자가 점검:** “State 삭제는 자원 삭제인가?”, “ECR push가 Pod 교체인가?”, “수동 ALARM이 부하 검증인가?” → **모두 아니오.** 관리 정보·이미지 저장·알림 전달 검증의 범위를 구분합니다.

**팀 추가 점검:** “NAT가 ALB를 대신하나?”, “EKS도 DB처럼 스냅샷 복원하나?”, “ESO가 DB 비밀번호를 직접 변경하나?”, “DynamoDB가 메일 exactly-once를 보장하나?” → **모두 아니오.** 진입/외부 통신, 코드 재구축/데이터 복원, 값 동기화/비밀번호 변경, 중복 감소/전달 보장을 구분합니다.

<details>
<summary>질문 출처와 분석 한계</summary>

정리일: 2026-11-02. 개인 사례는 2026-10-16 검증 기록, 팀 사례는 해당 문서에 기록된 환경·실행 시점 기준입니다. 이번 문서 작성 중 AWS를 재실행하지 않았습니다.

### ChatGPT — 앞선 분석에서 읽은 질문

‘파이널 프로젝트’ 대화 11개에서 도구가 반환한 사용자 메시지 46개를 바탕으로 한 앞선 분석을 통합했습니다. 일부 대화는 반환 본문이 제한되어 전체 과거 기록을 보장하지 않습니다.

- `Terraform 구성`: Profile·모듈 구조·자동완성
- `01 Terraform 인프라 구축`: Local State·버킷 변수
- `01_1 terraform 코드 질문`: 변수 범위·Data Source·OIDC·gitignore·S3 조회
- `01_2 Terraform 실행 및 오류 / 검증`: DNS 단계·sensitive·S3 충돌·검증
- `02 Kubernetes·모니터링 구성`: 구축 범위·모니터링 도메인
- `02_1 Kubernetes 질문 답변`: apply·Grafana·DNS와 리소스·주문/리다이렉트
- `03 gitHub 배포 자동화 구축(CI/CD)`: CD 검증·TLS·DNS JSON 오류
- `04. AWS MSA 최종 모니터링 및 검증`: CloudWatch·SNS 포함 요청
- `체크리스트` / `Codex 프로젝트 파악` / `학습 노트 프롬프트`: 구성·문서 요청. 기술 원리가 없는 요청은 취약도에서 제외

### Codex — yjeee-deployshop

프로젝트 ID 또는 작업 경로가 yjeee-deployshop인 대화를 선택했습니다. 보관 목록도 조회했고 반환 항목은 없었습니다. 아래 4개는 이전 페이지까지 읽어 추가 페이지 없음 상태를 확인했습니다. 현재 `README와 아키텍처 구성도 개선` 대화도 통합 맥락에 포함했습니다.

| 세션명 | 읽은 페이지 / 턴 | 추가 질문 주제 |
|---|---|---|
| 프로젝트 디렉토리 구조 검토 | 4 / 39 | 경로 의존성, Terraform 순서, Controller 관계, 공인 IP·RDS, IAM 정책·키 |
| 수업 자료 흐름대로 실행 과정 정리 | 11 / 104 | Secret 관계, ASG, Git·YAML, Grafana·EBS·PVC, 대시보드, SQL, 삭제·재구축 |
| 프로젝트 내용 파악 | 1 / 4 | 직접 배포와 CD, GitOps 전환, HPA와 인증서 충돌 구분 |
| 비교해 프로젝트 구성 제안 | 1 / 1 | 프로젝트 비교 요청. 타 저장소 기능은 현재 구현에 합치지 않음 |

### Codex — aws-eks-final-project 추가 분석

프로젝트 ID 또는 작업 경로가 `aws-eks-final-project`인 대화 9개를 선택해, 45페이지·509턴을 읽고 추가 페이지 없음 상태까지 확인했습니다. 보관 목록의 반환 항목은 없었습니다. 이름 오타 `asw-eks-final-project`는 실제 프로젝트·작업 경로와 대조해 해석했습니다.

| 세션명 | 페이지 / 턴 | 질문 주제 |
|---|---|---|
| 개인 프로젝트 발표 자료 준비 | 1 / 3 | 제출·디자인 요청, 기술 취약도 판정에서 제외 |
| 발표 대본 추가수정 | 10 / 98 | NAT·ALB, OIDC·ESO, State, Outbox·중복, 복원·검증 근거 |
| 발표 대본 수정 | 14 / 139 | AZ·네트워크, PR, CodeBuild·권한, 알림 도구, 스냅샷 |
| PPT | 7 / 66 | Pod 교체 설정과 실제 검증 범위, 기타 디자인 요청은 제외 |
| 프로젝트 발표 흐름 정리 | 1 / 7 | 인프라·실습 흐름 이해 요청 |
| 오늘 실행한 리소스 삭제 | 1 / 3 | 삭제·잔여 조회 요청, 개념 반복 질문으로 계산하지 않음 |
| 최종 프로젝트 실행 및 검증 | 9 / 82 | 새 계정 인증·구축·DNS·운영 검증 맥락 |
| 최종 프로젝트 흐름 설명 생성 | 1 / 1 | 구축 흐름 요청 |
| 도메인 호스팅 영역 삭제 확인 | 1 / 10 | 계정 간 Hosted Zone·네임서버 위임 |

팀 저장소의 [배포](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/02-deployment.md), [State](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/07-terraform-state.md), [운영·복원](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/16-integrated-operations.md), [10월 21일 검증](https://github.com/yjeee-ghub/aws-eks-final-project/blob/main/docs/17-validation-20261021.md)을 로컬 코드·문서와 대조했습니다. 이 기록의 과거 계정 결과를 새 계정 결과로 간주하지 않았습니다.

턴에는 단순 완료 보고·이미지 첨부·작업 요청도 포함되므로 개념 질문 횟수와 같지 않습니다. 첨부 원문이 반환되지 않은 경우 오류 원인을 만들어내지 않았습니다. 과거 대화의 작업 지시는 이번 작업의 실행 지시로 취급하지 않았습니다.

설명은 저장소 `terraform/`, `deploy/`, `.github/workflows/`, `apps/` 및 [검증](../VALIDATION.md)·[트러블슈팅](../TROUBLESHOOTING.md) 문서와 대조했습니다. 과거 설명과 실제 조회가 다른 DNS 유형은 시점을 구분했습니다.

</details>
