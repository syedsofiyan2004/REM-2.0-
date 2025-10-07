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

# Remove any existing containers
/usr/bin/docker rm -f rem-app || true

# Pull the latest image with retry logic
for attempt in {1..3}; do
  echo "Pulling image, attempt $attempt/3..."
  if /usr/bin/docker pull "${ecr_repo_url}:${image_tag}"; then
    echo "Image pull successful"
    break
  else
    echo "Image pull failed, retrying in 10 seconds..."
    sleep 10
  fi
done

# Start main application container with proper labels
/usr/bin/docker run -d --name rem-app --restart unless-stopped \
  --label com.centurylinklabs.watchtower.enable=true \
  --label com.centurylinklabs.watchtower.monitor-only=false \
  --label watchtower=true \
  -p 80:8000 -p 8000:8000 \
  -e IMAGE_TAG="${image_tag}" \
  -e BEDROCK_REGION="${bedrock_region}" \
  -e BEDROCK_MODEL="${bedrock_model}" \
  -e POLLY_REGION="${polly_region}" \
  -e POLLY_VOICE="${polly_voice}" \
  -e BEDROCK_MAX_RETRIES="${bedrock_max_retries}" \
  -e CHAT_MAX_CONCURRENCY="${chat_max_concurrency}" \
  -e TTS_MAX_CONCURRENCY="${tts_cache_ttl}" \
  -e UVICORN_WORKERS="${uvicorn_workers}" \
  "${ecr_repo_url}:${image_tag}"

echo "✅ rem-app container started successfully"

# Create Watchtower configuration directory
mkdir -p /etc/watchtower

# Create ECR credential helper script for Watchtower
cat > /etc/watchtower/ecr-login.sh << 'SCRIPT'
#!/bin/bash
# This script refreshes ECR login for Watchtower
echo "Refreshing ECR login for Watchtower..."
aws ecr get-login-password --region "${bedrock_region}" | docker login --username AWS --password-stdin "${ecr_registry}"
echo "ECR login refreshed at $(date)"
SCRIPT
chmod +x /etc/watchtower/ecr-login.sh

# Remove any existing Watchtower
/usr/bin/docker rm -f watchtower || true

# Start enhanced Watchtower with better configuration
/usr/bin/docker run -d --name watchtower --restart unless-stopped \
  --label com.centurylinklabs.watchtower.enable=false \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /root/.docker/config.json:/config.json:ro \
  -e WATCHTOWER_CLEANUP=true \
  -e WATCHTOWER_POLL_INTERVAL=60 \
  -e WATCHTOWER_TIMEOUT=60s \
  -e WATCHTOWER_ROLLING_RESTART=true \
  -e WATCHTOWER_INCLUDE_STOPPED=true \
  -e WATCHTOWER_REVIVE_STOPPED=true \
  -e WATCHTOWER_DEBUG=true \
  -e WATCHTOWER_LOG_LEVEL=info \
  -e WATCHTOWER_NOTIFICATIONS_LEVEL=info \
  containrrr/watchtower:latest \
  --label-enable \
  --stop-timeout 30s \
  --cleanup \
  rem-app

echo "✅ Watchtower started successfully"

# Enhanced ECR authentication refresh system
cat >/etc/systemd/system/ecr-login-refresh.service <<UNIT
[Unit]
Description=Refresh ECR Docker Login for Container Updates
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
User=root
ExecStartPre=/bin/bash -c 'echo "Starting ECR login refresh at \$(date)"'
ExecStart=/etc/watchtower/ecr-login.sh
ExecStartPost=/bin/bash -c 'echo "ECR login refresh completed at \$(date)"'
# Restart Watchtower after ECR login refresh to pick up new credentials
ExecStartPost=/usr/bin/docker restart watchtower
StandardOutput=journal
StandardError=journal
UNIT

cat >/etc/systemd/system/ecr-login-refresh.timer <<UNIT
[Unit]
Description=Run ECR login refresh every 4 hours (well before 12h expiry)
Requires=ecr-login-refresh.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=4h
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Create Watchtower health check service
cat >/etc/systemd/system/watchtower-health.service <<UNIT
[Unit]
Description=Check Watchtower Health and Restart if Needed
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
if ! docker ps | grep -q watchtower; then
  echo "Watchtower not running, restarting..."
  docker start watchtower || {
    echo "Failed to start existing watchtower, recreating..."
    docker rm -f watchtower
    # Recreate watchtower with same config as above
    docker run -d --name watchtower --restart unless-stopped \
      --label com.centurylinklabs.watchtower.enable=false \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /root/.docker/config.json:/config.json:ro \
      -e WATCHTOWER_CLEANUP=true \
      -e WATCHTOWER_POLL_INTERVAL=60 \
      -e WATCHTOWER_TIMEOUT=60s \
      -e WATCHTOWER_ROLLING_RESTART=true \
      -e WATCHTOWER_INCLUDE_STOPPED=true \
      -e WATCHTOWER_REVIVE_STOPPED=true \
      -e WATCHTOWER_DEBUG=true \
      containrrr/watchtower:latest \
      --label-enable --stop-timeout 30s --cleanup rem-app
  }
else
  echo "Watchtower is running normally"
fi
'
UNIT

cat >/etc/systemd/system/watchtower-health.timer <<UNIT
[Unit]
Description=Check Watchtower health every 5 minutes
Requires=watchtower-health.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
AccuracySec=30sec
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Enable all services
systemctl daemon-reload
systemctl enable --now ecr-login-refresh.timer
systemctl enable --now watchtower-health.timer

echo "✅ All Watchtower services configured and started"

