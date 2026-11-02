**DEPLOYSHOP · SETUP**

# 구축 및 재현 절차

> 인프라 → 클러스터 → 배포 → 관측 → 기능 검증.

---

**시작 전** · 계정·도메인·OIDC·서브넷·이미지 주소를 환경에 맞게 변경합니다. `stable/latest` 설치 URL은 버전이 고정되어 있지 않습니다.

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

`terraform/variables.tf`를 기준으로 로컬 `terraform.tfvars`를 작성합니다.

| 항목 | 구성값 |
| :--- | :--- |
| **클러스터 / 노드 그룹** | `my-cluster` / `my-nodes` |
| **인스턴스** | `t3.large` |
| **노드 수** | min 2 · desired 2 · max 4 |

> **인증값 관리** · tfvars·State·실제 비밀번호는 Git 추적에서 제외합니다. `sensitive`는 일반 출력만 가리며 State 자체를 암호화하지 않습니다.

```powershell
Set-Location C:\yjeee-deployshop\terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

> **DB 접근** · Public RDS를 유지하며 `workbench_allowed_cidr`를 PC 공인 IP `/32`로 제한합니다. EKS 보안 그룹 규칙은 별도로 유지합니다.

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

기존 Secret의 키와 적용 범위를 확인합니다. 실제 값이 들어 있는 YAML은 Git 추적에서 제외합니다.

AWS 프로필·Actions 인증·상품 S3 키·Pod IRSA는 용도가 다릅니다. S3 키는 Terraform의 `product_s3_access_key_id`·`product_s3_secret_access_key` 출력에서 로컬 변수로 받아 사용합니다.

---

## 4. 이미지와 애플리케이션 배포

| 대상 | 빌드·실행 |
| :--- | :--- |
| **Backend** | JDK 17 bootJar → JRE 17 |
| **Frontend** | NGINX 정적 파일 제공 |

Actions Secrets에 인증값을 등록하고 EKS Access Entry·접근 정책을 연결합니다. 변경 경로 감지 후 이미지 빌드·push와 kubectl apply·rollout restart를 수행합니다.

```powershell
kubectl apply -f deploy/k8s/apps/apigateway
kubectl apply -f deploy/k8s/apps/member
kubectl apply -f deploy/k8s/apps/product
kubectl apply -f deploy/k8s/apps/ordering
kubectl apply -f deploy/k8s/apps/frontend
kubectl get pods,svc -n soldesk
```

> **배포 방식** · `latest` 이미지를 사용하며 Actions 직접 배포와 Argo CD 선언 동기화를 병행합니다.

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

Route 53 호스트를 NLB로 연결합니다. DNS·외부 HTTP 접근을 확인한 뒤 ClusterIssuer `my-issuer`와 namespace별 Certificate로 TLS Secret을 생성합니다.

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

TLS는 Ingress에서 종료합니다. `server.insecure: "true"`로 Argo 서버에 HTTP를 전달하고, 초기 admin 비밀번호를 변경합니다.

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

CA 적용 전 OIDC Provider와 `autoscaling-pod-role`의 IRSA trust·권한을 준비합니다. ASG discovery 태그와 Terraform의 desired size 변경 무시 설정도 확인합니다.

---

## 8. 모니터링·Grafana EBS

EBS CSI 역할·애드온을 준비한 뒤 monitoring을 동기화합니다. 상세 절차는 [복습 노트의 EBS 절차](learning/STUDY-NOTES.md#12-grafana-ebs-영구-저장소-상세)를 참고합니다.

```powershell
kubectl get csidriver ebs.csi.aws.com
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl apply -f deploy/k8s/platform/monitoring
kubectl get pvc -n monitoring
kubectl get pods,svc,certificate -n monitoring
```

1. Git 반영 후 Argo CD로 Sync합니다.
2. 초기 비밀번호를 변경하고 Prometheus 데이터 소스와 대시보드를 설정합니다.
3. 설정을 저장하고 재시작한 뒤 계정·데이터 소스·대시보드 유지를 확인합니다.

> **정상 상태** · EBS CSI 정상 · PVC `Bound` · Grafana Ready · 재시작 후 설정 유지.

---

## 9. CloudWatch·SNS 및 기능 검증

Terraform 적용 후 SNS 이메일 구독을 승인합니다. 테스트 메시지와 수동 ALARM 전환으로 전달 경로를 확인하고 EKS 제어 영역 로그 스트림을 조회합니다.

웹 구매·Postman 주문·Workbench SELECT로 재고와 주문을 대조합니다. 부하 Pod 삭제 후 HPA 축소도 확인합니다. 관찰값은 [실행 및 검증 결과](VALIDATION.md)에 정리했습니다.

---

## 10. 종료 시 보존 대상

| 대상 | 보존·정리 전 확인 |
| :--- | :--- |
| **RDS** | 삭제 보호·최종 스냅샷 |
| **S3** | 객체·이전 버전 |
| **Grafana EBS** | PV Retain·PVC·필요한 데이터 |
| **CloudWatch** | 로그 그룹 `prevent_destroy` |
| **Terraform** | 로컬 State 보존 |

> **기억할 점** · PVC 유지와 Retain은 삭제 방지 설정입니다. 백업과 복구는 별도로 준비해야 합니다.
