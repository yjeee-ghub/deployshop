# 구축 및 재현 절차

이 문서는 2026-10-16 실습의 최종 구성을 기준으로 순서를 정리한 것입니다. 명령은 사용자가 직접 실행하는 참고 자료이며 문서 작성 과정에서는 AWS·Kubernetes 명령을 실행하지 않았습니다. 계정·도메인·OIDC·서브넷·이미지 주소는 새 환경에 맞게 변경해야 합니다. `latest` 및 upstream `stable/latest` 설치 URL은 실습 당시 사용한 것으로, 재현 시 동일 버전을 보장하지 않습니다.

상세 설명은 [복습 노트](learning/STUDY-NOTES.md), 실제 결과는 [검증 문서](VALIDATION.md)를 참고합니다.

## 1. 사전 준비와 관리 범위

- AWS CLI, Terraform, kubectl, Docker Desktop, Git, JDK 17을 준비합니다.
- AWS 프로필은 `aws-yjeee`, 리전은 `ap-northeast-2`입니다.
- Terraform은 VPC·IAM·EKS·RDS·ECR·S3·CloudWatch/SNS를 관리합니다.
- Ingress NGINX, cert-manager, Argo CD, Metrics Server는 CLI로 설치했습니다.
- Route 53 레코드, OIDC Provider·IRSA 역할 및 EBS CSI 애드온은 콘솔로 연결했습니다. 저장소만으로 모든 콘솔 설정이 자동 재현되지는 않습니다.
- Terraform backend는 로컬 state입니다. state와 tfvars를 Git에 올리지 않습니다.

```powershell
Set-Location C:\yjeee-deployshop
aws sts get-caller-identity --profile aws-yjeee
terraform version
kubectl version --client
docker version
git --version
```

## 2. Terraform 적용

`terraform/variables.tf`의 필수 변수에 맞춰 로컬 `terraform.tfvars`를 작성합니다. DB 비밀번호 등 실제 값은 공개 예제에 넣지 않습니다. 실습은 클러스터 `my-cluster`, 노드 그룹 `my-nodes`, t3.large, min/desired 2, max 4를 사용했습니다.

```powershell
Set-Location C:\yjeee-deployshop\terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

일반 output에는 민감 출력이 숨겨지지만 `-raw`와 state에는 실제 값이 포함될 수 있습니다. 상품 이미지 전용 IAM 자격 증명은 터미널에 출력해서 캡처하지 않습니다.

RDS는 실습상 public subnet과 public access를 유지했습니다. 외부 Workbench 접근은 `workbench_allowed_cidr = "<접속_PC_공인_IP>/32"`로 제한합니다. 초기 검증 중 임시 전체 허용 후 최종 `/32`로 복구했습니다. EKS 접근용 보안 그룹 규칙은 별도로 유지합니다.

## 3. kubeconfig와 Secret

```powershell
aws eks update-kubeconfig --region ap-northeast-2 --name my-cluster --profile aws-yjeee
kubectl config current-context
kubectl get nodes
kubectl create namespace soldesk
```

`my-app-secrets`에 `DB_HOST`, `DB_PW`를, `aws-secret`에 상품 이미지 전용 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`를 넣습니다. 기존 Secret이 있으면 현재 키와 적용 범위를 먼저 확인합니다. 실제 값이 들어 있는 Secret YAML은 Git에서 제외합니다.

AWS 프로필용 자격 증명, GitHub Actions 인증, 상품 S3 전용 IAM 키, Pod용 IRSA는 서로 용도가 다릅니다. S3 전용 키는 Terraform의 `product_s3_access_key_id`·`product_s3_secret_access_key` 출력에서 로컬 변수로 받아 사용했습니다.

## 4. 이미지와 애플리케이션 배포

ECR 로그인은 [트러블슈팅](TROUBLESHOOTING.md)의 정상 동작한 native pipeline을 사용했습니다. backend Dockerfile은 JDK 17에서 bootJar를 빌드하고 JRE 17로 실행하며 frontend는 NGINX를 사용합니다.

GitHub Actions Repository Secrets에 `AWS_KEY`, `AWS_SECRET`을 등록했습니다. 해당 IAM principal이 EKS Access Entry를 통해 클러스터에 접근할 수 있어야 합니다. 워크플로는 변경 경로를 판단하여 이미지를 빌드·push하고 kubectl apply와 rollout restart를 수행합니다.

```powershell
kubectl apply -f deploy/k8s/apps/apigateway
kubectl apply -f deploy/k8s/apps/member
kubectl apply -f deploy/k8s/apps/product
kubectl apply -f deploy/k8s/apps/ordering
kubectl apply -f deploy/k8s/apps/frontend
kubectl get pods,svc -n soldesk
```

현재 이미지 태그는 `latest`입니다. Actions 직접 배포와 Argo CD 동기화가 함께 존재하므로 순수 GitOps 또는 커밋별 불변 이미지 배포라고 표현하지 않습니다.

## 5. Ingress·DNS·HTTPS

```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/aws/deploy.yaml
kubectl get svc -n ingress-nginx
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.0/cert-manager.yaml
kubectl get pods -n cert-manager
kubectl apply -f deploy/k8s/platform/ingress
kubectl get ingress,certificate -n soldesk
```

NGINX 서비스의 NLB DNS 이름으로 Route 53 CNAME을 연결합니다. `server`, `argo`, `prometheus`, `grafana`의 각 호스트를 설정합니다. HTTP-01 발급은 올바른 DNS와 외부 HTTP 접근이 준비돼야 합니다. ClusterIssuer `my-issuer`와 namespace별 Certificate가 TLS secret을 생성합니다.

## 6. Argo CD

```powershell
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f deploy/k8s/platform/argocd
kubectl apply -f deploy/argocd/applications
kubectl apply -f deploy/argocd/root-app.yml
kubectl get applications -n argocd
```

TLS는 Ingress에서 종료하고 Argo 서버는 HTTP로 연결하도록 `argocd-cmd-params-cm`의 `server.insecure: "true"`를 설정하고 서버를 재시작했습니다. 초기 admin 비밀번호는 로컬에서 확인하고 로그인 후 변경했습니다. 비밀번호 조회 출력은 공개하지 않습니다.

root `msa-root`가 9개 자식 Application을 관리합니다. HPA 대상 backend는 `/spec/replicas` ignore 및 `RespectIgnoreDifferences`로 HPA와 충돌을 피합니다. frontend는 replica 1을 Git이 관리합니다.

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

CA 적용 전 콘솔에서 EKS OIDC Provider, `autoscaling-pod-role`의 IRSA trust와 권한을 준비합니다. `eks:DescribeNodegroup`의 추가 권한이 필요했던 이력은 트러블슈팅 문서에 있습니다. ASG discovery 태그와 Terraform의 desired size 변경 무시 설정도 연결됩니다.

## 8. 모니터링·Grafana EBS

EBS CSI 역할 및 애드온을 먼저 준비하고 monitoring을 동기화합니다. 상세 콘솔 순서는 [복습 노트의 EBS 절차](learning/STUDY-NOTES.md#12-grafana-ebs-영구-저장소-상세)에 있습니다.

```powershell
kubectl get csidriver ebs.csi.aws.com
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl apply -f deploy/k8s/platform/monitoring
kubectl get pvc -n monitoring
kubectl get pods,svc,certificate -n monitoring
```

Argo CD가 관리하는 이후 변경은 Git 반영 후 Sync로 적용했습니다. Grafana 초기 로그인 후 비밀번호 변경, Prometheus 데이터 소스 연결, JSON Import를 수행합니다. 계정·대시보드를 저장하고 restart 후 유지 여부를 확인합니다.

## 9. CloudWatch·SNS 및 기능 검증

Terraform 적용 후 SNS 이메일의 구독 확인 링크를 직접 승인합니다. SNS 테스트 메시지와 수동 CloudWatch ALARM 전환으로 알림 경로를 확인했습니다. EKS control plane의 api·audit·authenticator 로그 스트림을 확인했습니다.

웹에서 로그인·상품 조회·구매를 수행하고 Postman의 Bearer 인증 주문 및 Workbench SELECT로 재고·주문을 대조합니다. 부하 테스트 종료 후 load Pod를 삭제하고 HPA 축소를 확인합니다. [검증 문서](VALIDATION.md)에 기대값과 관찰값이 있습니다.

## 10. 종료 시 보존 대상

이 문서는 자동 삭제를 수행하지 않습니다. 종료 전 RDS 최종 스냅샷, S3 객체, Grafana EBS와 로컬 Terraform state를 확인합니다. RDS 삭제 보호, CloudWatch log group의 prevent_destroy, S3 versioning 및 Grafana PV Retain 때문에 일부 리소스는 별도 결정과 정리가 필요합니다. PVC 유지 설정은 백업을 대신하지 않습니다.
