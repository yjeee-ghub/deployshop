# 실행 검증 결과

검증 기준일: 2026-10-16 (KST). 실행은 사용자가 직접 수행했습니다. 아래는 제공된 캡처·명령 출력·완료 보고를 구분해 정리한 기록이며, 문서 작성 중 새 부하·주문·AWS 변경을 실행하지 않았습니다.

## 1. 주문 결과 대조

검증 상품 ID `2`, 회원 ID `2`. 다른 상품 ID `1`의 초기 쇼핑몰 검증 캡처와 혼합하지 않습니다.

| 순서 | 동작 | HTTP / 화면 | 재고 | 해당 상품 주문 |
|---|---|---|---:|---|
| 1 | 신규 상품 등록 | 상품·이미지 표시 | 10 | 없음 |
| 2 | 웹 구매 1회 | 주문 완료 알림 | 9 | ID 3, quantity 1, ORDERED |
| 3 | API 구매 수량 2 | 201, 본문 4 | 7 | ID 4 추가, quantity 2 |
| 4 | API 구매 수량 8 | 400, 재고 부족 | 7 | ID 3·4 유지 |

SQL은 읽기 확인용이며 실제 비밀번호는 기록하지 않습니다.

```sql
USE ordermsa;
SET @product_id = 2;
SELECT id, name, price, stock_quantity, image_url
FROM product WHERE id = @product_id;
SELECT id, member_id, product_id, quantity, order_status
FROM ordering WHERE product_id = @product_id ORDER BY id;
```

웹의 주문 완료 알림 뒤 화면이 이동하기 전 재고 숫자는 이전 응답일 수 있습니다. 결과 판단은 재조회한 상품 화면·API·DB 값을 사용했습니다. 최종 웹 재고 7, DB 재고 7, 주문 ID 4의 수량 2가 연결됩니다.

## 2. 배포·복구

- Actions 초기 전체 서비스 업로드 실행 `2c7c12f` 성공 캡처가 있습니다. 워크플로는 변경 서비스의 Docker 빌드·ECR push·kubectl apply·rollout restart를 실행합니다.
- 이후 사용자가 서비스별 rollout 및 쇼핑몰 조회 정상 완료를 보고했습니다.
- 프런트엔드 `replicas=2` 수동 변경 후 `1/1` 복귀는 터미널 캡처로 확인했습니다.
- root 등록 직후·인증서 충돌 해결 전의 `ArgoCD.png`에는 `msa-monitoring OutOfSync`가 보입니다. 이는 실패 원인 설명용이며 최종 전체 정상 화면으로 사용하지 않습니다.
- issuer annotation 제거 커밋 후 전체 Synced·Healthy 및 HTTPS 정상은 사용자가 완료 보고했습니다. 최종 전체 목록 캡처를 추가하면 시점 연결이 더 명확해집니다.

## 3. 자동 확장·축소

- 상품 조회 부하: BusyBox 8개 루프, `http://product-service/product/list` 반복 GET.
- HPA 목표 30%, 최소 1·최대 5. 화면에서 상품 Pod `1 → 2 → 4 → 5` 확인.
- 노드 `2 → 3` 및 새 노드에 상품 Pod 배치 확인.
- 부하 Pod 삭제 후 CPU 감소·상품 Pod `5 → 1` 캡처 확인.
- 노드 최소 2 복귀는 사용자가 확인·보고했습니다. 제공된 축소 캡처는 HPA 출력이며 노드 축소 목록은 포함하지 않습니다.
- `kubectl top`의 CPU 실사용률만으로 CA 동작을 설명하지 않습니다. CA는 requests 등을 기준으로 스케줄 불가능한 Pod를 판단합니다.
- 모니터링 설치 시 Prometheus requests 부족으로 CA가 노드를 추가한 별도 이벤트도 있었습니다. 부하 실습 이후의 노드 수가 항상 2라고 단정하지 않습니다.

## 4. 모니터링

- Prometheus Targets: `spring-apps` 4/4 UP, 당시 `node-exporter` 4/4 UP 캡처.
- `up` 쿼리 결과 모두 1. 노드 수는 수집 당시 상태이며 부하 실습의 노드 3개와 시점이 다릅니다.
- Grafana 노드 대시보드에서 CPU·RAM·디스크·네트워크 확인.
- 앱 대시보드 4개 패널: up·프로세스 CPU·Heap·HTTP 요청률.
- 상태 확인 경로를 제외한 HTTP 요청 그래프에서 웹 조회 후 증가 확인.
- 대시보드 JSON 원본은 HTTP 쿼리 수정 전 내보내기입니다. 수정 쿼리를 적용한 파생 사본과 구분했습니다.

## 5. Grafana 장애·보존

1. `OOMKilled`, exit 137, restartCount 1 확인.
2. 메모리 한도 500Mi → 1Gi, requests 250Mi → 512Mi.
3. EBS CSI Controller 2/2·노드 DaemonSet 3/3·CSIDriver 등록 출력 확인.
4. gp3 5Gi PVC Bound·Grafana Running은 사용자 완료 보고.
5. 새 볼륨에 계정·데이터 소스·대시보드 재설정.
6. rollout restart 후 변경 비밀번호·데이터 소스·대시보드 유지 사용자 보고.

증거 PNG는 OOM 진단 화면입니다. Pod 교체 후 보존 성공은 대화 보고 근거이며 별도 EBS/PVC 성공 캡처가 있는 것으로 꾸미지 않습니다.

## 6. CloudWatch·SNS

- EKS 제어 영역 로그 스트림 목록과 최근 이벤트 시각 확인.
- ASG 평균 CPUUtilization, period 300s, evaluation 2/2, threshold 80 확인.
- SNS 직접 메시지 게시 후 이메일 수신 캡처.
- `set-alarm-state ALARM` 실행 캡처와 이유가 `Manual notification path test for Deployshop`인 이메일 확인.
- CloudWatch History에 ALARM 전환·SNS 실행, OK 복귀·SNS 실행 확인.
- OK 이메일 수신은 사용자가 완료 보고했으며 별도 OK 이메일 캡처는 제공되지 않았습니다.

**검증 의미:** CloudWatch 상태 변경 → SNS → 이메일 경로 검증입니다. 실제 CPU 임계값 초과 부하로 발생한 경보라고 표현하지 않습니다.

## 7. 최종 DB 접근 제한

- 실습 중 Workbench CIDR `0.0.0.0/0` 사용.
- 최종 PC 공인 IP `/32`로 수정·Terraform 적용·Workbench 재접속 완료.
- RDS 보안 그룹 캡처에서 `/32` 규칙과 별도 EKS SG 규칙 확인.
- RDS 퍼블릭 접근 자체는 유지. 운영용 private RDS 구축이라고 표현하지 않습니다.

## 8. 완료 범위

회원·이미지·주문 순차 기능, 자동 배포, 선언 상태 복구, 부하 확장·축소, 메트릭 시각화, 알림 전달을 검증했습니다. 결제·동시 주문 정합성·분산 트랜잭션·멀티 AZ DB 장애 복구·성능 수치 SLA는 검증 범위에 포함하지 않습니다.

캡처별 원본 파일명·공개용 파일·검증 시점은 [증거 목록](EVIDENCE.md)을 참고하세요.
