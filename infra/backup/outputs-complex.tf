output "alb_dns_name" {
  value       = aws_lb.app.dns_name
  description = "Public DNS name of the Application Load Balancer"
}

output "app_url" {
  value       = "http://${aws_lb.app.dns_name}"
  description = "HTTP URL of the load-balanced app"
}

output "ecr_repo_url" {
  value       = aws_ecr_repository.rem.repository_url
  description = "ECR repository URL (compare account+region with CI push logs)"
}
