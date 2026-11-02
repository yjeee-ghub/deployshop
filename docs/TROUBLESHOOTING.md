# 문제 분석 및 해결 기록

증상 → 원인 → 조치 → 확인 결과. [실행 및 검증 결과](VALIDATION.md).

## 1. Grafana OOMKilled와 설정 소실

**증상:** `restartCount: 1`·`OOMKilled`·Exit Code `137`. 메모리 limit 500Mi, `/var/lib/grafana` 영구 볼륨 미연결. 재시작 후 계정·데이터 소스·대시보드 소실.

**원인:** 메모리 부족으로 종료, 영구 저장소 미연결로 설정 소실. 메모리와 저장소 각각 조치 필요.

**변경:** 메모리 request 512Mi / limit 1Gi, 단일 EBS 사용을 고려한 `Recreate`, `fsGroup: 472`, `/var/lib/grafana` PVC 마운트를 적용. `grafana-gp3` StorageClass와 `grafana-data` 5Gi PVC를 추가.

**AWS 연결:** EBS CSI 전용 IRSA 역할을 만들고 `AmazonEBSCSIDriverPolicyV2`를 연결. EKS Amazon EBS CSI Driver 애드온이 그 역할을 사용하도록 설정. Cluster Autoscaler 역할과는 별개.

**확인:** PVC `Bound`·Grafana 정상 배포. 초기 설정 저장 → `rollout restart` → 계정·데이터 소스·대시보드 유지 확인.

관련 파일: [배포](../deploy/k8s/platform/monitoring/grafana-depl_svc.yml), [스토리지](../deploy/k8s/platform/monitoring/grafana-storage.yml).

## 2. 새 PVC가 Git에 있는데 Argo CD에서 보이지 않음

**증상:** 새 커밋 `3f8f591`에 스토리지를 추가했지만 Argo CD는 이전 `2c7c12f`를 보고 있음.

**해결:** 원격 커밋 확인 → hard refresh로 캐시 갱신 → 최신 리비전 Sync.

```powershell
kubectl annotate application msa-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application msa-monitoring -n argocd
```

**확인:** PVC 생성·Bound, Grafana 정상 배포. PVC 미생성과 Pending 구분 필요. `WaitForFirstConsumer`의 Pod 배치 전 Pending은 정상 대기 가능.

## 3. monitoring Certificate가 계속 OutOfSync

**증상:** Git의 명시적 Certificate와 Ingress의 cert-manager 자동 인증서 생성 설정이 같은 인증서를 관리. `duration: 2160h`, `renewBefore: 360h` 차이가 반복됨.

**해결:** monitoring Ingress의 `cert-manager.io/cluster-issuer` annotation 한 줄을 제거하고 명시적 Certificate와 TLS secret 참조를 유지. 반영 후 Application Healthy/Synced·HTTPS 정상 확인.

[Argo CD 캡처](images/evidence-03.png)는 수정 전 monitoring OutOfSync 1개가 보이는 시점.

## 4. HPA와 Argo CD의 replicas 제어 충돌

**증상·원인:** HPA의 자동 확장 후 Argo CD selfHeal이 Git의 고정 replicas를 재적용. 같은 필드를 두 컨트롤러가 관리해 Pod 수 복귀 발생.

**해결:** apigateway·member·product·ordering Application에 `/spec/replicas` `ignoreDifferences`·`RespectIgnoreDifferences=true` 적용. replicas는 HPA, 나머지 선언은 Argo CD가 관리.

상품 서비스의 적용 예시.

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    name: product-depl
    namespace: soldesk
    jsonPointers:
      - /spec/replicas
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - RespectIgnoreDifferences=true
```

**확인:** Product Pod `1 → 5 → 1` 확장·축소. HPA 미사용 Frontend는 수동 `2 → 1` self-heal 확인. [실행 및 검증 결과](VALIDATION.md) · [상품 Application](../deploy/argocd/applications/msa-product.yml).

## 5. Prometheus Pending / Insufficient cpu

**증상:** 모니터링 배포 중 Pod의 CPU request를 수용할 노드 여유가 부족.

**확인:** `kubectl describe pod`의 Events, `kubectl top nodes`, CA 로그를 함께 확인. CA가 노드를 늘린 후 배치됨. HPA 상품 부하 테스트의 2→3노드 변화와 모니터링 설치 시점의 4노드 화면은 서로 다른 시점.

## 6. Argo CD 설치 시 큰 CRD annotation 문제

대형 CRD를 일반 client-side apply로 설치할 때 annotation 크기 제한에 걸릴 수 있어 server-side apply로 설치. `--force-conflicts`는 충돌 필드의 소유권 강제 변경 옵션.

```powershell
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 7. Workbench Error 1046

연결은 됐으나 기본 DB를 선택하지 않아 `No database selected`가 발생. `USE ordermsa;` 실행 후 동일 SELECT가 정상 수행됨. 네트워크·인증 실패와 구분.
