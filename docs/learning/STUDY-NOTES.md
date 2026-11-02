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

브라우저 요청은 Route 53 조회 후 NLB·Ingress NGINX를 거쳐 Frontend 또는 Gateway에 도달합니다. 서비스 데이터는 RDS에, 상품 이미지는 S3에 저장합니다.

- 배포: Actions 이미지 빌드·ECR push·kubectl 배포, Argo CD 선언 동기화.
- 확장: HPA로 Pod 수, Cluster Autoscaler로 노드 수 조절.
- 관측: Prometheus 메트릭 수집·Grafana 시각화, CloudWatch 제어 영역 로그·EC2 CPU 경보·SNS 알림.

Actions 직접 배포와 Argo CD를 병행합니다. 이미지 SHA를 Git manifest에 반영하는 파이프라인은 구현하지 않았습니다.

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

Backend는 JDK 17로 빌드합니다. 로컬 빌드와 Docker builder stage의 환경을 구분합니다.

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

`plan` 성공 후에도 실제 생성 과정에서 권한·용량·네트워크 오류가 발생할 수 있습니다. `apply` 결과와 콘솔 상태를 대조합니다.

- **모듈:** Root → network·iam·eks·rds·ecr·s3 연결.
- **관측 설정:** root `monitoring.tf`에서 CloudWatch/SNS 관리.
- **Local State:** 코드와 실제 자원의 연결 정보. 삭제 시 관리 정보 손실.

> **핵심** · tfvars·State·credential 파일은 Git 추적에서 제외합니다. `sensitive`는 일반 출력을 가리며 State를 암호화하지 않습니다.

### 네트워크와 데이터 저장소

- VPC 10.20 대역, 2개 AZ, public 2개·private app 2개·private DB 2개 subnet을 정의.
- EKS 노드는 private app subnet에 배치하고 NAT로 외부 통신.
- RDS: public subnet·공개 접근 사용. private DB subnet은 정의만 존재하며 실제 RDS 배치에는 미사용.
- RDS는 Single-AZ, 암호화·7일 백업 보존을 사용.
- Workbench 접속은 외부 PC 공인 IP/32와 EKS 측 보안 그룹 규칙으로 구분.

`workbench_allowed_cidr`를 최종 PC `/32`로 제한하고 재접속을 확인했습니다. 공인 IP가 바뀌면 CIDR도 갱신해야 합니다.

---

## 4. EKS 접속과 Secret

```powershell
Set-Location C:\yjeee-deployshop
aws eks update-kubeconfig --region ap-northeast-2 --name my-cluster --profile aws-yjeee
kubectl config current-context
kubectl get nodes
kubectl create namespace soldesk
```

`update-kubeconfig`는 기존 클러스터의 로컬 접속 정보를 갱신합니다. `get nodes`로 Ready를 확인하며, 기존 namespace를 다시 생성하면 `AlreadyExists`가 발생합니다.

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

최초 생성 전 환경 변수를 확인합니다. 기존 Secret은 별도로 갱신하며, 실제 값이 든 YAML은 Git 추적에서 제외합니다. base64는 암호화가 아닙니다.

상품 이미지 전용 키를 Terraform 출력으로 전달하고 관리자 키와 분리했습니다. `products/` Put/Get과 필요한 ListBucket 권한을 부여했으며, 공개 읽기는 상품 객체 GetObject로 제한했습니다.

---

## 5. Docker·ECR·앱 배포

ECR은 이미지를 저장하고 EKS는 실행합니다. ECR push 후에는 Deployment 적용과 Pod 교체가 필요합니다.

```powershell
cmd /c "aws ecr get-login-password --region ap-northeast-2 --profile aws-yjeee | docker login --username AWS --password-stdin 193644343848.dkr.ecr.ap-northeast-2.amazonaws.com"
```

PowerShell pipeline에서 400이 발생했으나 cmd native pipeline으로 로그인에 성공했습니다. 문자열 처리 차이가 원인인지는 확정하지 않았습니다.

Backend는 JDK 17로 bootJar를 빌드한 뒤 JRE 17로 실행하고, Frontend는 NGINX로 정적 파일을 제공합니다. Dockerfile 위치에 맞는 build context를 지정합니다.

서비스별 ECR 저장소에 Actions로 이미지를 빌드·push하며 `latest` 태그를 사용합니다. 같은 태그를 덮어쓰므로 커밋별 추적·롤백에 제약이 있습니다.

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

> **핵심** · CPU request 0.5는 스케줄링 기준, limit 1은 상한입니다. CPU HPA의 200%는 노드 전체가 아니라 request 0.5 CPU의 두 배를 의미합니다.

---

## 6. GitHub Actions와 Git 초기 연결

```powershell
git status
git remote -v
git branch -vv
```

`.github/workflows/deploy_ordermsa_with_k8s.yml`이 변경 경로를 감지하고 build·ECR push·apply·restart를 수행합니다.

Actions의 AWS 인증과 EKS Access Entry·접근 정책을 연결합니다. AWS 인증과 Kubernetes 작업 권한은 각각 확인합니다.

Actions Workflow 성공을 확인했습니다. Node 런타임·runner 전환 안내는 의존성 업데이트 시 확인합니다.

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

LoadBalancer Service가 NLB를 연결합니다. Route 53 호스트를 NLB에 연결하고 DNS 이름과 Ingress host를 일치시킵니다.

`/`는 Frontend로, 서비스 접두 경로는 Gateway로 전달합니다. Gateway는 StripPrefix 후 Backend로 라우팅합니다. 경로 변경 지점을 기준으로 404 원인을 확인합니다.

ClusterIssuer `my-issuer`는 HTTP-01을 사용합니다. Certificate가 생성한 TLS Secret을 Ingress가 참조합니다. Ready 상태와 HTTPS·호스트 일치를 함께 확인합니다.

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

CRD annotation 크기 제한을 피하기 위해 server-side apply를 사용했습니다. Argo CD v3.5.5를 확인했으며 `stable` URL은 버전이 고정되어 있지 않습니다.

`server.insecure=true`로 Ingress에서 TLS를 종료하고 Argo 서버에 HTTP를 전달합니다. 초기 admin 비밀번호는 변경합니다.

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

> **핵심** · Backend Pod 수는 HPA가, Frontend 고정값은 Git이 관리합니다.

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

`TARGETS: unknown`이 지속되면 Metrics Server와 Pod request를 확인합니다. 새 Pod는 수집 대기일 수 있으며 노드 공간이 부족하면 Pending이 발생합니다.

---

## 10. OIDC·IRSA·Cluster Autoscaler

클러스터 OIDC issuer 예시:

```text
https://oidc.eks.ap-northeast-2.amazonaws.com/id/50E86F11FAC5ABA3B66F51DF8933D901
```

OIDC issuer ID는 클러스터 식별자입니다. 클러스터 재생성 후에는 새 값으로 갱신합니다.

```powershell
aws eks describe-cluster --name my-cluster --region ap-northeast-2 --profile aws-yjeee --query cluster.identity.oidc.issuer --output text
```

IAM의 자격 증명 공급자에서 클러스터 issuer로 OpenID Connect를 등록합니다.

| Trust 조건 | 값 |
| :--- | :--- |
| **Role** | `autoscaling-pod-role` |
| **Provider** | 해당 EKS OIDC issuer |
| **audience** | `sts.amazonaws.com` |
| **subject** | `system:serviceaccount:kube-system:cluster-autoscaler` |

> **핵심** · IRSA는 ServiceAccount의 OIDC 토큰으로 IAM Role의 임시 자격 증명을 받습니다. 로컬 AWS 프로필과는 별개입니다.

CA 역할에는 AmazonEC2FullAccess·AmazonEKSClusterPolicy·AutoScalingFullAccess를 연결했습니다.

```powershell
kubectl apply -f deploy/k8s/platform/cluster-autoscaler/autoscaler.yml
kubectl get deployment cluster-autoscaler -n kube-system
kubectl logs deployment/cluster-autoscaler -n kube-system --tail=80
kubectl get nodes
```

CA v1.36.1·EKS 1.36을 사용했습니다. ASG discovery 태그와 min 2/max 4를 확인합니다. Terraform이 CA의 desired size 변경을 되돌리지 않도록 구성했습니다.

재시작 직후 leader Lease 획득 대기를 거쳐 정상 루프를 확인했습니다. AccessDenied·확장 불가 메시지가 반복되면 권한과 조건을 점검합니다.

### 부하 테스트와 종료

상품 조회 부하 루프 8개 생성:

```powershell
kubectl run product-load -n soldesk --image=busybox:1.37 --restart=Never -- /bin/sh -c 'for i in 1 2 3 4 5 6 7 8; do while true; do wget -q -O /dev/null http://product-service/product/list || sleep 1; done & done; wait'
kubectl get hpa product-hpa -n soldesk -w
kubectl get pods -n soldesk -l app=product -o wide
kubectl get nodes
kubectl top pods -n soldesk
```

HPA replicas `1→2→4→5`, Product Pod 5개 Running, 노드 `2→3` 확장을 확인했습니다. 다음 명령으로 부하를 종료합니다.

```powershell
kubectl delete pod product-load -n soldesk
kubectl get hpa product-hpa -n soldesk -w
```

> **핵심** · 부하 제거 후 CPU가 감소하고 안정화 대기 뒤 replicas가 `5→1`로 줄었습니다. 노드 축소는 별도 동작입니다.

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

Targets에서 node-exporter와 spring-apps가 UP인지 확인합니다.

```promql
up{job="node-exporter"}
up{job="spring-apps"}
```

각 job의 시계열 4개에서 `up=1`을 확인했습니다.

1. 초기 `admin/admin` 로그인 → 비밀번호 변경.
2. Prometheus 데이터 소스 연결: `http://prometheus-service.monitoring.svc.cluster.local:9090`.
3. Node Exporter Full(1860)·앱 수집 상태·CPU·JVM Heap·HTTP 요청 패널 구성.

```promql
process_cpu_usage{job="spring-apps"} * 100
sum by (app, pod) (jvm_memory_used_bytes{job="spring-apps", area="heap"})
sum by (app) (rate(http_server_requests_seconds_count{job="spring-apps", uri!~"/health|/actuator.*"}[5m]))
```

> **핵심** · 프로세스 CPU 지표와 HPA의 request 대비 사용률은 다릅니다. HTTP rate는 5분 구간의 평균입니다.

---

## 12. Grafana EBS 영구 저장소 상세

### 12-1. 왜 메모리와 볼륨을 함께 바꿨는가

Grafana OOM으로 limit을 500Mi→1Gi, request를 512Mi로 조정했습니다. 설정 소실은 별도로 EBS PVC를 연결해 조치했습니다.

> **핵심** · 메모리는 실행 중 데이터를 처리하고 EBS는 파일을 저장합니다. 메모리 증설만으로 Pod 교체 후 설정이 보존되지는 않습니다.

### 12-2. EBS CSI용 IAM 역할 만들기

1. IAM 콘솔에서 실습 클러스터의 OIDC 공급자가 있는지 확인.
2. 새 역할 `yjeee-deployshop-ebs-csi-role`을 만들고 Web identity/해당 OIDC를 선택.
3. audience는 sts.amazonaws.com, subject는 `system:serviceaccount:kube-system:ebs-csi-controller-sa`로 제한.
4. 권한 정책 `AmazonEBSCSIDriverPolicyV2`를 연결.
5. 생성한 역할 ARN을 EKS 애드온 연결 단계에 사용.

Trust의 Provider ARN과 조건 키에 같은 issuer ID를 사용합니다.

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

CA와 EBS CSI는 같은 OIDC 공급자를 사용해도 역할과 ServiceAccount는 다릅니다. EBS에는 볼륨 권한을, CA에는 ASG 조절 권한을 부여합니다.

### 12-3. EKS 애드온 연결

EKS Add-ons에서 EBS CSI Driver를 추가하고 IRSA 역할을 연결합니다. 애드온 버전은 EKS 호환성을 확인해 선택합니다.

```powershell
kubectl get csidriver ebs.csi.aws.com
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl get daemonset -n kube-system
```

Controller 2/2와 노드 DaemonSet 정상을 확인했습니다. DaemonSet 수는 노드 수에 따라 달라집니다.

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

> **핵심** · ReadWriteOnce는 한 노드 기준의 읽기·쓰기 모드입니다. Grafana replica 1·Recreate로 동시 연결을 피하며, EBS는 생성된 AZ에서 연결합니다.

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

Deployment 설정 일부이며 실제 파일은 `grafana-depl_svc.yml`입니다.

- **fsGroup:** 데이터 경로 쓰기 권한.
- **OnRootMismatch:** 소유권 변경 범위 조절.
- **Recreate:** 기존 Pod 종료 후 생성, 재배포 중 중단 가능.

### 12-6. Argo CD에 최신 파일 반영

변경 commit·push 후 Sync합니다. 이전 커밋을 참조하면 hard refresh로 최신 리비전을 갱신합니다.

```powershell
kubectl annotate application msa-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application msa-monitoring -n argocd
kubectl get pvc -n monitoring
kubectl get pods -n monitoring
kubectl describe pvc grafana-data -n monitoring
```

PVC가 없으면 Argo CD 리비전과 Sync를 먼저 확인합니다. Pending이면 Events에서 consumer 대기·IAM·AZ 문제를 구분합니다. 목표 상태는 PVC Bound·Grafana READY 1/1입니다.

### 12-7. 데이터 보존 확인

새 EBS는 빈 볼륨이므로 과거 설정이 자동 복원되지 않습니다. 비밀번호·데이터 소스·대시보드를 재설정하고 저장합니다.

```powershell
kubectl rollout restart deployment grafana -n monitoring
kubectl rollout status deployment grafana -n monitoring
kubectl get pvc grafana-data -n monitoring
```

재시작 후 변경한 계정으로 로그인하고 데이터 소스와 대시보드 유지를 확인합니다.

> **핵심** · Retain·PVC 보호는 자동 삭제를 막으며 백업을 대신하지 않습니다. 종료 시 EBS·비용을 확인합니다. Prometheus 영구 볼륨은 적용하지 않았습니다.

---

## 13. monitoring 인증서 OutOfSync 수정

Certificate와 Ingress annotation이 같은 인증서를 중복 관리해 duration·renewBefore 차이가 반복되었습니다.

Ingress issuer annotation을 제거하고 명시적 Certificate·TLS Secret 참조를 유지했습니다. 이후 Synced/Healthy와 HTTPS를 확인했습니다. `ArgoCD.png`는 수정 전 화면입니다.

---

## 14. CloudWatch·SNS

`monitoring.tf`에서 EKS api·audit·authenticator 로그와 로그 그룹을 구성했습니다. 보존 기간은 7일이며 prevent_destroy를 적용했습니다. 앱 stdout 수집은 포함하지 않았습니다.

SNS topic은 `msa-monitoring-alerts`입니다. 이메일 구독 승인 후 직접 publish·CloudWatch 경보 메일 수신을 확인했습니다.

CPU 경보 조건은 다음과 같습니다.

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

> **핵심** · 수동 ALARM 전환 후 SNS 이메일 수신과 OK 복귀를 확인했습니다. 실제 CPU 임계값 초과는 검증하지 않았습니다.

`order_notifications.tf`는 선택적 인프라 정의입니다. 앱 주문 이벤트·SNS 연동은 구현하지 않았습니다.

---

## 15. 웹·Postman·Workbench 검증

웹 로그인 후 상품을 구매했습니다. 상품 ID 1은 초기 확인용이며 최종 검증 대상은 ID 2입니다.

Postman 로그인은 `/member-service/member/doLogin`으로 요청합니다. 응답 토큰을 후속 요청의 Bearer 인증에 사용하며 비밀번호·토큰은 공개하지 않습니다.

상품 ID 2는 재고 10에서 웹 1개 구매 후 9, API 2개 주문 후 7로 감소했습니다.

```http
POST /ordering-service/ordering/create
Authorization: Bearer <로그인_access_token>
Content-Type: application/json

{"productId": 2, "productCount": 2}
```

응답 201과 주문 ID 4를 확인하고 다음 SQL로 DB를 대조했습니다.

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

SQL은 snake_case 필드를 사용하므로 API JSON 이름과 구분합니다.

수량 8 요청에서 400·재고 부족을 확인했고 재고 7·기존 주문이 유지되었습니다. 순차 검증이며 동시성·결제·분산 트랜잭션은 검증하지 않았습니다.

Error 1046은 기본 DB 미선택이 원인이며 `USE ordermsa` 후 해결했습니다. 접속 실패와 SQL 실행 실패를 구분합니다.

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

> **핵심** · 종료 전 RDS 보호·스냅샷, S3 버전 객체, EBS Retain, 로그 그룹 보호, 로컬 State를 확인합니다.
