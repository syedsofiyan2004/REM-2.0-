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

######## Login to ECR and pull image
aws ecr get-login-password --region "${bedrock_region}" | docker login --username AWS --password-stdin "${ecr_registry}"

/usr/bin/docker rm -f rem-app || true
/usr/bin/docker pull "${ecr_repo_url}:${image_tag}"
/usr/bin/docker run -d --name rem-app --restart unless-stopped \
  -l com.centurylinklabs.watchtower.enable=true \
  -p 80:8000 -p 8000:8000 \
  -e IMAGE_TAG="${image_tag}" \
  -e BEDROCK_REGION="${bedrock_region}" \
  -e BEDROCK_MODEL="${bedrock_model}" \
  -e POLLY_REGION="${polly_region}" \
  -e POLLY_VOICE="${polly_voice}" \
  -e BEDROCK_MAX_RETRIES="${bedrock_max_retries}" \
  -e CHAT_MAX_CONCURRENCY="${chat_max_concurrency}" \
  -e TTS_MAX_CONCURRENCY="${tts_max_concurrency}" \
  -e TTS_CACHE_TTL="${tts_cache_ttl}" \
  -e UVICORN_WORKERS="${uvicorn_workers}" \
  "${ecr_repo_url}:${image_tag}"

# Start Watchtower to auto-update the rem-app container when a new :${image_tag} is pushed
/usr/bin/docker rm -f watchtower || true
/usr/bin/docker run -d --name watchtower --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --interval 60 \
  --cleanup \
  --include-stopped --revive-stopped \
  --stop-timeout 30s \
  rem-app

# Refresh ECR login periodically so pulls keep working (token expires ~12h)
cat >/etc/systemd/system/ecr-login-refresh.service <<UNIT
[Unit]
Description=Refresh ECR Docker Login
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -lc 'aws ecr get-login-password --region "${bedrock_region}" | docker login --username AWS --password-stdin "${ecr_registry}"'
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

