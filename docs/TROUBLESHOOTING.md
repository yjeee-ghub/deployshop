# 트러블슈팅 기록

실습 당시 관찰한 증상과 해결 과정을 기록했습니다. 해결 후 확인을 직접 캡처한 항목과 사용자가 실행 결과를 확인한 항목은 [검증 결과](VALIDATION.md)에서 구분합니다.

## 1. Grafana OOMKilled와 설정 소실

**증상:** 재시작 횟수 1, 마지막 종료 사유 `OOMKilled`, Exit Code `137`이 확인됐습니다. 기존 설정에서 메모리 제한은 500Mi였고 `/var/lib/grafana`에 영구 볼륨이 없었습니다. 이후 계정·데이터 소스·대시보드를 다시 설정해야 했습니다.

**분석:** OOM은 메모리 문제이며, 설정 소실은 저장소 문제입니다. 메모리 증설만으로 저장소 소실을 해결할 수는 없습니다.

**변경:** 메모리 request 512Mi / limit 1Gi, 단일 EBS 사용을 고려한 `Recreate`, `fsGroup: 472`, `/var/lib/grafana` PVC 마운트를 적용했습니다. `grafana-gp3` StorageClass와 `grafana-data` 5Gi PVC를 추가했습니다.

**AWS 연결:** EBS CSI 전용 IRSA 역할을 만들고 `AmazonEBSCSIDriverPolicyV2`를 연결했습니다. EKS Amazon EBS CSI Driver 애드온이 그 역할을 사용하도록 설정했습니다. Cluster Autoscaler 역할과는 별개입니다.

**확인:** 사용자가 PVC `Bound`, Grafana 정상 배포를 확인하고 초기 설정을 다시 저장한 뒤 `rollout restart`를 수행했습니다. 재시작 후 계정·데이터 소스·대시보드가 유지됐다고 확인했습니다. OOM 캡처는 제공됐지만 재시작 전후 유지 비교 캡처는 제공되지 않았습니다.

관련 파일: [배포](../deploy/k8s/platform/monitoring/grafana-depl_svc.yml), [스토리지](../deploy/k8s/platform/monitoring/grafana-storage.yml).

## 2. 새 PVC가 Git에 있는데 Argo CD에서 보이지 않음

**증상:** 새 커밋 `3f8f591`에 스토리지를 추가했지만 Argo CD는 이전 `2c7c12f`를 보고 있었습니다.

**해결:** 원격 커밋을 확인한 뒤 캐시를 강제로 새로 읽도록 했습니다.

```powershell
kubectl annotate application msa-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application msa-monitoring -n argocd
```

그 후 최신 리비전으로 Sync하고 PVC 생성·Bound와 Grafana 배포를 확인했습니다. `PVC가 없음`은 리소스 미생성 문제이고 `PVC Pending`은 생성 후 바인딩 대기 문제이므로 구분해야 합니다. `WaitForFirstConsumer`에서는 Pod 배치 전 Pending 자체가 반드시 장애는 아닙니다.

## 3. monitoring Certificate가 계속 OutOfSync

**증상:** Git의 명시적 Certificate와 Ingress의 cert-manager 자동 인증서 생성 설정이 같은 인증서를 관리했습니다. `duration: 2160h`, `renewBefore: 360h` 차이가 반복됐습니다.

**해결:** monitoring Ingress의 `cert-manager.io/cluster-issuer` annotation 한 줄을 제거하고 명시적 Certificate와 TLS secret 참조를 유지했습니다. 사용자는 반영 후 전체 Application Healthy/Synced와 HTTPS 정상 접속을 확인했습니다.

[Argo CD 캡처](images/evidence-03.png)는 수정 전 monitoring OutOfSync 1개가 보이는 시점입니다. 최종 전체 Synced 증거로 사용하지 않습니다.

## 4. Cluster Autoscaler의 eks:DescribeNodegroup 403

**증상:** EC2·Auto Scaling 권한 연결 후에도 Managed Node Group 조회에서 권한 오류가 발생했습니다.

**해결:** 역할에 다음 인라인 권한을 추가했습니다.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "eks:DescribeNodegroup",
    "Resource": "arn:aws:eks:ap-northeast-2:193644343848:nodegroup/my-cluster/my-nodes/*"
  }]
}
```

서비스 계정의 IRSA annotation, OIDC trust의 `aud`·`sub`도 함께 확인했습니다. 재시작 직후 기존 leader Lease가 만료되기 전 발생한 acquire 실패는 약 1분 후 정상 루프로 전환됐습니다. Lease를 삭제하지 않았습니다.

수업 정책인 EC2FullAccess·AutoScalingFullAccess 등은 범위가 넓습니다. 이 프로젝트는 해당 실습 구성을 재현했으며 최소 권한 설계 완료를 주장하지 않습니다.

## 5. PowerShell ECR 로그인 400

**증상:** `get-login-password | docker login`과 PowerShell 변수 전달 방식에서 400이 발생했습니다.

**해결:** 동일 자격 증명으로 `cmd /c`의 native pipeline을 사용했을 때 성공했습니다. PowerShell의 문자열·개행 처리 영향으로 추정하지만 정확한 원인을 별도 분석으로 확정한 것은 아닙니다.

```powershell
cmd /c "aws ecr get-login-password --region ap-northeast-2 --profile aws-yjeee | docker login --username AWS --password-stdin 193644343848.dkr.ecr.ap-northeast-2.amazonaws.com"
```

정상 결과는 `Login Succeeded`입니다. ECR 로그인 토큰과 IAM Secret은 문서에 남기지 않습니다.

## 6. Prometheus Pending / Insufficient cpu

**증상:** 모니터링 배포 중 Pod의 CPU request를 수용할 노드 여유가 부족했습니다.

**확인:** `kubectl describe pod`의 Events, `kubectl top nodes`, CA 로그를 함께 확인했습니다. CA가 노드를 늘린 후 배치됐습니다. HPA 상품 부하 테스트의 2→3노드 변화와 모니터링 설치 시점의 4노드 화면은 서로 다른 시점입니다.

## 7. Argo CD 설치 시 큰 CRD annotation 문제

대형 CRD를 일반 client-side apply로 설치할 때 annotation 크기 제한에 걸릴 수 있어 server-side apply로 설치했습니다. `--force-conflicts`는 필드 소유권을 덮어쓸 수 있으므로 이 실습의 초기 Argo CD 설치 명령으로만 기록합니다.

```powershell
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 8. Workbench Error 1046

연결은 됐으나 기본 DB를 선택하지 않아 `No database selected`가 발생했습니다. `USE ordermsa;` 실행 후 동일 SELECT가 정상 수행됐습니다. 네트워크·인증 실패와 구분했습니다.

## 9. 재고 부족 400

재고 7개 상품에 8개 주문을 요청했을 때 400과 `재고 부족` 응답을 받았습니다. 이 응답은 의도한 거절 결과입니다. 재고 7개와 기존 주문 2건이 유지됐음을 별도로 조회했습니다. 이 단일 순차 테스트만으로 동시 주문 경쟁 조건이나 분산 트랜잭션 원자성을 보장하지는 않습니다.
