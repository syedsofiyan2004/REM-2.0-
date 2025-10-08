#!/bin/bash
set -euo pipefail

# Install Docker and helpers
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg awscli
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Login to ECR and pull image
aws ecr get-login-password --region "${aws_region}" | docker login --username AWS --password-stdin "${ecr_repo_url}"

# Start the application container
/usr/bin/docker rm -f rem-app || true
/usr/bin/docker pull "${ecr_repo_url}:latest"
/usr/bin/docker run -d --name rem-app --restart unless-stopped \
  -l com.centurylinklabs.watchtower.enable=true \
  -p 80:8000 -p 8000:8000 \
  -e IMAGE_TAG="latest" \
  -e BEDROCK_REGION="${aws_region}" \
  -e BEDROCK_MODEL="anthropic.claude-3-haiku-20240307-v1:0" \
  -e POLLY_REGION="${aws_region}" \
  -e POLLY_VOICE="Ruth" \
  -e BEDROCK_MAX_RETRIES="3" \
  -e CHAT_MAX_CONCURRENCY="4" \
  -e TTS_MAX_CONCURRENCY="3" \
  -e TTS_CACHE_TTL="900" \
  -e UVICORN_WORKERS="2" \
  "${ecr_repo_url}:latest"

# Start Watchtower for auto-updates (simplified)
/usr/bin/docker rm -f watchtower || true
/usr/bin/docker run -d --name watchtower --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --interval 30 \
  --cleanup \
  --include-stopped --revive-stopped \
  --stop-timeout 30s \
  rem-app

# Simple ECR login refresh (every 6 hours)
cat >/etc/systemd/system/ecr-login-refresh.service <<UNIT
[Unit]
Description=Refresh ECR Docker Login
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -lc 'aws ecr get-login-password --region "${aws_region}" | docker login --username AWS --password-stdin "${ecr_repo_url}"'
UNIT

cat >/etc/systemd/system/ecr-login-refresh.timer <<UNIT
[Unit]
Description=Run ECR login refresh every 6 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now ecr-login-refresh.timer

echo "✅ Simple REM deployment completed successfully!"