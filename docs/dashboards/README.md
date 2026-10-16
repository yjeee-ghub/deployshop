# Grafana 대시보드 내보내기

2026-10-16 실습 환경에서 사용자가 내보낸 JSON 두 개를 보관했습니다. 파일을 저장소에 넣는 것만으로 실행 중인 Grafana에 반영되지는 않습니다.

| 파일 | 용도 |
|---|---|
| [node-exporter-full.export.json](node-exporter-full.export.json) | Node Exporter Full 원본 내보내기 |
| [application-metrics.export.json](application-metrics.export.json) | Deployshop Application Metrics 원본 내보내기 |
| [application-metrics.current.json](application-metrics.current.json) | 원본에서 HTTP 요청 수 쿼리의 health·actuator 제외 조건을 보완한 재사용 사본 |

두 원본은 수정하지 않았습니다. 내보내기 형식은 `dashboard.grafana.app/v2`이며, 실습 내보내기 메타데이터에는 Grafana 13.2.4가 기록되어 있습니다. 다른 버전에서는 Import 호환성을 확인해야 합니다.

## 다시 가져오기

1. Grafana에 로그인하고 Prometheus 데이터 소스를 생성합니다.
2. 데이터 소스 URL을 `http://prometheus-service.monitoring.svc.cluster.local:9090`으로 설정하고 연결을 확인합니다.
3. Dashboards의 Import 화면에서 JSON 파일을 가져옵니다.
4. 원본의 데이터 소스 UID는 `dg1e5uk2ia7swc`입니다. 새 환경의 UID와 다르면 각 패널에서 현재 Prometheus 데이터 소스를 다시 선택합니다.
5. 시간 범위를 최근 15분으로 설정하고 데이터가 보이는지 확인합니다. 새 Prometheus에는 과거 시계열이 없을 수 있습니다.

## 애플리케이션 패널

| 패널 | PromQL |
|---|---|
| 앱 수집 상태 | `up{job="spring-apps"}` |
| 프로세스 CPU 사용률 | `process_cpu_usage{job="spring-apps"} * 100` |
| JVM Heap 사용량 | `sum by (app, pod) (jvm_memory_used_bytes{job="spring-apps", area="heap"})` |
| 초당 HTTP 요청 수 | `sum by (app) (rate(http_server_requests_seconds_count{job="spring-apps", uri!~"/health|/actuator.*"}[5m]))` |

HTTP 요청 수 원본은 `/actuator/prometheus`만 제외합니다. 재사용 사본은 `/health`와 `/actuator` 경로도 제외합니다. 이 사본을 실제 환경에 Import하고 재검증했다는 의미는 아닙니다. 낮은 트래픽에서 5분 평균 요청률은 0에 가까울 수 있습니다.

Grafana EBS PVC는 대시보드·계정·데이터 소스 설정을 저장합니다. Prometheus의 수집 데이터는 별도 영구 볼륨을 구성하지 않아 재시작 시 유지가 보장되지 않습니다.
