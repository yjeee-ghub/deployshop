#############################
# 모니터링·주문 알림을 받을 이메일
#############################

# CloudWatch 경보와 선택적으로 사용하는 주문 알림이 같은 이메일 변수를 사용합니다.
# sensitive는 일반 출력에서 값을 가리는 설정이며, 이메일을 암호화하는 기능은 아닙니다.
variable "alert_email" {
  description = "Email address for monitoring notifications; confirm the SNS subscription email after apply."
  type        = string
  default     = "yoonjoung429@gmail.com"
  sensitive   = true

  # 공백 없이 사용자명@도메인 형태인지 검사합니다.
  validation {
    condition     = can(regex("^[^[:space:]@]+@[^[:space:]@]+\\.[^[:space:]@]+$", var.alert_email))
    error_message = "Enter a valid email address for alert_email."
  }
}


#############################
# EKS 제어 영역 로그 보관
#############################

# EKS API 요청·감사·인증 관련 로그를 저장하는 CloudWatch 로그 그룹입니다.
# 어떤 종류의 로그를 보낼지는 EKS 모듈의 enabled_cluster_log_types에서 설정합니다.
resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  # Terraform이 이 로그 그룹을 삭제하는 변경을 계획하면 중단하도록 보호합니다.
  lifecycle {
    prevent_destroy = true
  }
}


#############################
# 모니터링 경보 전달용 SNS 주제
#############################

# CloudWatch가 경보 메시지를 보내는 수신 지점입니다.
# 실제 이메일 수신자는 아래의 SNS 구독에서 연결합니다.
resource "aws_sns_topic" "monitoring_alerts" {
  name = "msa-monitoring-alerts"
}


#############################
# 모니터링 경보 이메일 구독
#############################

# SNS 주제에 게시된 메시지를 alert_email 주소로 전달합니다.
# apply 후 SNS가 보낸 구독 확인 이메일에서 승인을 완료해야 수신할 수 있습니다.
resource "aws_sns_topic_subscription" "monitoring_email" {
  topic_arn = aws_sns_topic.monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}


#############################
# EKS 노드 그룹의 평균 CPU 경보
#############################

# 개별 노드의 최대 CPU가 아니라, 같은 ASG에 속한 EC2 노드들의 평균 CPU를 봅니다.
# ASG 이름은 EKS 모듈에서 받아오므로 개별 EC2 인스턴스 ID를 직접 적지 않습니다.
resource "aws_cloudwatch_metric_alarm" "eks_node_cpu_high" {
  alarm_name          = "${var.cluster_name}-node-group-cpu-high"
  alarm_description   = "EKS node group average CPU >= 80% for two consecutive 5-minute periods."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"

  # 5분 단위로 평가하고, 최근 두 평가 구간이 모두 80% 이상이면 경보 상태로 전환합니다.
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"

  # 이 ASG에 속한 노드들을 대상으로 CPU 지표를 집계합니다.
  dimensions = {
    AutoScalingGroupName = module.eks.node_autoscaling_group_name
  }

  # 경보 발생과 정상 상태 복귀 시 각각 같은 SNS 주제로 메시지를 보냅니다.
  alarm_actions = [aws_sns_topic.monitoring_alerts.arn]
  ok_actions    = [aws_sns_topic.monitoring_alerts.arn]
}


#############################
# 모니터링 리소스 정보 출력
#############################

# 알림 주제의 ARN과 CPU 경보 이름을 출력합니다.
output "monitoring_sns_topic_arn" {
  value = aws_sns_topic.monitoring_alerts.arn
}

output "monitoring_cpu_alarm_name" {
  value = aws_cloudwatch_metric_alarm.eks_node_cpu_high.alarm_name
}
