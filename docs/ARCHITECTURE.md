# 상세 아키텍처

[프로젝트 개요](../README.md)

```mermaid
flowchart TB
    USER(["👤 Browser / Postman"]) --> DNS["Route 53"] --> NLB["Network Load Balancer"] --> ING["Ingress NGINX · HTTPS"]
    subgraph EKS["☁️ Amazon EKS · my-cluster"]
        ING --> FRONT["Frontend · Nginx"]
        ING --> GW["API Gateway"]
        GW --> MEMBER["👤 Member"]
        GW --> PRODUCT["📦 Product"]
        GW --> ORDER["🛒 Ordering"]
        ORDER -->|"재고 조회·차감"| PRODUCT
        EXPORTER["Node Exporter"] --> PROM["Prometheus"]
        MEMBER -.->|"Actuator"| PROM
        PRODUCT -.->|"Actuator"| PROM
        ORDER -.->|"Actuator"| PROM
        GW -.->|"Actuator"| PROM
        PROM --> GRAF["Grafana"]
        MS["Metrics Server"] --> HPA["HPA · Pod 수 조절"]
        CA["Cluster Autoscaler"]
    end
    MEMBER --> RDS[("RDS MySQL · ordermsa")]
    PRODUCT --> RDS
    ORDER --> RDS
    PRODUCT --> S3[("S3 · 상품 이미지")]
    GRAF -->|"PVC / EBS CSI"| EBS[("EBS gp3 · 5Gi")]
    CA --> ASG["ASG · EC2 노드 수 조절"]
    GIT["GitHub · main"] --> ACTIONS["GitHub Actions"] --> ECR["Amazon ECR"]
    ACTIONS -.->|"apply / rollout restart"| EKS
    ECR -.->|"이미지 다운로드"| EKS
    GIT --> ARGO["Argo CD"] -.->|"선언 상태 동기화·복구"| EKS
    TF["Terraform · Local State"] -.->|"AWS 리소스"| EKS
    TF -.-> RDS
    TF -.-> S3
    EKS -.->|"제어 영역 로그"| CW["CloudWatch"]
    ASG -.->|"노드 평균 CPU"| CW
    CW --> SNS["SNS"] --> MAIL["이메일"]
    classDef network fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    classDef app fill:#ede9fe,stroke:#8b5cf6,color:#5b21b6
    classDef storage fill:#dcfce7,stroke:#22c55e,color:#166534
    classDef delivery fill:#ffedd5,stroke:#f97316,color:#9a3412
    classDef monitor fill:#fce7f3,stroke:#ec4899,color:#9d174d
    class USER,DNS,NLB,ING network
    class FRONT,GW,MEMBER,PRODUCT,ORDER app
    class RDS,S3,EBS storage
    class GIT,ACTIONS,ECR,ARGO,TF delivery
    class EXPORTER,PROM,GRAF,MS,HPA,CA,CW,SNS,MAIL,ASG monitor
```

- 프런트엔드 → 같은 도메인의 API 경로 → Ingress → Gateway.
- 워커 노드: 프라이빗 앱 서브넷 배치.
- RDS: **퍼블릭 접근 유지**, 외부 MySQL 접근은 실습 PC `/32`로 제한. EKS 보안 그룹 규칙 별도 유지.
- 프라이빗 DB 서브넷: 정의만 존재, 현재 RDS 배치에 미사용.
