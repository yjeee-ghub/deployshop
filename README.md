# yjeee-deployshop

**AWS EKS 기반 MSA 온라인 주문 서비스 · DevOps 포트폴리오**

회원가입부터 상품 조회, 구매, 재고 차감, 주문 저장까지 이어지는 온라인
쇼핑몰을 **마이크로서비스 아키텍처(MSA)** 로 구성하고, AWS 클라우드
환경에서 **인프라 구축·배포·운영을 자동화**한 프로젝트입니다.

## Architecture

``` mermaid
flowchart TB
    U["사용자 / 웹 브라우저"] --> DNS["Route 53 · HTTPS"]
    DNS --> NLB["AWS NLB"]
    NLB --> ING["Ingress NGINX"]

    subgraph EKS["Amazon EKS · Kubernetes"]
        ING --> FE["Frontend"]
        ING --> GW["API Gateway"]
        FE --> GW
        GW --> MEM["Member Service"]
        GW --> PROD["Product Service"]
        GW --> ORD["Ordering Service"]
        ORD -->|"재고 조회 · 차감 (Feign)"| PROD
    end

    MEM --> DB[("Amazon RDS · MySQL")]
    PROD --> DB
    ORD --> DB
    PROD --> S3[("Amazon S3 · 상품 이미지")]

    GIT["GitHub"] --> CI["GitHub Actions · CI"]
    CI --> ECR["Amazon ECR"]
    ECR -.-> EKS
    GIT --> CD["Argo CD · GitOps"]
    CD -.-> EKS

    TF["Terraform"] -.->|"AWS 인프라 프로비저닝"| EKS
    MON["Prometheus · Grafana"] -.->|"메트릭 모니터링"| EKS
    OBS["CloudWatch · SNS"] -.->|"AWS 모니터링 · 알림 구성"| EKS
```

## 주요 서비스 및 기능

  -----------------------------------------------------------------------
  서비스                              주요 기능
  ----------------------------------- -----------------------------------
  **Member**                          회원가입, 중복 회원 검사, 로그인,
                                      JWT 인증 및 토큰 재발급

  **Product**                         상품 등록·목록·상세 조회, S3 이미지
                                      업로드, 재고 관리

  **Ordering**                        상품 재고 확인, 주문 생성, 재고
                                      차감, 주문 내역 DB 저장

  **Frontend**                        상품 탐색, 회원 로그인, 상품 구매
                                      UI

  **API Gateway**                     서비스별 API 라우팅 및 인증 요청
                                      처리
  -----------------------------------------------------------------------

## 주문 처리 흐름

``` mermaid
sequenceDiagram
    actor User as 사용자
    participant Web as Frontend
    participant Order as Ordering Service
    participant Product as Product Service
    participant DB as RDS MySQL

    User->>Web: 구매하기 클릭
    Web->>Order: 주문 생성 요청 (JWT)
    Order->>Product: 상품 재고 조회
    Product-->>Order: 현재 재고 반환
    alt 재고 충분
        Order->>Product: 구매 수량만큼 재고 차감
        Product->>DB: 변경된 재고 저장
        Order->>DB: 주문 정보 저장
        Order-->>Web: 주문 생성 성공
        Web-->>User: 주문 완료 표시
    else 재고 부족
        Order-->>Web: 주문 실패
        Web-->>User: 재고 부족 안내
    end
```

**주문 시스템 핵심:** Ordering Service가 Product Service를 **Feign 기반
동기 HTTP 호출**로 연동해 재고를 확인·차감한 후, 주문 정보를 MySQL에
저장합니다. 재고가 부족하면 주문을 거절합니다.

> **구현 범위:** 재고 검증·차감 로직은 구현되어 있습니다. 다만 동시
> 주문에 대한 별도 락·원자적 재고 차감 및 서비스 간 분산 트랜잭션 보장은
> 현재 확인된 구현 범위에 포함되지 않습니다.

## DevOps 핵심 구성

  -----------------------------------------------------------------------
  영역                                기술 및 역할
  ----------------------------------- -----------------------------------
  **IaC**                             Terraform 모듈 기반 AWS 인프라
                                      프로비저닝

  **Container / Orchestration**       Docker, Amazon ECR, Amazon EKS,
                                      Kubernetes

  **Network / TLS**                   Route 53, NLB, Ingress NGINX,
                                      cert-manager

  **CI/CD · GitOps**                  GitHub Actions 이미지 빌드·배포,
                                      Argo CD 선언적 배포 관리

  **Scaling**                         Kubernetes HPA 기반 Pod 자동 확장
                                      구성

  **Monitoring**                      Prometheus, Grafana 및 AWS
                                      CloudWatch·SNS 모니터링 구성
  -----------------------------------------------------------------------

## 프로젝트 목표

단순한 쇼핑몰 구현을 넘어 **실제 서비스를 클라우드 환경에 배포하고
운영하는 전체 과정**을 경험하는 것이 목표입니다.

**인프라 코드화 → 컨테이너 배포 → GitOps 자동화 → 모니터링 및 운영**

------------------------------------------------------------------------

*Project: yjeee-deployshop · AWS MSA / DevOps Portfolio*
