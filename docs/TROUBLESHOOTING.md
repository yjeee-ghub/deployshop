**DEPLOYSHOP · OPERATIONS**

# 문제 분석 및 해결

> 증상 → 원인 → 조치 → 확인 결과.

[문서 목록](README.md) · [구축 절차](SETUP.md) · [실행 결과](VALIDATION.md)

---

| 구분 | 문제 | 핵심 조치 |
| :--- | :--- | :--- |
| **저장·자원** | Grafana OOM·설정 소실 | 메모리 조정·EBS PVC |
| **배포 상태** | 신규 PVC 미반영 | hard refresh·최신 리비전 Sync |
| **인증서** | Certificate 반복 OutOfSync | 중복 생성 설정 제거 |
| **제어 충돌** | HPA·Argo CD replicas | 관리 필드 분리 |
| **스케줄링** | Prometheus Pending | 요청 자원·CA 확장 확인 |
| **설치** | CRD annotation 제한 | server-side apply |
| **DB 조회** | Workbench 1046 | 기본 DB 선택 |

---

## 1. Grafana OOMKilled와 설정 소실

**증상** · `restartCount: 1`·`OOMKilled`·Exit Code `137`. 메모리 limit 500Mi, `/var/lib/grafana` 영구 볼륨 미연결. 재시작 후 계정·데이터 소스·대시보드 소실.

**원인** · 메모리 부족으로 종료, 영구 저장소 미연결로 설정 소실. 메모리와 저장소 각각 조치 필요.

**조치**

| 조치 대상 | 변경 내용 |
| :--- | :--- |
| 메모리 | request 512Mi / limit 1Gi |
| 배포 전략 | `Recreate` |
| 파일 권한 | `fsGroup: 472` |
| 영구 저장 | `grafana-gp3`·`grafana-data` 5Gi → `/var/lib/grafana` |

**권한 연결** · EBS CSI 전용 IRSA 역할을 만들고 `AmazonEBSCSIDriverPolicyV2`를 연결. EKS Amazon EBS CSI Driver 애드온이 그 역할을 사용하도록 설정. Cluster Autoscaler 역할과는 별개.

> **확인 결과** · PVC `Bound`·Grafana 정상 배포. 초기 설정 저장 → `rollout restart` → 계정·데이터 소스·대시보드 유지 확인.

관련 파일: [배포](../deploy/k8s/platform/monitoring/grafana-depl_svc.yml), [스토리지](../deploy/k8s/platform/monitoring/grafana-storage.yml).

---

## 2. 새 PVC가 Git에 있는데 Argo CD에서 보이지 않음

**증상** · Git에 PVC 정의가 있지만 클러스터에 미생성.

**원인** · Argo CD가 최신 커밋 `3f8f591` 대신 이전 `2c7c12f` 참조.

**조치** · 원격 커밋 확인 → hard refresh로 캐시 갱신 → 최신 리비전 Sync.

```powershell
kubectl annotate application msa-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application msa-monitoring -n argocd
```

> **확인 결과** · PVC 생성·Bound, Grafana 정상 배포. PVC 미생성과 Pending 구분 필요. `WaitForFirstConsumer`의 Pod 배치 전 Pending은 정상 대기 가능.

---

## 3. monitoring Certificate가 계속 OutOfSync

**증상** · monitoring Certificate의 `duration: 2160h`·`renewBefore: 360h` 차이로 OutOfSync 반복.

**원인** · Git의 명시적 Certificate와 Ingress 자동 생성 설정이 같은 인증서를 중복 관리.

**조치** · Ingress의 `cert-manager.io/cluster-issuer` annotation 제거. 명시적 Certificate·TLS Secret 참조 유지.

> **확인 결과** · Application Healthy/Synced·HTTPS 정상 확인.

[Argo CD 캡처](images/evidence-03.png)는 수정 전 monitoring OutOfSync 1개가 보이는 시점.

---

## 4. HPA와 Argo CD의 replicas 제어 충돌

**증상** · HPA 확장 후 Pod 수가 Git의 고정 replicas로 복귀.

**원인** · HPA와 Argo CD selfHeal이 같은 replicas 필드를 제어.

**조치** · apigateway·member·product·ordering Application에 `/spec/replicas` `ignoreDifferences`·`RespectIgnoreDifferences=true` 적용. replicas는 HPA, 나머지 선언은 Argo CD가 관리.

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

> **확인 결과** · Product Pod `1 → 5 → 1` 확장·축소. HPA 미사용 Frontend는 수동 `2 → 1` self-heal 확인. [실행 및 검증 결과](VALIDATION.md) · [상품 Application](../deploy/argocd/applications/msa-product.yml).

---

## 5. Prometheus Pending / Insufficient cpu

**증상** · 모니터링 배포 중 Prometheus Pod Pending·`Insufficient cpu`.

**원인** · 기존 노드의 할당 가능한 CPU가 Pod request를 수용하기에 부족. 실제 CPU 사용률과 스케줄링 여유는 별개.

**조치** · Pod Events·`kubectl top nodes`·CA 로그로 자원·확장 상태 확인. CA의 노드 추가 후 재배치 확인.

> **확인 결과** · 노드 확장 후 Prometheus 배치. 상품 부하 테스트와 모니터링 설치 화면의 노드 수는 서로 다른 시점.

---

## 6. Argo CD 설치 시 큰 CRD annotation 문제

**증상** · Argo CD 설치 과정에서 대형 CRD의 annotation 크기 제한 문제.

**원인** · client-side apply가 리소스 구성을 last-applied annotation에 저장해 크기 제한에 도달 가능.

**조치** · server-side apply로 설치. `--force-conflicts`는 충돌 필드의 소유권 강제 변경 옵션.

```powershell
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> **확인 결과** · server-side apply로 설치 진행 후 Argo CD Application 관리·self-heal 확인.

---

## 7. Workbench Error 1046

**증상** · 연결 후 SELECT에서 `No database selected`.

**원인** · 기본 DB 미선택. 네트워크·인증 실패와 구분.

**조치** · `USE ordermsa;`로 DB 선택.

> **확인 결과** · 동일 SELECT 정상 수행.
