**DEPLOYSHOP · ARCHITECTURE**

# 상세 아키텍처

> 요청·배포·관측·인프라 관리 경로.

[문서 목록](README.md) · [구축 절차](SETUP.md) · [실행 결과](VALIDATION.md)

---

## 01. 전체 연결 구조

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

---

## 02. 배치와 접근

| 대상 | 배치·접근 방식 |
| :--- | :--- |
| **웹·API** | 같은 도메인의 API 요청 → Ingress → Gateway |
| **워커 노드** | Private App Subnet 배치·NAT 외부 통신 |
| **RDS** | Public 접근 유지·외부 PC `/32` 제한·EKS 보안 그룹 별도 허용 |
| **Private DB Subnet** | 정의만 존재·현재 RDS 배치에 미사용 |
| **Grafana 데이터** | EBS gp3 5Gi·PVC·같은 AZ 내 재연결 |

---

## 03. 관리 범위

| 관리 주체 | 대상 |
| :--- | :--- |
| **Terraform** | VPC·IAM·EKS·RDS·ECR·S3·CloudWatch/SNS·Local State |
| **CLI·콘솔** | Ingress NGINX·cert-manager·Argo CD·Metrics Server·Route 53·IRSA·EBS CSI 연결 |
| **Kubernetes Controller** | LoadBalancer Service → NLB / StorageClass·PVC → EBS |
| **Actions·Argo CD** | 이미지 직접 배포 / Git 선언 동기화·self-heal |

> **제어 분리** · HPA는 Backend replicas를, CA는 노드 용량을 조절합니다. Argo CD는 나머지 배포 선언을 관리합니다.
