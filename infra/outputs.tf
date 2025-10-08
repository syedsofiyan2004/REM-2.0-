output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_eip.rem.public_ip}:8000"
}

output "app_url_port_80" {
  description = "URL to access the application on port 80"
  value       = "http://${aws_eip.rem.public_ip}"
}

output "public_ip" {
  description = "Elastic IP address"
  value       = aws_eip.rem.public_ip
}

output "ecr_repo_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.rem.repository_url
}