**DEPLOYSHOP · SETUP**

# 구축 및 재현 절차

> 인프라 → 클러스터 → 배포 → 관측 → 기능 검증.

[문서 목록](README.md) · [상세 복습](learning/STUDY-NOTES.md) · [실행 결과](VALIDATION.md)

---

**시작 전** · 계정·도메인·OIDC·서브넷·이미지 주소 변경. `stable/latest` URL은 버전 미고정.

---

## 1. 사전 준비와 관리 범위

**도구** · AWS CLI · Terraform · kubectl · Docker Desktop · Git · JDK 17

**환경** · 프로필 `aws-yjeee` · 리전 `ap-northeast-2` · Local State

| 관리 방식 | 구성 대상 |
| :--- | :--- |
| **Terraform** | VPC·IAM·EKS·RDS·ECR·S3·CloudWatch/SNS |
| **CLI 설치** | Ingress NGINX·cert-manager·Argo CD·Metrics Server |
| **콘솔 연결** | Route 53·OIDC Provider·IRSA 역할·EBS CSI 애드온 |

```powershell
Set-Location C:\yjeee-deployshop
aws sts get-caller-identity --profile aws-yjeee
terraform version
kubectl version --client
docker version
git --version
```

---

## 2. Terraform 적용

`terraform/variables.tf` 기준으로 로컬 `terraform.tfvars` 작성.

| 항목 | 구성값 |
| :--- | :--- |
| **클러스터 / 노드 그룹** | `my-cluster` / `my-nodes` |
| **인스턴스** | `t3.large` |
| **노드 수** | min 2 · desired 2 · max 4 |

> **인증값 관리** · tfvars·State·실제 비밀번호는 Git 추적 제외. `sensitive`는 일반 출력만 가림.

```powershell
Set-Location C:\yjeee-deployshop\terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

> **DB 접근** · Public RDS 유지. `workbench_allowed_cidr = "<접속_PC_공인_IP>/32"`로 외부 접근 제한, EKS 보안 그룹 규칙 별도 유지.

---

## 3. kubeconfig와 Secret

```powershell
aws eks update-kubeconfig --region ap-northeast-2 --name my-cluster --profile aws-yjeee
kubectl config current-context
kubectl get nodes
kubectl create namespace soldesk
```

| Secret | 전달값 | 용도 |
| :--- | :--- | :--- |
| **`my-app-secrets`** | `DB_HOST`·`DB_PW` | 앱 → RDS 연결 |
| **`aws-secret`** | `AWS_ACCESS_KEY_ID`·`AWS_SECRET_ACCESS_KEY` | 상품 이미지 S3 업로드 |

기존 Secret의 키·적용 범위 확인. 실제 값이 들어 있는 YAML은 Git 추적 제외.

AWS 프로필용 자격 증명, GitHub Actions 인증, 상품 S3 전용 IAM 키, Pod용 IRSA는 서로 용도가 다름. S3 전용 키는 Terraform의 `product_s3_access_key_id`·`product_s3_secret_access_key` 출력에서 로컬 변수로 받아 사용.

---

## 4. 이미지와 애플리케이션 배포

| 대상 | 빌드·실행 |
| :--- | :--- |
| **Backend** | JDK 17 bootJar → JRE 17 |
| **Frontend** | NGINX 정적 파일 제공 |

Actions Secrets `AWS_KEY`·`AWS_SECRET` 등록, 해당 IAM principal의 EKS Access Entry·접근 정책 연결. 변경 경로 확인 → 이미지 빌드·push → kubectl apply·rollout restart.

```powershell
kubectl apply -f deploy/k8s/apps/apigateway
kubectl apply -f deploy/k8s/apps/member
kubectl apply -f deploy/k8s/apps/product
kubectl apply -f deploy/k8s/apps/ordering
kubectl apply -f deploy/k8s/apps/frontend
kubectl get pods,svc -n soldesk
```

> **배포 방식** · `latest` 이미지·Actions 직접 배포·Argo CD 선언 동기화 병행.

---

## 5. Ingress·DNS·HTTPS

```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/aws/deploy.yaml
kubectl get svc -n ingress-nginx
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml
kubectl get pods -n cert-manager
kubectl apply -f deploy/k8s/platform/ingress
kubectl get ingress,certificate -n soldesk
```

Route 53의 `server`·`argo`·`prometheus`·`grafana` 호스트를 NLB로 연결. HTTP-01 발급 전 DNS·외부 HTTP 접근 확인. ClusterIssuer `my-issuer`·namespace별 Certificate로 TLS Secret 생성.

---

## 6. Argo CD

```powershell
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f deploy/k8s/platform/argocd
kubectl apply -f deploy/argocd/applications
kubectl apply -f deploy/argocd/root-app.yml
kubectl get applications -n argocd
```

TLS는 Ingress에서 종료하고 Argo 서버는 HTTP로 연결하도록 `argocd-cmd-params-cm`의 `server.insecure: "true"`를 설정하고 서버를 재시작. 초기 admin 비밀번호는 로컬에서 확인하고 로그인 후 변경.

| 제어 대상 | 관리 기준 |
| :--- | :--- |
| **`msa-root`** | 자식 Application 9개 |
| **Backend replicas** | HPA 관리·Argo CD 비교 및 동기화 제외 |
| **Frontend replicas** | Git의 replica 1 유지 |

[HPA·Argo CD 충돌 해결](TROUBLESHOOTING.md#4-hpa와-argo-cd의-replicas-제어-충돌).

---

## 7. HPA·Cluster Autoscaler

```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes
kubectl top pods -n soldesk
kubectl apply -f deploy/k8s/platform/hpa
kubectl apply -f deploy/k8s/platform/cluster-autoscaler/autoscaler.yml
kubectl get hpa -n soldesk
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=60
```

CA 적용 전 콘솔에서 EKS OIDC Provider, `autoscaling-pod-role`의 IRSA trust와 권한을 준비. ASG discovery 태그와 Terraform의 desired size 변경 무시 설정도 연결됨.

---

## 8. 모니터링·Grafana EBS

EBS CSI 역할 및 애드온을 먼저 준비하고 monitoring을 동기화. 상세 콘솔 순서는 [복습 노트의 EBS 절차](learning/STUDY-NOTES.md#12-grafana-ebs-영구-저장소-상세)에 있음.

```powershell
kubectl get csidriver ebs.csi.aws.com
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl apply -f deploy/k8s/platform/monitoring
kubectl get pvc -n monitoring
kubectl get pods,svc,certificate -n monitoring
```

1. Git 반영 → Argo CD Sync.
2. Grafana 초기 비밀번호 변경 → Prometheus 연결 → 대시보드 설정.
3. 설정 저장 → restart → 계정·데이터 소스·대시보드 유지 확인.

> **정상 상태** · EBS CSI 정상 · PVC `Bound` · Grafana Ready · 재시작 후 설정 유지.

---

## 9. CloudWatch·SNS 및 기능 검증

Terraform 적용 후 SNS 이메일의 구독 확인 링크를 직접 승인. SNS 테스트 메시지와 수동 CloudWatch ALARM 전환으로 알림 경로 확인. EKS control plane의 api·audit·authenticator 로그 스트림 확인.

웹에서 로그인·상품 조회·구매를 수행하고 Postman의 Bearer 인증 주문 및 Workbench SELECT로 재고·주문을 대조. 부하 테스트 종료 후 load Pod를 삭제하고 HPA 축소 확인. [실행 및 검증 결과](VALIDATION.md)에 기대값과 관찰값이 있음.

---

## 10. 종료 시 보존 대상

| 대상 | 보존·정리 전 확인 |
| :--- | :--- |
| **RDS** | 삭제 보호·최종 스냅샷 |
| **S3** | 객체·이전 버전 |
| **Grafana EBS** | PV Retain·PVC·필요한 데이터 |
| **CloudWatch** | 로그 그룹 `prevent_destroy` |
| **Terraform** | 로컬 State 보존 |

> **기억할 점** · PVC 유지와 Retain은 삭제 방지 설정. 백업과 복구는 별도.
