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

**증상** · `restartCount: 1`·`OOMKilled`·Exit Code `137`을 확인했습니다. 메모리 limit은 500Mi였으며 영구 볼륨이 없어 재시작 후 계정·데이터 소스·대시보드가 소실되었습니다.

**원인** · 메모리 부족으로 컨테이너가 종료되었고, 영구 저장소가 없어 설정이 소실되었습니다. 메모리와 저장소를 각각 조치해야 합니다.

**조치**

| 조치 대상 | 변경 내용 |
| :--- | :--- |
| 메모리 | request 512Mi / limit 1Gi |
| 배포 전략 | `Recreate` |
| 파일 권한 | `fsGroup: 472` |
| 영구 저장 | `grafana-gp3`·`grafana-data` 5Gi → `/var/lib/grafana` |

**권한 연결** · EBS CSI 전용 IRSA 역할에 `AmazonEBSCSIDriverPolicyV2`를 연결하고 EKS 애드온이 사용하도록 설정했습니다. CA 역할과는 별도로 구성했습니다.

> **확인 결과** · PVC `Bound`와 Grafana 배포를 확인했습니다. 설정 저장 후 `rollout restart`를 수행해 계정·데이터 소스·대시보드 유지를 확인했습니다.

관련 파일: [배포](../deploy/k8s/platform/monitoring/grafana-depl_svc.yml), [스토리지](../deploy/k8s/platform/monitoring/grafana-storage.yml).

---

## 2. 새 PVC가 Git에 있는데 Argo CD에서 보이지 않음

**증상** · Git에 PVC 정의가 있지만 클러스터에는 생성되지 않았습니다.

**원인** · Argo CD가 최신 커밋 `3f8f591` 대신 이전 커밋 `2c7c12f`를 참조하고 있었습니다.

**조치** · 원격 커밋을 확인하고 hard refresh로 캐시를 갱신한 뒤 최신 리비전을 Sync했습니다.

```powershell
kubectl annotate application msa-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application msa-monitoring -n argocd
```

> **확인 결과** · PVC 생성·Bound와 Grafana 배포를 확인했습니다. PVC 미생성과 Pending은 구분해야 하며, `WaitForFirstConsumer`에서는 Pod 배치 전 Pending이 정상 대기일 수 있습니다.

---

## 3. monitoring Certificate가 계속 OutOfSync

**증상** · monitoring Certificate의 `duration: 2160h`·`renewBefore: 360h` 차이로 OutOfSync가 반복되었습니다.

**원인** · Git의 명시적 Certificate와 Ingress 자동 생성 설정이 같은 인증서를 중복 관리했습니다.

**조치** · Ingress의 issuer annotation을 제거하고 명시적 Certificate와 TLS Secret 참조를 유지했습니다.

> **확인 결과** · Application Healthy/Synced와 HTTPS 정상 접속을 확인했습니다.

[Argo CD 캡처](images/evidence-03.png)는 수정 전 monitoring OutOfSync 상태입니다.

---

## 4. HPA와 Argo CD의 replicas 제어 충돌

**증상** · HPA 확장 후 Pod 수가 Git의 고정 replicas로 되돌아갔습니다.

**원인** · HPA와 Argo CD selfHeal이 같은 replicas 필드를 제어했습니다.

**조치** · Backend Application에 `/spec/replicas` 제외와 `RespectIgnoreDifferences=true`를 적용했습니다. Pod 수는 HPA가, 나머지 선언은 Argo CD가 관리하도록 분리했습니다.

상품 서비스에 적용한 설정입니다.

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

> **확인 결과** · Product Pod `1 → 5 → 1` 확장·축소와 Frontend 수동 변경 `2 → 1` self-heal을 확인했습니다. [실행 및 검증 결과](VALIDATION.md) · [상품 Application](../deploy/argocd/applications/msa-product.yml).

---

## 5. Prometheus Pending / Insufficient cpu

**증상** · Prometheus Pod가 Pending 상태였으며 `Insufficient cpu`가 발생했습니다.

**원인** · 노드의 할당 가능한 CPU가 Pod request보다 부족했습니다. 실제 CPU 사용률과 스케줄링 여유는 별개입니다.

**조치** · Pod Events·노드 지표·CA 로그를 대조하고 노드 추가 후 배치를 확인했습니다.

> **확인 결과** · 노드 확장 후 Prometheus가 배치되었습니다. 상품 부하 테스트와 모니터링 설치 화면의 노드 수는 서로 다른 시점입니다.

---

## 6. Argo CD 설치 시 큰 CRD annotation 문제

**증상** · Argo CD 설치 과정에서 대형 CRD의 annotation 크기 제한 문제가 발생했습니다.

**원인** · client-side apply는 구성을 last-applied annotation에 저장하므로 대형 리소스에서 크기 제한에 도달할 수 있습니다.

**조치** · server-side apply로 설치했습니다. `--force-conflicts`는 충돌 필드의 소유권을 강제로 변경하는 옵션입니다.

```powershell
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> **확인 결과** · 설치 후 Argo CD Application 관리와 self-heal을 확인했습니다.

---

## 7. Workbench Error 1046

**증상** · DB 연결 후 SELECT 실행 시 `No database selected`가 발생했습니다.

**원인** · 기본 DB를 선택하지 않았습니다. 네트워크·인증 실패와는 별개입니다.

**조치** · `USE ordermsa;`로 DB를 선택했습니다.

> **확인 결과** · 동일 SELECT가 정상 수행되었습니다.
