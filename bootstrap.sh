#!/bin/bash
set -e

echo '=== Nexus Bootstrap ==='
echo ''

# 1. Change hostname
echo '[1/3] Changing hostname to nexus...'
sudo hostnamectl set-hostname nexus
sudo sed -i 's/127.0.1.1.*/127.0.1.1\tnexus/' /etc/hosts
echo '    Hostname set to nexus'

# 2. Install Docker
if ! command -v docker &> /dev/null; then
    echo '[2/3] Installing Docker...'
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
    echo '    Docker installed. Group added - will apply after reboot.'
else
    echo '[2/3] Docker already installed'
fi

# 3. Create backups dir and start services
echo '[3/3] Starting Nexus services...'
mkdir -p ~/nexus-setup/backups
cd ~/nexus-setup

# Need to use sudo since user not in docker group yet
sudo docker compose up -d

echo ''
echo '=== Waiting for services to be healthy... ==='
sleep 15

# Check status
sudo docker compose ps

echo ''
echo '=========================================='
echo '  Nexus Deployed Successfully!'
echo '=========================================='
echo ''
echo 'URLs:'
echo '  NocoDB UI:  https://nexus.rfanw'
echo '  Direct:     http://10.0.0.11:8080'
echo ''
echo 'Database:'
echo '  Host: 10.0.0.11:5432'
echo '  User: nexus'
echo '  Pass: (check ~/nexus-setup/.env)'
echo ''
echo 'Next steps:'
echo '  1. Reboot to apply hostname: sudo reboot'
echo '  2. After reboot, run: tailscale set --hostname=nexus'
echo '  3. Open https://nexus.rfanw and create admin account'
echo ''
