#############################
# 주문 알림 기능 사용 여부
#############################

# 기본값은 false이며, 주문 알림용 SNS·IAM 리소스를 만들지 않습니다.
# true로 설정하면 아래 리소스가 생성됩니다. 실제 주문 알림 발송에는 앱 연동도 필요합니다.
variable "enable_order_notifications" {
  description = "Optional SNS order notifications; configure IRSA and app settings before enabling."
  type        = bool
  default     = false
}


#############################
# 주문 서비스가 사용할 EKS OIDC 제공자
#############################

# 해당 EKS 클러스터에 등록된 IAM OIDC 제공자의 ARN을 입력합니다.
# GitHub Actions 인증용 OIDC가 아니라, EKS의 Pod가 IAM 역할을 사용하기 위한 설정입니다.
variable "order_irsa_provider_arn" {
  description = "Existing OIDC provider ARN for this EKS cluster; not the GitHub OIDC provider."
  type        = string
  default     = ""
}

# 주문 알림을 켠 경우에만 기존 OIDC 제공자 정보를 조회합니다.
# 제공자를 새로 만드는 리소스가 아니므로 입력한 ARN의 제공자가 미리 있어야 합니다.
data "aws_iam_openid_connect_provider" "ordering" {
  count = var.enable_order_notifications ? 1 : 0
  arn   = var.order_irsa_provider_arn
}


#############################
# 주문 알림 전달용 SNS 주제
#############################

# 주문 서비스가 알림 메시지를 게시할 SNS 주제를 생성합니다.
# count가 0이면 생성하지 않고, 1이면 한 개를 생성합니다.
resource "aws_sns_topic" "orders" {
  count = var.enable_order_notifications ? 1 : 0
  name  = "${var.project_name}-orders"
}


#############################
# 주문 알림 이메일 구독
#############################

# monitoring.tf에 선언된 alert_email을 주문 알림 수신 주소로도 사용합니다.
# 이메일을 받으려면 apply 후 SNS 구독 확인 이메일에서 승인을 완료해야 합니다.
resource "aws_sns_topic_subscription" "order_email" {
  count     = var.enable_order_notifications ? 1 : 0
  topic_arn = aws_sns_topic.orders[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}


#############################
# 주문 서비스 전용 IAM 역할과 신뢰 정책
#############################

# EKS의 특정 ServiceAccount만 이 역할을 맡아 임시 AWS 자격 증명을 받도록 허용합니다.
# 이 파일은 ServiceAccount 자체를 만들거나 Pod에 연결하지는 않습니다.
# 별도로 soldesk/ordering-sa를 만들고 역할 ARN을 연결한 뒤, 주문 Pod가 사용하도록 설정해야 합니다.
resource "aws_iam_role" "ordering_notifications" {
  count = var.enable_order_notifications ? 1 : 0
  name  = "${var.project_name}-ordering-sns-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"

      # 위에서 조회한 EKS OIDC 제공자가 발급한 토큰을 신뢰합니다.
      Principal = { Federated = data.aws_iam_openid_connect_provider.ordering[0].arn }
      Condition = {
        StringEquals = {
          # soldesk 네임스페이스의 ordering-sa만 역할을 사용할 수 있습니다.
          "${replace(data.aws_iam_openid_connect_provider.ordering[0].url, "https://", "")}:sub" = "system:serviceaccount:soldesk:ordering-sa"
          # AWS STS를 대상으로 발급된 토큰인지 확인합니다.
          "${replace(data.aws_iam_openid_connect_provider.ordering[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}


#############################
# 주문 알림 SNS 게시 권한
#############################

# 위 IAM 역할에 주문 알림 주제로 메시지를 게시하는 권한만 부여합니다.
# 신뢰 정책은 역할을 사용할 주체를 정하고, 이 정책은 역할이 할 수 있는 작업을 정합니다.
resource "aws_iam_role_policy" "ordering_notifications" {
  count = var.enable_order_notifications ? 1 : 0
  role  = aws_iam_role.ordering_notifications[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.orders[0].arn
    }]
  })
}


#############################
# 주문 알림 연동 정보 출력
#############################

# 앱 연동에 사용할 SNS 주제 ARN과 ServiceAccount에 연결할 역할 ARN을 출력합니다.
# 기능이 꺼져 리소스가 없으면 try가 null을 반환합니다.
output "ordering_notification_topic_arn" {
  value = try(aws_sns_topic.orders[0].arn, null)
}

output "ordering_notification_role_arn" {
  value = try(aws_iam_role.ordering_notifications[0].arn, null)
}
