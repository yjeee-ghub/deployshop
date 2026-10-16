# 증거 이미지 목록

2026-10-16 사용자가 제공한 PNG 45개와 대시보드 JSON 2개를 기준으로 정리했습니다. 원본 파일명은 아래에서 공개 사본과 대응됩니다. 원본 폴더는 수정하지 않았습니다.

## 공개 사본 처리

- 일반 캡처 43개는 내용 변경 없이 복사했습니다. 브라우저 주소·AWS 계정 번호·공인 IP 등 화면에 표시된 환경 식별자는 남아 있습니다.
- `login-redacted.png`와 `sns-email-redacted.png`는 **ImageGen을 이용해 AI로 편집한 가림 설명용 사본**입니다. UI·해상도 등이 원본과 달라질 수 있어 원본 그대로의 검증 증거로 취급하지 않습니다. 비밀번호, access token, refreshToken 및 SNS 구독 해지 링크를 숨겼습니다.
- 편집 요청은 로그인 화면의 비밀번호·토큰을 불투명한 검정 사각형으로 가리고, SNS 화면의 구독 해지 링크 전체를 가리며 나머지 화면을 유지하는 것이었습니다. 편집 모드는 기존 이미지 편집입니다.
- 로그인 성공과 SNS 수신은 사용자 제공 원본에서 확인했으며, 공개 설명용 사본에는 민감한 문자열을 포함하지 않습니다. 원본 민감 정보 이미지는 저장소에 복사하지 않았습니다.

## 해석 시 주의할 시점

- `ArgoCD.png`는 monitoring OutOfSync 상태의 중간 화면입니다. 최종 전체 Synced는 사용자 실행 확인으로 구분합니다.
- CloudWatch ALARM 메일은 수동 `set-alarm-state` 테스트 결과입니다. 실제 CPU 80% 초과 부하 검증이 아닙니다.
- Grafana OOM 화면은 장애 확인 증거입니다. EBS 연결 및 재시작 후 데이터 유지 확인은 사용자 보고이며 해당 비교 캡처는 없습니다.
- HPA 캡처는 상품 Pod 1→5→1과 확장 시점 노드 3개를 보여 줍니다. 노드 3→2 축소는 사용자 보고입니다.
- 제품 ID 1의 웹 구매와 제품 ID 2의 Postman·DB 검증은 다른 상품입니다.

## 전체 대응표

| 번호 | 제공한 원본 파일명 | 공개 사본 |
|---|---|---|
| 1 | ArgoCD replicas 복구 실습1.png | [캡처 보기](images/evidence-01.png) |
| 2 | ArgoCD replicas 복구 실습2.png | [캡처 보기](images/evidence-02.png) |
| 3 | ArgoCD.png | [캡처 보기](images/evidence-03.png) |
| 4 | Cluster Autoscaler가 ASG의 노드 수를 조절할 수 있도록 AWS 권한을 연결.png | [캡처 보기](images/evidence-04.png) |
| 5 | HPA 확장_부하테스트1.png | [캡처 보기](images/evidence-05.png) |
| 6 | HPA 확장_부하테스트2.png | [캡처 보기](images/evidence-06.png) |
| 7 | Postman_Workbench_test.png | [캡처 보기](images/evidence-07.png) |
| 8 | Postman_Workbench_test1.png | [캡처 보기](images/evidence-08.png) |
| 9 | Postman_Workbench_test10.png | [캡처 보기](images/evidence-09.png) |
| 10 | Postman_Workbench_test11.png | [캡처 보기](images/evidence-10.png) |
| 11 | Postman_Workbench_test11_1.png | [캡처 보기](images/evidence-11.png) |
| 12 | Postman_Workbench_test11_2.png | [캡처 보기](images/evidence-12.png) |
| 13 | Postman_Workbench_test11_3.png | [캡처 보기](images/evidence-13.png) |
| 14 | Postman_Workbench_test2.png | [캡처 보기](images/evidence-14.png) |
| 15 | Postman_Workbench_test3.png | [캡처 보기](images/evidence-15.png) |
| 16 | Postman_Workbench_test4.png | [캡처 보기](images/evidence-16.png) |
| 17 | Postman_Workbench_test5.png | [AI 가림 설명용 사본](images/login-redacted.png) |
| 18 | Postman_Workbench_test6.png | [캡처 보기](images/evidence-18.png) |
| 19 | Postman_Workbench_test7.png | [캡처 보기](images/evidence-19.png) |
| 20 | Postman_Workbench_test8.png | [캡처 보기](images/evidence-20.png) |
| 21 | Postman_Workbench_test9.png | [캡처 보기](images/evidence-21.png) |
| 22 | RDS의 공개 접근은 유지하면서 외부 PC의 MySQL 접속 허용 범위만 제한.png | [캡처 보기](images/evidence-22.png) |
| 23 | RDS의 공개 접근은 유지하면서 외부 PC의 MySQL 접속 허용 범위만 제한2.png | [캡처 보기](images/evidence-23.png) |
| 24 | RDS의 공개 접근은 유지하면서 외부 PC의 MySQL 접속 허용 범위만 제한3.png | [캡처 보기](images/evidence-24.png) |
| 25 | cloudewatch1.png | [캡처 보기](images/evidence-25.png) |
| 26 | cloudewatch2.png | [캡처 보기](images/evidence-26.png) |
| 27 | cloudewatch3.png | [캡처 보기](images/evidence-27.png) |
| 28 | cloudewatch_test1.png | [캡처 보기](images/evidence-28.png) |
| 29 | cloudewatch_test2.png | [캡처 보기](images/evidence-29.png) |
| 30 | cloudewatch_test3.png | [캡처 보기](images/evidence-30.png) |
| 31 | cloudwatch_구독이메일_메세지테스트.png | [AI 가림 설명용 사본](images/sns-email-redacted.png) |
| 32 | cloudwatch_로그스트림확인.png | [캡처 보기](images/evidence-32.png) |
| 33 | github1.png | [캡처 보기](images/evidence-33.png) |
| 34 | github2.png | [캡처 보기](images/evidence-34.png) |
| 35 | grafana_ommkilled오류 해결1.png | [캡처 보기](images/evidence-35.png) |
| 36 | grafana검증1.png | [캡처 보기](images/evidence-36.png) |
| 37 | grafana검증2.png | [캡처 보기](images/evidence-37.png) |
| 38 | prometheus_web검증.png | [캡처 보기](images/evidence-38.png) |
| 39 | prometheus_web검증2.png | [캡처 보기](images/evidence-39.png) |
| 40 | prometheus_web검증3.png | [캡처 보기](images/evidence-40.png) |
| 41 | shop_imag2.png | [캡처 보기](images/evidence-41.png) |
| 42 | shop_imag2_1.png | [캡처 보기](images/evidence-42.png) |
| 43 | shop_image1.png | [캡처 보기](images/evidence-43.png) |
| 44 | shop_image3.png | [캡처 보기](images/evidence-44.png) |
| 45 | shop_s3_object.png | [캡처 보기](images/evidence-45.png) |

JSON은 [대시보드 안내](dashboards/README.md)에서 확인합니다. 항목별 판정은 [검증 결과](VALIDATION.md)를 기준으로 읽습니다.
