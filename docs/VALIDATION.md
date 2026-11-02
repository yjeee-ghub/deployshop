# 실행 및 검증 결과

**실행·변경 내용 → 강조된 검증 캡처 → 확인 결과** 순서로 구성했습니다. 모든 캡처는 이 문서에서 바로 볼 수 있습니다.

검증 기준일: **2026-10-16 (KST)**. 실행은 사용자가 직접 수행했습니다. 새 AWS 테스트를 실행한 문서가 아니라 당시 실행 기록을 정리한 자료입니다. 빨간 네모와 번호는 확인할 위치를 표시하며, 원본 글자·수치를 유지한 채 관련 영역을 발췌했습니다. 캡처가 없는 최종 결과는 **사용자 실행 보고**로 구분합니다.

| 사례 | 검증 흐름 |
|---|---|
| 01. 이미지 빌드·배포 | 인증값 준비 → Workflow 실행 → 작업 성공 |
| 02. Git 선언 상태 복구 | replicas 수동 변경 → Git 값으로 복귀 |
| 03. 자동 확장·축소 | 부하 생성 → Pod·노드 확장 → 부하 제거 → Pod 축소 |
| 04. 웹·API·DB 대조 | 초기 상태 → 주문 → 재고·주문 저장 → 초과 주문 거절 |
| 05. 메트릭 수집·시각화 | Targets UP → up 쿼리 → Grafana 패널 |
| 06. Grafana 문제 해결 | OOM 진단 → 메모리·저장소 조정 → 보존 재확인 |
| 07. 경보·로그·알림 | 경보 설정 → 수동 상태 전환 → 메일·이력 확인 |
| 08. DB 접근 범위 제한 | PC /32 적용 → 보안 그룹 확인 → DB 재조회 |

## 01. 이미지 빌드·배포

### AWS 인증값 준비와 Workflow 성공

**실행·확인 내용**

Actions에 AWS 인증값을 등록하고, 변경 서비스의 이미지 빌드·ECR push·Kubernetes 배포를 수행하는 Workflow를 실행했습니다. 캡처는 초기 전체 서비스 업로드 커밋 `2c7c12f`의 실행 결과입니다.

![검증 캡처 33 — github1.png](images/annotated/evidence-33.png)

![검증 캡처 34 — github2.png](images/annotated/evidence-34.png)

**캡처 확인 포인트**

- 인증값 등록 화면에서 `AWS_KEY`·`AWS_SECRET`의 존재를 확인합니다. 실제 키 값은 표시되지 않습니다.
- Workflow의 `Status: Success`와 `build-and-deploy` 작업의 성공 표시를 확인합니다.

**검증 결과:** Actions에 정의한 작업이 성공했습니다. 이후 서비스별 rollout과 쇼핑몰 조회 정상은 사용자 실행 보고로 확인했습니다. 실제 주문·DB 결과는 04번에서 별도로 대조합니다.

## 02. Git 선언 상태 복구

### 수동 변경 후 Frontend replicas 복귀

**실행·확인 내용**

Frontend의 Pod 수를 수동으로 2개로 바꾸고 Deployment 변화를 관찰했습니다.

![검증 캡처 01 — ArgoCD replicas 복구 실습1.png](images/annotated/evidence-01.png)

![검증 캡처 02 — ArgoCD replicas 복구 실습2.png](images/annotated/evidence-02.png)

**캡처 확인 포인트**

- 수동 scale 명령의 `--replicas=2`와 `scaled` 응답을 확인합니다.
- watch 출력과 최종 Deployment 조회에서 `READY 1/1`로 복귀한 값을 확인합니다.

**검증 결과:** 수동 변경한 Pod 수가 Git에 선언된 1개로 복구됐습니다.

### Argo CD 중간 상태 구분

**실행·확인 내용**

Application 화면에서 앱별 상태를 확인했습니다. 이 캡처는 monitoring 인증서 충돌 해결 전 시점입니다.

![검증 캡처 03 — ArgoCD.png](images/annotated/evidence-03.png)

**캡처 확인 포인트**

- `msa-monitoring`은 `Healthy`이면서 `OutOfSync`입니다.
- 이 화면을 최종 전체 Synced 증거로 사용하지 않습니다.

**검증 결과:** 앱 health와 선언 일치 상태가 서로 다름을 확인했습니다. 인증서 수정 후 전체 정상은 별도 사용자 보고입니다.

## 03. 부하에 따른 Pod·노드 확장과 Pod 축소

### CA 권한 준비와 부하에 따른 확장

**실행·확인 내용**

CA가 노드 용량을 조절하도록 역할을 연결하고, `http://product-service/product/list`를 반복 조회하는 BusyBox 부하 루프 8개를 실행했습니다. Product HPA는 CPU 목표 30%, 최소 1·최대 5개입니다.

![검증 캡처 04 — Cluster Autoscaler가 ASG의 노드 수를 조절할 수 있도록 AWS 권한을 연결.png](images/annotated/evidence-04.png)

![검증 캡처 05 — HPA 확장_부하테스트1.png](images/annotated/evidence-05.png)

**캡처 확인 포인트**

- 역할 화면의 `autoscaling-pod-role`과 실습 당시 연결한 정책을 확인합니다. 정책 연결 자체가 확장 성공의 증거는 아닙니다.
- HPA의 `REPLICAS`가 `1 → 2 → 4 → 5`로 증가하는 부분을 확인합니다.
- 상품 Pod 5개의 배치와 Ready 노드 3개를 확인합니다.

**검증 결과:** 실행 기록상 노드가 2개에서 3개로 증가했고, 확장 시점 캡처에서 노드 3개와 상품 Pod 5개를 확인했습니다.

### 부하 제거 후 Pod 자동 축소

**실행·확인 내용**

상품 조회 부하를 발생시키던 `product-load` Pod를 삭제하고 HPA 변화를 관찰했습니다.

![검증 캡처 06 — HPA 확장_부하테스트2.png](images/annotated/evidence-06.png)

**캡처 확인 포인트**

- 부하 Pod 삭제 명령과 삭제 완료 응답을 확인합니다.
- CPU 사용률이 `40% → 32% → 5% → 0%`로 감소합니다.
- `REPLICAS`가 `5 → 1`로 감소합니다.

**검증 결과:** 부하 종료 후 상품 Pod가 최소 설정인 1개로 줄었습니다. 노드 3→2 축소는 사용자 실행 보고이며, 위 화면은 노드 축소 목록이 아닙니다. 처리량 개선율·SLA는 측정하지 않았습니다. CA는 단순 노드 CPU 사용률이 아니라 requests와 스케줄링 불가능한 Pod 등을 고려합니다. 모니터링 설치 시 Prometheus requests 부족으로 노드가 추가된 이벤트는 이 부하 테스트와 별도입니다.

## 04. 웹·API 주문과 DB 결과 대조

**검증 기준:** 최종 재고·주문 대조는 **상품 ID 2·회원 ID 2**로 수행했습니다. 앞부분의 상품 ID 1은 별도 초기 기능 확인입니다. 두 결과를 한 상품의 연속 검증으로 섞지 않습니다.

### 주문 전후 비교 기준

| 순서 | 동작 | HTTP / 화면 | 재고 | 해당 상품 주문 |
|---|---|---|---:|---|
| 1 | 신규 상품 등록 | 상품·이미지 표시 | 10 | 없음 |
| 2 | 웹 구매 1회 | 주문 완료 알림 | 9 | ID 3, quantity 1, ORDERED |
| 3 | API 구매 수량 2 | 201, 본문 4 | 7 | ID 4 추가, quantity 2 |
| 4 | API 구매 수량 8 | 400, 재고 부족 | 7 | ID 3·4 유지 |


### 웹 로그인과 로그인 응답

**실행·확인 내용**

브라우저에서 로그인하고 API 로그인 응답도 확인했습니다.

![검증 캡처 44 — shop_image3.png](images/annotated/evidence-44.png)

![검증 캡처 17 — Postman_Workbench_test5.png](images/annotated/evidence-17.png)

**캡처 확인 포인트**

- 웹 화면의 로그인 성공 안내를 확인합니다.
- 두 번째 이미지는 이미 AI로 가림 편집된 로그인 응답 설명용 사본입니다. 원본 그대로의 검증 증거로 사용하지 않습니다.

**검증 결과:** 웹 로그인 상태를 확인했습니다. 로그인 성공만으로 주문 저장·재고 차감 성공까지 판단하지 않습니다.

### 상품 이미지와 초기 상품 ID 1의 구매

**실행·확인 내용**

상품 이미지의 S3 저장과 웹 표시를 확인하고, 초기 상품 ID 1을 웹에서 구매했습니다.

![검증 캡처 45 — shop_s3_object.png](images/annotated/evidence-45.png)

![검증 캡처 43 — shop_image1.png](images/annotated/evidence-43.png)

![검증 캡처 41 — shop_imag2.png](images/annotated/evidence-41.png)

![검증 캡처 42 — shop_imag2_1.png](images/annotated/evidence-42.png)

**캡처 확인 포인트**

- S3의 `products/` 경로와 이미지 객체를 확인합니다.
- 상품 ID 1의 구매 전 재고 9, 주문 완료 안내, 이후 상세 재고 8을 확인합니다.
- 이 초기 상품은 아래 최종 검증 상품 ID 2와 구분합니다.

**검증 결과:** 상품 이미지 저장·표시와 초기 웹 구매를 확인했습니다. 파일 전체 해시를 비교한 검증은 아닙니다.

### 최종 검증 상품 ID 2의 초기 상태

**실행·확인 내용**

최종 검증용 상품을 재고 10개로 준비하고 웹과 DB에서 같은 상품을 확인했습니다.

![검증 캡처 07 — Postman_Workbench_test.png](images/annotated/evidence-07.png)

![검증 캡처 08 — Postman_Workbench_test1.png](images/annotated/evidence-08.png)

**캡처 확인 포인트**

- 웹의 `최종 검증 상품`과 재고 10을 확인합니다.
- DB 조회 조건 `product_id=2`와 결과 행의 `stock_quantity=10`을 확인합니다.

**검증 결과:** 같은 상품의 초기 재고 10을 확인하고 이후 주문 결과의 비교 기준으로 삼았습니다.

**DB 대조에 사용한 읽기 조회**

```sql
USE ordermsa;
SET @product_id = 2;
SELECT id, name, price, stock_quantity, image_url
FROM product WHERE id = @product_id;
SELECT id, member_id, product_id, quantity, order_status
FROM ordering WHERE product_id = @product_id ORDER BY id;
```

### 웹에서 1개 구매 후 DB·API 대조

**실행·확인 내용**

상품 ID 2를 웹에서 1개 구매한 뒤, DB와 상품 API를 다시 조회했습니다.

![검증 캡처 14 — Postman_Workbench_test2.png](images/annotated/evidence-14.png)

![검증 캡처 15 — Postman_Workbench_test3.png](images/annotated/evidence-15.png)

![검증 캡처 16 — Postman_Workbench_test4.png](images/annotated/evidence-16.png)

![검증 캡처 18 — Postman_Workbench_test6.png](images/annotated/evidence-18.png)

**캡처 확인 포인트**

- 웹 URL의 상품 ID 2와 주문 완료 안내를 확인합니다. 안내 뒤 화면의 이전 재고 숫자는 최종 결과로 사용하지 않습니다.
- DB 재고 9와 주문 ID 3·수량 1·ORDERED를 확인합니다.
- 상품 API 재조회 응답의 `stockQuantity: 9`를 확인합니다.

**검증 결과:** 웹 구매 1개 후 재고가 10→9로 감소하고 주문 1건이 저장됐습니다.

### API로 2개 주문 후 재고·주문 대조

**실행·확인 내용**

같은 상품 ID 2에 수량 2로 주문 API를 호출하고 DB·웹을 재조회했습니다.

![검증 캡처 19 — Postman_Workbench_test7.png](images/annotated/evidence-19.png)

![검증 캡처 20 — Postman_Workbench_test8.png](images/annotated/evidence-20.png)

![검증 캡처 21 — Postman_Workbench_test9.png](images/annotated/evidence-21.png)

![검증 캡처 09 — Postman_Workbench_test10.png](images/annotated/evidence-09.png)

**캡처 확인 포인트**

- 요청의 `productId: 2`, `productCount: 2`와 응답 `201 Created`, 주문 ID 4를 확인합니다.
- DB 재고 7과 주문 ID 3·4의 수량 1·2를 확인합니다.
- 웹 재조회에서도 같은 상품 재고 7을 확인합니다.

**검증 결과:** 웹 1개 + API 2개 구매 결과 재고 10→9→7, 주문 2건을 대조했습니다.

### 초과 주문 거절 후 기존 데이터 유지

**실행·확인 내용**

남은 재고 7개에 수량 8로 주문하고 DB와 웹을 다시 조회했습니다.

![검증 캡처 10 — Postman_Workbench_test11.png](images/annotated/evidence-10.png)

![검증 캡처 11 — Postman_Workbench_test11_1.png](images/annotated/evidence-11.png)

![검증 캡처 12 — Postman_Workbench_test11_2.png](images/annotated/evidence-12.png)

![검증 캡처 13 — Postman_Workbench_test11_3.png](images/annotated/evidence-13.png)

**캡처 확인 포인트**

- `productCount: 8` 요청과 `400 Bad Request`, `재고 부족` 응답을 확인합니다.
- DB 재고 7과 기존 주문 ID 3·4만 유지된 결과를 확인합니다.
- 웹의 같은 상품 재고도 7입니다.

**검증 결과:** 초과 주문은 거절됐고 기존 재고·주문은 유지됐습니다. 이 순차 테스트로 동시 주문 정합성·분산 트랜잭션·결제 성공을 보장하지 않습니다.

## 05. 메트릭 수집과 시각화

### 노드·앱 수집 상태 확인

**실행·확인 내용**

Node Exporter와 앱 Actuator의 수집 경로를 연결하고 Prometheus Targets와 up 쿼리를 확인했습니다.

![검증 캡처 38 — prometheus_web검증.png](images/annotated/evidence-38.png)

![검증 캡처 39 — prometheus_web검증2.png](images/annotated/evidence-39.png)

![검증 캡처 40 — prometheus_web검증3.png](images/annotated/evidence-40.png)

**캡처 확인 포인트**

- Targets의 `node-exporter 4/4 UP`, `spring-apps 4/4 UP`을 확인합니다.
- 각 job을 조건으로 조회한 결과 시계열의 값이 모두 1인지 확인합니다.

**검증 결과:** 해당 시점의 노드·앱 메트릭 수집 성공을 확인했습니다. 노드 4개 화면은 앞선 부하 테스트의 노드 3개와 다른 시점이며, up=1이 구매 성공을 뜻하지 않습니다.

### 수집한 메트릭을 Grafana에 표시

**실행·확인 내용**

Prometheus를 데이터 소스로 연결하고 노드·앱 대시보드를 확인했습니다.

![검증 캡처 36 — grafana검증1.png](images/annotated/evidence-36.png)

![검증 캡처 37 — grafana검증2.png](images/annotated/evidence-37.png)

**캡처 확인 포인트**

- 노드 CPU·메모리·네트워크·디스크 패널을 확인합니다.
- 앱 수집 상태·프로세스 CPU·JVM Heap·HTTP 요청률 패널을 확인합니다.

**검증 결과:** 노드·앱 메트릭을 시각화했습니다. HTTP 요청률 변화는 관측 결과이며 업무 기능 성공은 API·DB 대조로 따로 검증했습니다.

## 06. Grafana 종료 원인 분석과 설정 보존

### 종료 원인 확인과 메모리·저장소 조치

**실행·확인 내용**

계정·대시보드 설정 소실 후 컨테이너의 마지막 종료 상태를 조회했습니다.

![검증 캡처 35 — grafana_ommkilled오류 해결1.png](images/annotated/evidence-35.png)

**캡처 확인 포인트**

- `restartCount: 1`, `Reason: OOMKilled`, `ExitCode: 137`을 확인합니다.

**검증 결과:** 메모리 부족에 따른 종료를 확인했습니다. 메모리 한도 500Mi→1Gi·requests 250Mi→512Mi 조정과 별개로, 설정 보존을 위해 /var/lib/grafana에 EBS gp3 5Gi PVC를 연결했습니다.

**조치 후 재검증 — 사용자 실행 보고**

당시 EBS CSI Controller 2/2·노드 DaemonSet 3/3·CSIDriver 등록 출력을 확인했습니다. PVC Bound·Grafana 배포는 사용자 완료 보고이며, 설정을 다시 저장한 뒤 rollout restart했습니다. 사용자는 변경한 계정·데이터 소스·대시보드가 유지됐다고 보고했습니다. **재시작 전후 보존 비교 캡처는 없으므로**, 다른 대시보드 화면으로 이를 대신 증명하지 않습니다.

## 07. CloudWatch 상태 변경과 SNS 알림 전달

### 경보 조건과 SNS 연결 확인

**실행·확인 내용**

AWS/EC2 CPUUtilization의 ASG 평균이 80% 이상인 5분 구간 2회(300초·2/2) 조건으로 경보를 구성하고 ALARM·OK 상태의 SNS 작업을 연결했습니다.

![검증 캡처 25 — cloudewatch1.png](images/annotated/evidence-25.png)

![검증 캡처 26 — cloudewatch2.png](images/annotated/evidence-26.png)

![검증 캡처 27 — cloudewatch3.png](images/annotated/evidence-27.png)

**캡처 확인 포인트**

- CPU 임계값·평가 데이터 포인트 2/2·기간 5분을 확인합니다.
- ALARM·OK 상태에서 같은 SNS 주제로 전달하는 작업을 확인합니다.
- 세 번째 이미지는 수동 테스트 이전의 이력이며 아래 테스트 결과와 구분합니다.

**검증 결과:** 경보 판단 조건과 알림 전달 대상을 연결했습니다. 이 설정 화면 자체는 실제 CPU 임계값 초과 발생의 증거가 아닙니다.

### SNS 직접 게시 테스트

**실행·확인 내용**

SNS 주제에 테스트 메시지를 직접 게시하고 수신 메일을 확인했습니다.

![검증 캡처 31 — cloudwatch_구독이메일_메세지테스트.png](images/annotated/evidence-31.png)

**캡처 확인 포인트**

- 이 이미지는 기존 AI 가림 편집 설명용 사본입니다. 원본 그대로의 검증 증거로 취급하지 않습니다.

**검증 결과:** 직접 게시 메시지 수신은 당시 원본 확인 기록에 근거합니다. 아래 CloudWatch 경보 경로 테스트와는 별도입니다.

### 수동 ALARM 전환과 경보 메일·이력 대조

**실행·확인 내용**

set-alarm-state로 경보를 ALARM 상태로 바꾸고 이메일과 CloudWatch History를 확인했습니다.

![검증 캡처 28 — cloudewatch_test1.png](images/annotated/evidence-28.png)

![검증 캡처 29 — cloudewatch_test2.png](images/annotated/evidence-29.png)

![검증 캡처 30 — cloudewatch_test3.png](images/annotated/evidence-30.png)

**캡처 확인 포인트**

- 실행 명령의 `state-value ALARM`과 `Manual notification path test` 사유를 확인합니다.
- 수신 메일의 ALARM 제목, `OK → ALARM`, 동일한 수동 테스트 사유를 확인합니다.
- History의 11:07 ALARM·11:08 OK 전환과 SNS 작업 실행을 확인합니다.

**검증 결과:** CloudWatch 상태 변경→SNS→이메일 전달 경로를 확인했습니다. 실제 CPU 80% 이상을 10분 유지한 부하 테스트가 아닙니다. OK 메일 수신은 사용자 보고입니다.

### EKS 제어 영역 로그 확인

**실행·확인 내용**

EKS의 api·audit·authenticator 로그 수집을 설정하고 CloudWatch 로그 그룹을 확인했습니다.

![검증 캡처 32 — cloudwatch_로그스트림확인.png](images/annotated/evidence-32.png)

**캡처 확인 포인트**

- `kube-apiserver`, `kube-apiserver-audit`, `authenticator` 로그 스트림과 마지막 이벤트 시각을 확인합니다.

**검증 결과:** EKS 제어 영역 로그 스트림을 확인했습니다. 앱 컨테이너 로그 전체 수집이나 주문 완료 SNS 연동을 완료한 구성은 아닙니다.

## 08. DB 접근 범위 제한 후 재접속

### PC /32 적용과 보안 그룹 확인

**실행·확인 내용**

실습 중 `0.0.0.0/0`이던 외부 Workbench 접근 허용 범위를 최종 PC 공인 IP /32로 변경하고 Terraform을 적용한 뒤 RDS 보안 그룹을 확인했습니다.

![검증 캡처 22 — RDS의 공개 접근은 유지하면서 외부 PC의 MySQL 접속 허용 범위만 제한.png](images/annotated/evidence-22.png)

![검증 캡처 24 — RDS의 공개 접근은 유지하면서 외부 PC의 MySQL 접속 허용 범위만 제한3.png](images/annotated/evidence-24.png)

**캡처 확인 포인트**

- `workbench_allowed_cidr` 값이 PC 공인 IP `/32`인지 확인합니다.
- RDS의 CIDR/IP Inbound 규칙과 별도의 EKS 보안 그룹 규칙을 확인합니다.

**검증 결과:** 외부 MySQL 접근 출발지를 제한했습니다. RDS의 Public 접근 자체는 유지합니다.

### 변경 후 Workbench 재접속·조회

**실행·확인 내용**

접근 범위 변경 후 Workbench에서 DB를 선택하고 같은 상품을 재조회했습니다.

![검증 캡처 23 — RDS의 공개 접근은 유지하면서 외부 PC의 MySQL 접속 허용 범위만 제한2.png](images/annotated/evidence-23.png)

**캡처 확인 포인트**

- 결과 행의 상품 ID 2·재고 7을 확인합니다.
- 하단 초기 1046 오류 뒤 `USE ordermsa`와 SELECT 성공을 확인합니다.

**검증 결과:** 접근 범위를 제한한 상태에서 DB 조회가 가능함을 확인했습니다. 다른 모든 출발지의 접속 거부까지 시험한 결과는 아닙니다.

## 검증 완료 범위와 한계

회원·상품 이미지·순차 주문, 자동 배포, 선언 상태 복구, 부하 확장·축소, 메트릭 시각화, 알림 전달을 확인했습니다. **결제·동시 주문 정합성·분산 트랜잭션 보장·멀티 AZ DB 장애 복구·성능 SLA는 검증 범위에 포함하지 않습니다.**

## 기록 범위

- 원본 45개 중 일반 캡처 43개는 보존했고, 이 문서에는 빨간 표시를 얹은 별도 사본을 배치했습니다. 글자·수치의 생성·재작성 없이 원본 영역을 사용했습니다.
- 로그인 응답과 SNS 직접 게시 메일 2개는 과거 AI 가림 편집본이며 해당 이미지와 본문에 설명용 사본임을 표시했습니다. 이번에 생성형 편집을 다시 적용하지 않았습니다.
- 재검증 캡처가 없는 항목은 실행 보고로 표시했습니다. 중간 화면·별도 상품·서로 다른 시점의 결과를 최종 완료 증거로 합치지 않았습니다.
