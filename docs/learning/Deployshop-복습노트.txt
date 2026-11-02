**DEPLOYSHOP · STUDY NOTES**

# 구축·검증 복습 노트

> 명령의 목적 → 정상 상태 → 리소스 간 연결.

[문서 목록](../README.md) · [핵심 복습](CORE-REVIEW.md) · [구축 절차](../SETUP.md)

---

**환경** · Windows PowerShell · `aws-yjeee` · `ap-northeast-2`

| 학습 구간 | 주요 내용 |
| :--- | :--- |
| **[01–04 인프라 기반](#1-전체-연결-구조)** | 전체 구조·도구·Terraform·EKS Secret |
| **[05–08 이미지와 배포](#5-dockerecr앱-배포)** | Docker·ECR·Actions·DNS/TLS·Argo CD |
| **[09–12 확장과 관측](#9-hpa와-metrics-server)** | HPA·IRSA·CA·Prometheus·Grafana EBS |
| **[13–16 운영 검증](#13-monitoring-인증서-outofsync-수정)** | 인증서 충돌·CloudWatch/SNS·웹/API/DB·최종 점검 |

---

## 1. 전체 연결 구조

브라우저 → Route 53 → NLB → Ingress NGINX → Frontend / API Gateway → Member·Product·Ordering → RDS. 상품 이미지는 S3에 저장.

- 배포: Actions 이미지 빌드·ECR push·kubectl 배포, Argo CD 선언 동기화.
- 확장: HPA로 Pod 수, Cluster Autoscaler로 노드 수 조절.
- 관측: Prometheus 메트릭 수집·Grafana 시각화, CloudWatch 제어 영역 로그·EC2 CPU 경보·SNS 알림.

Actions 직접 배포와 Argo CD 병행. 이미지 SHA를 Git manifest에 반영하는 GitOps 파이프라인은 미구현.

---

## 2. 사전 도구·AWS 프로필

```powershell
Set-Location C:\yjeee-deployshop
aws --version
terraform version
kubectl version --client
docker version
git --version
aws sts get-caller-identity --profile aws-yjeee
```

- `Set-Location`: 작업 폴더 변경. 상대 경로의 기준.
- `sts get-caller-identity`: 인증된 AWS 계정·principal 조회. 개별 작업 권한은 별도 확인.
- `--profile aws-yjeee`: 로컬 AWS CLI의 해당 프로필 선택.
- Docker Desktop 엔진 실행 상태 확인.

Backend 빌드: JDK 17. 로컬 빌드와 Docker builder stage의 실행 환경 구분.

---

## 3. Terraform 최초 적용

```powershell
Set-Location C:\yjeee-deployshop\terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

| 명령 | 의미 | 확인할 정상 결과 |
|---|---|---|
| **init** | provider·module 준비 | 초기화 완료 |
| **fmt -check -recursive** | 하위 폴더까지 포맷 확인 | 수정이 필요한 파일이 없는 상태 |
| **validate** | 구문과 구성 정합성 확인 | configuration valid |
| **plan** | 현재 state와 선언의 차이 확인 | 의도한 생성·변경만 포함 |
| **apply** | 승인한 인프라 변경 실행 | Apply complete |
| **output** | 모듈이 외부로 내보낸 값 확인 | cluster·RDS·ECR·S3 정보 |

`plan` 성공 후에도 실제 생성 과정의 권한·용량·네트워크 오류 가능. `apply` 결과·콘솔 상태 대조 필요.

- **모듈:** Root → network·iam·eks·rds·ecr·s3 연결.
- **관측 설정:** root `monitoring.tf`에서 CloudWatch/SNS 관리.
- **Local State:** 코드와 실제 자원의 연결 정보. 삭제 시 관리 정보 손실.

> **핵심** · `terraform.tfvars`·`*.tfstate*`·`.terraform`·credential 파일은 Git 추적 제외. `sensitive = true`는 일반 출력 가림이며 State 암호화와 별개.

### 네트워크와 데이터 저장소

- VPC 10.20 대역, 2개 AZ, public 2개·private app 2개·private DB 2개 subnet을 정의.
- EKS 노드는 private app subnet에 배치하고 NAT로 외부 통신.
- RDS: public subnet·공개 접근 사용. private DB subnet은 정의만 존재하며 실제 RDS 배치에는 미사용.
- RDS는 Single-AZ, 암호화·7일 백업 보존을 사용.
- Workbench 접속은 외부 PC 공인 IP/32와 EKS 측 보안 그룹 규칙으로 구분.

`workbench_allowed_cidr`: 임시 전체 허용 → 최종 PC `/32` 적용·재접속 확인. PC 공인 IP 변경 시 CIDR 갱신 필요.

---

## 4. EKS 접속과 Secret

```powershell
Set-Location C:\yjeee-deployshop
aws eks update-kubeconfig --region ap-northeast-2 --name my-cluster --profile aws-yjeee
kubectl config current-context
kubectl get nodes
kubectl create namespace soldesk
```

`update-kubeconfig`: 기존 클러스터의 로컬 접속 정보 갱신. `get nodes`로 Ready 확인. 기존 namespace 재생성 시 `AlreadyExists` 발생.

애플리케이션 Secret:

| Secret | 키 | 소비 목적 |
|---|---|---|
| **my-app-secrets** | DB_HOST, DB_PW | RDS 연결 |
| **aws-secret** | AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY | 상품 이미지 S3 업로드 |

로컬 환경 변수로 Secret 생성:

```powershell
kubectl create secret generic my-app-secrets -n soldesk --from-literal=DB_HOST="$env:DEPLOYSHOP_DB_HOST" --from-literal=DB_PW="$env:DEPLOYSHOP_DB_PW"
kubectl create secret generic aws-secret -n soldesk --from-literal=AWS_ACCESS_KEY_ID="$env:DEPLOYSHOP_S3_KEY" --from-literal=AWS_SECRET_ACCESS_KEY="$env:DEPLOYSHOP_S3_SECRET"
kubectl get secrets -n soldesk
```

최초 생성 전 환경 변수 값 확인. 기존 Secret은 별도 갱신 필요. Secret YAML은 Git 추적 제외. base64 인코딩은 암호화와 별개.

상품 이미지 전용 IAM 키는 Terraform sensitive 출력으로 전달. 계정 관리용 키와 분리. `products/` Put/Get·필요한 ListBucket 권한 적용, 공개 읽기는 상품 객체 GetObject로 제한.

---

## 5. Docker·ECR·앱 배포

ECR: 이미지 저장. EKS: 이미지 실행. ECR push 후 Deployment 적용·Pod 교체 필요.

```powershell
cmd /c "aws ecr get-login-password --region ap-northeast-2 --profile aws-yjeee | docker login --username AWS --password-stdin 193644343848.dkr.ecr.ap-northeast-2.amazonaws.com"
```

`Login Succeeded` 확인. PowerShell pipeline에서 400 발생, cmd native pipeline으로 로그인 성공. 문자열 처리 원인은 미확정.

Backend: JDK 17로 Gradle bootJar 빌드 → JRE 17 이미지로 실행. Frontend: NGINX로 정적 파일 제공. Dockerfile 위치에 맞는 build context 지정.

ECR repository: apigateway·member-service·product-service·ordering-service·frontend-service. Actions로 빌드·push, 태그는 `latest`. 같은 태그 덮어쓰기로 커밋별 추적·롤백에 제약.

```powershell
kubectl apply -f deploy/k8s/apps/apigateway
kubectl apply -f deploy/k8s/apps/member
kubectl apply -f deploy/k8s/apps/product
kubectl apply -f deploy/k8s/apps/ordering
kubectl apply -f deploy/k8s/apps/frontend
kubectl get deployment,pod,service -n soldesk
kubectl describe pod -n soldesk <Pod이름>
```

| 대상 | 역할·확인 기준 |
| :--- | :--- |
| **Deployment** | 원하는 Pod 상태 유지 |
| **Service** | Pod 교체와 무관한 내부 접속 주소 |
| **Pod** | `READY 1/1`·restart 횟수·Events 확인 |
| **`/health` probe** | 프로세스 상태 확인·구매 기능 검증은 별도 |

> **핵심** · backend CPU request 0.5, limit 1은 각각 스케줄링 기준과 사용 상한. HPA의 CPU 사용률 계산은 request를 기준으로 하므로 200%는 노드 CPU 전체 200%가 아니라 0.5 CPU의 두 배 사용을 의미.

---

## 6. GitHub Actions와 Git 초기 연결

```powershell
git status
git remote -v
git branch -vv
```

`.github/workflows/deploy_ordermsa_with_k8s.yml`이 push 시 변경 경로를 검사하고 build·ECR push·kubectl apply·rollout restart를 수행.

Actions Secrets `AWS_KEY`·`AWS_SECRET`: AWS 인증용. EKS Access Entry·접근 정책으로 클러스터 권한 연결. AWS 인증과 Kubernetes 권한은 각각 확인.

Actions Workflow 성공 확인. Node 런타임·runner 전환 안내는 의존성 업데이트 시 확인.

---

## 7. NLB·Ingress·DNS·TLS

```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/aws/deploy.yaml
kubectl get pods,svc -n ingress-nginx
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml
kubectl get pods -n cert-manager
kubectl apply -f deploy/k8s/platform/ingress
kubectl get ingress -n soldesk
kubectl get clusterissuer my-issuer
kubectl get certificate -n soldesk
```

NGINX LoadBalancer Service → NLB 연결. Route 53의 server·argo·prometheus·grafana 호스트 → NLB 연결. DNS 이름과 Ingress host 일치 필요.

`/`는 frontend, 서비스 접두 경로는 API Gateway로 전달됨. Gateway가 StripPrefix로 접두 경로를 제거해 backend로 라우팅. 경로가 어디서 변경되는지 확인하면 404의 발생 위치를 구분하는 데 도움이 됨.

cert-manager의 ClusterIssuer `my-issuer`는 Let's Encrypt HTTP-01을 사용. namespace별 Certificate가 TLS Secret을 만들고 Ingress가 참조. 인증서 Ready=True, 실제 HTTPS 접속, 브라우저의 호스트 일치를 함께 확인.

---

## 8. Argo CD와 self-heal

```powershell
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f deploy/k8s/platform/argocd
kubectl apply -f deploy/argocd/applications
kubectl apply -f deploy/argocd/root-app.yml
kubectl get applications -n argocd
```

대형 CRD annotation 크기 제한 회피를 위해 server-side apply 사용. Argo CD v3.5.5 확인. `stable` URL은 버전 미고정.

`server.insecure=true`: Ingress에서 TLS 종료, Argo 서버로 HTTP 전달. 초기 admin 비밀번호 변경.

- root msa-root는 applications 폴더를 읽고 9개의 자식 Application을 생성·관리.
- Synced는 Git 선언과 live 리소스의 일치 상태.
- Healthy는 리소스 health 판정. 둘은 별개.
- selfHeal: live drift를 Git 선언 상태로 복구.
- prune: Git에서 제거한 리소스 삭제. PVC는 별도 보호 설정 적용.

```powershell
kubectl scale deployment frontend-depl --replicas=2 -n soldesk
kubectl get deployment frontend-depl -n soldesk -w
```

- **Frontend:** 수동 replicas `2 → 1` self-heal 확인. `-w` 관찰·Ctrl+C 종료.
- **Backend:** HPA·Argo CD 제어 충돌 → `/spec/replicas` 제외·`RespectIgnoreDifferences=true` 적용.

> **핵심** · Backend Pod 수는 HPA, Frontend 고정값은 Git이 관리.

---

## 9. HPA와 Metrics Server

```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes
kubectl top pods -n soldesk
kubectl apply -f deploy/k8s/platform/hpa
kubectl get hpa -n soldesk
```

| 구성 | 기준 |
| :--- | :--- |
| **Metrics Server** | HPA·`kubectl top`의 리소스 메트릭 제공 |
| **Member·Product·Ordering HPA** | CPU 30% |
| **Gateway HPA** | CPU 70% |
| **Pod 수** | min 1 / max 5 |

`TARGETS: unknown` 지속 시 Metrics Server·Pod request 확인. 새 Pod는 수집 대기 가능. 확장 후 노드 공간 부족 시 Pending 발생 가능.

---

## 10. OIDC·IRSA·Cluster Autoscaler

클러스터 OIDC issuer 예시:

```text
https://oidc.eks.ap-northeast-2.amazonaws.com/id/50E86F11FAC5ABA3B66F51DF8933D901
```

OIDC issuer ID는 클러스터 식별자. 재생성 후 새 값으로 갱신.

```powershell
aws eks describe-cluster --name my-cluster --region ap-northeast-2 --profile aws-yjeee --query cluster.identity.oidc.issuer --output text
```

IAM → 자격 증명 공급자 → OpenID Connect 등록.

| Trust 조건 | 값 |
| :--- | :--- |
| **Role** | `autoscaling-pod-role` |
| **Provider** | 해당 EKS OIDC issuer |
| **audience** | `sts.amazonaws.com` |
| **subject** | `system:serviceaccount:kube-system:cluster-autoscaler` |

> **핵심** · ServiceAccount의 `eks.amazonaws.com/role-arn` → IAM Role 연결. OIDC 토큰으로 임시 자격 증명을 받는 IRSA 방식. 로컬 AWS 프로필과 별개.

CA 역할에는 수업 정책 AmazonEC2FullAccess, AmazonEKSClusterPolicy, AutoScalingFullAccess를 연결.

```powershell
kubectl apply -f deploy/k8s/platform/cluster-autoscaler/autoscaler.yml
kubectl get deployment cluster-autoscaler -n kube-system
kubectl logs deployment/cluster-autoscaler -n kube-system --tail=80
kubectl get nodes
```

CA 버전 v1.36.1, EKS 1.36을 사용. ASG 자동 발견 태그와 min2/max4 확인. Terraform은 CA가 바꾸는 desired size를 무시하도록 구성. 그렇지 않으면 apply 시 확장한 크기를 되돌릴 수 있음.

재시작 직후 leader Lease 획득 대기 → 정상 루프 확인. AccessDenied·no expansion option 반복 시 권한·확장 조건 점검.

### 부하 테스트와 종료

상품 조회 부하 루프 8개 생성:

```powershell
kubectl run product-load -n soldesk --image=busybox:1.37 --restart=Never -- /bin/sh -c 'for i in 1 2 3 4 5 6 7 8; do while true; do wget -q -O /dev/null http://product-service/product/list || sleep 1; done & done; wait'
kubectl get hpa product-hpa -n soldesk -w
kubectl get pods -n soldesk -l app=product -o wide
kubectl get nodes
kubectl top pods -n soldesk
```

확장 결과: HPA replicas `1→2→4→5`, Product Pod 5개 Running, 노드 `2→3`. 부하 종료:

```powershell
kubectl delete pod product-load -n soldesk
kubectl get hpa product-hpa -n soldesk -w
```

> **핵심** · 부하 제거 → CPU 감소 → 안정화 대기 → replicas `5→1`. 노드 축소는 HPA와 별도 동작·확인.

---

## 11. Prometheus·Grafana

| 수집 대상 | 수집 경로 |
| :--- | :--- |
| **노드** | node-exporter DaemonSet·hostNetwork 9100 |
| **앱** | soldesk annotation 기반 발견·8080 `/actuator/prometheus` |
| **Prometheus** | monitoring namespace에서 두 job 수집 |

```powershell
kubectl get pods,svc -n monitoring
kubectl get daemonset -n monitoring
kubectl get certificate -n monitoring
```

Prometheus Targets에서 node-exporter와 spring-apps가 UP인지 확인.

```promql
up{job="node-exporter"}
up{job="spring-apps"}
```

각 job의 시계열 4개 모두 `up=1`: 메트릭 수집 성공.

1. 초기 `admin/admin` 로그인 → 비밀번호 변경.
2. Prometheus 데이터 소스 연결: `http://prometheus-service.monitoring.svc.cluster.local:9090`.
3. Node Exporter Full(1860)·앱 수집 상태·CPU·JVM Heap·HTTP 요청 패널 구성.

```promql
process_cpu_usage{job="spring-apps"} * 100
sum by (app, pod) (jvm_memory_used_bytes{job="spring-apps", area="heap"})
sum by (app) (rate(http_server_requests_seconds_count{job="spring-apps", uri!~"/health|/actuator.*"}[5m]))
```

> **핵심** · CPU 패널은 프로세스 메트릭이며 HPA가 보는 request 대비 사용률과 같다고 해석하지 않음. HTTP rate는 5분 구간 평균.

---

## 12. Grafana EBS 영구 저장소 상세

### 12-1. 왜 메모리와 볼륨을 함께 바꿨는가

Grafana OOMKilled(137) 발생 → limit 500Mi→1Gi·request 512Mi 조정. 설정 소실 → `/var/lib/grafana`에 EBS PVC 연결. 메모리·저장소 문제 각각 조치.

> **핵심** · 메모리: 실행 중 데이터 처리. EBS: 파일 영구 저장. 메모리 증설만으로 Pod 교체 후 설정 보존 불가.

### 12-2. EBS CSI용 IAM 역할 만들기

1. IAM 콘솔에서 실습 클러스터의 OIDC 공급자가 있는지 확인.
2. 새 역할 `yjeee-deployshop-ebs-csi-role`을 만들고 Web identity/해당 OIDC를 선택.
3. audience는 sts.amazonaws.com, subject는 `system:serviceaccount:kube-system:ebs-csi-controller-sa`로 제한.
4. 권한 정책 `AmazonEBSCSIDriverPolicyV2`를 연결.
5. 생성한 역할 ARN을 EKS 애드온 연결 단계에 사용.

trust의 핵심 조건은 아래 형태. provider ARN과 두 조건 키에 같은 issuer ID를 사용.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::193644343848:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/50E86F11FAC5ABA3B66F51DF8933D901"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-northeast-2.amazonaws.com/id/50E86F11FAC5ABA3B66F51DF8933D901:aud": "sts.amazonaws.com",
        "oidc.eks.ap-northeast-2.amazonaws.com/id/50E86F11FAC5ABA3B66F51DF8933D901:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      }
    }
  }]
}
```

CA와 같은 OIDC 공급자를 사용하지만 역할과 service account는 다름. EBS 역할에는 볼륨 생성·연결 권한이, CA 역할에는 ASG 크기 조절 권한이 필요.

### 12-3. EKS 애드온 연결

EKS 콘솔 → my-cluster → Add-ons → Amazon EBS CSI Driver를 추가. 인증 방식은 이 실습에서 IRSA를 사용했고, 위 역할을 연결. 사용 가능한 애드온 버전은 현재 EKS 호환성을 확인해 선택.

```powershell
kubectl get csidriver ebs.csi.aws.com
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl get daemonset -n kube-system
```

ebs-csi-controller 2/2·ebs-csi-node DaemonSet 정상 확인. DaemonSet 수는 노드 수에 따라 변동.

### 12-4. StorageClass와 PVC

저장소 파일: `deploy/k8s/platform/monitoring/grafana-storage.yml`

| 설정 | 의미 |
|---|---|
| **provisioner: ebs.csi.aws.com** | EBS CSI 드라이버로 동적 볼륨 생성 |
| **type: gp3** | EBS gp3 볼륨 사용 |
| **encrypted: true** | 저장 시 암호화 활성화 |
| **fstype: ext4** | 파일 시스템 |
| **WaitForFirstConsumer** | Pod의 배치 위치를 보고 적절한 AZ에 볼륨 생성 |
| **allowVolumeExpansion: true** | PVC 확장 허용 설정; 실제 변경 후 확인 필요 |
| **reclaimPolicy: Retain** | PVC 삭제 뒤 PV/EBS를 자동 폐기하지 않음 |
| **PVC 5Gi / ReadWriteOnce** | 단일 노드에서 read/write로 마운트하는 사용 방식 |
| **Prune=false,Delete=false** | Argo CD prune·Application 삭제에서 PVC 보호 |

> **핵심** · ReadWriteOnce: 한 노드 기준 읽기·쓰기 모드. Pod 1개 제한과 구분. Grafana replica 1·Recreate로 동시 볼륨 연결 충돌 방지. EBS는 생성된 AZ 안에서 연결 가능.

### 12-5. Grafana Deployment 연결

```yaml
strategy:
  type: Recreate
# template.spec 내부
securityContext:
  fsGroup: 472
  fsGroupChangePolicy: OnRootMismatch
# containers의 Grafana 항목 내부
volumeMounts:
  - name: grafana-data
    mountPath: /var/lib/grafana
# template.spec 내부
volumes:
  - name: grafana-data
    persistentVolumeClaim:
      claimName: grafana-data
```

Deployment 설정 일부 · 실제 파일: `grafana-depl_svc.yml`.

- **fsGroup:** 데이터 경로 쓰기 권한.
- **OnRootMismatch:** 소유권 변경 범위 조절.
- **Recreate:** 기존 Pod 종료 후 생성, 재배포 중 중단 가능.

### 12-6. Argo CD에 최신 파일 반영

변경 commit·push 후 Sync. 이전 커밋 참조 시 hard refresh로 최신 리비전 갱신.

```powershell
kubectl annotate application msa-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application msa-monitoring -n argocd
kubectl get pvc -n monitoring
kubectl get pods -n monitoring
kubectl describe pvc grafana-data -n monitoring
```

Git에 새 파일이 있어도 Argo CD가 이전 리비전을 보고 있으면 아직 PVC가 없음. 새 리비전과 Sync 결과를 먼저 확인. PVC Pending이면 Events에서 consumer 대기인지 IAM 권한·용량·AZ 문제인지 구분. 정상 목표: PVC Bound·Grafana READY 1/1.

### 12-7. 데이터 보존 확인

새 EBS는 빈 볼륨으로 생성. 과거 설정 자동 복원 불가. 비밀번호·데이터 소스·대시보드 재설정 후 저장.

```powershell
kubectl rollout restart deployment grafana -n monitoring
kubectl rollout status deployment grafana -n monitoring
kubectl get pvc grafana-data -n monitoring
```

재시작 후 변경한 계정으로 로그인되고 Prometheus 데이터 소스와 대시보드가 남아 있는지 확인.

> **핵심** · Retain·PVC 보호: 자동 삭제 방지. 백업·AZ 장애 복구와 별개. 종료 시 남은 EBS·비용 확인. Prometheus 영구 볼륨은 미적용.

---

## 13. monitoring 인증서 OutOfSync 수정

Git Certificate와 Ingress annotation이 같은 인증서를 중복 관리. duration·renewBefore 차이 반복 발생.

최종 변경은 monitoring Ingress의 cert-manager.io/cluster-issuer annotation 제거 한 줄. 명시적 Certificate, issuerRef, TLS secret 참조는 유지. 반영 후 Synced/Healthy·HTTPS 정상 확인. `ArgoCD.png`는 이 수정 전 화면.

---

## 14. CloudWatch·SNS

Terraform monitoring.tf에서 EKS control plane 로그 api·audit·authenticator를 켜고 `/aws/eks/my-cluster/cluster` 로그 그룹을 사용. 보존 기간 7일과 prevent_destroy가 설정돼 있음. 애플리케이션 stdout을 CloudWatch로 모으는 구성은 포함하지 않음.

SNS topic: `msa-monitoring-alerts`. 이메일 구독 승인 후 알림 수신 가능. 직접 publish·CloudWatch ALARM 메일 수신 확인.

CPU alarm은 다음 조건.

| 항목 | 값 |
|---|---|
| **이름** | my-cluster-node-group-cpu-high |
| **namespace / metric** | AWS/EC2 / CPUUtilization |
| **dimension** | 해당 노드 그룹의 AutoScalingGroupName |
| **statistic** | Average |
| **period** | 300초 |
| **evaluation / datapoints** | 2 / 2 |
| **threshold** | 80 이상 |
| **missing** | missing |
| **action** | ALARM 및 OK에서 SNS |

수동 알림 경로 테스트:

```powershell
aws cloudwatch set-alarm-state --alarm-name my-cluster-node-group-cpu-high --state-value ALARM --state-reason "Manual notification path test for Deployshop" --region ap-northeast-2 --profile aws-yjeee
```

> **핵심** · 수동 ALARM 전환 → SNS → 이메일 수신 확인. 이후 지표 재평가로 OK 복귀. 실제 CPU 임계값 초과는 미검증.

`order_notifications.tf`: 선택적 인프라 정의. 애플리케이션 주문 이벤트·SNS 연동은 미구현.

---

## 15. 웹·Postman·Workbench 검증

웹 로그인 후 상품 상세 페이지에서 구매를 수행. 상품 ID 1은 재고 9→8 화면이 있음. 별도의 최종 검증 상품은 ID 2.

Postman 로그인: POST `/member-service/member/doLogin`, JSON loginId/password. 성공 응답의 token을 후속 요청 Authorization Bearer에 입력. 비밀번호·token·refreshToken 값은 공개하지 않음.

상품 ID 2: 초기 재고 10 → 웹 1개 구매 후 9 → API 2개 주문 후 7.

```http
POST /ordering-service/ordering/create
Authorization: Bearer <로그인_access_token>
Content-Type: application/json

{"productId": 2, "productCount": 2}
```

응답 201, 주문 ID 4 확인. RDS ordermsa에서 다음 SELECT를 수행.

```sql
USE ordermsa;
SET @product_id = 2;
SELECT id, name, price, stock_quantity, image_url
FROM product
WHERE id = @product_id;
SELECT id, member_id, product_id, quantity, order_status
FROM ordering
WHERE product_id = @product_id
ORDER BY id;
```

| DB 확인 항목 | 결과 |
| :--- | :--- |
| **상품 / 회원** | `product_id=2` / `member_id=2` |
| **재고** | `stock_quantity=7` |
| **주문 ID 3** | quantity 1·ORDERED |
| **주문 ID 4** | quantity 2·ORDERED |

SQL 필드는 snake_case, API JSON과 이름 구분.

같은 상품에 productCount=8을 요청해 400과 `재고 부족` 확인. 재조회 시 재고 7과 기존 두 주문만 유지. API 응답·DB·웹을 대조한 순차 검증. 동시성 부하에서의 재고 원자성, 결제, 분산 트랜잭션 검증은 포함하지 않음.

Workbench Error1046은 DB 미선택이 원인이었고 USE ordermsa 실행 후 해결. 접속 실패와 SQL 실행 실패를 구분.

---

## 16. 최종 확인

```powershell
kubectl get applications -n argocd
kubectl get pods,hpa -n soldesk
kubectl get nodes
kubectl get pods,pvc -n monitoring
kubectl get certificate -A
git status --short
```

> **핵심** · 종료 전 확인: RDS 삭제 보호·최종 스냅샷, S3 버전 객체, EBS Retain, CloudWatch prevent_destroy, 로컬 Terraform state.
