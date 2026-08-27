#!/bin/sh
set -eu

export DEBIAN_FRONTEND=noninteractive

# Update system and install base tools
apt-get -y update
apt-get -y install curl git make bash unattended-upgrades
apt-get -y upgrade

# Install Docker
curl -fsSL https://get.docker.com | sh

# Enable automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Clone the repository
REPO_URL="${REPO_URL:-https://github.com/Vectorfield4/pi-deploy.git}"
cd /root
if [ -d pi-deploy/.git ]; then
  echo "[cloud-init] pi-deploy already exists — pulling latest"
  git -C pi-deploy pull
else
  git clone "$REPO_URL" pi-deploy
fi
cd /root/pi-deploy

# Create directories + .env from template
make init

# Daily backup at 02:00. Cron runs a bare environment, so source .env
# first so scripts/backup.sh sees POSTGRES_PASSWORD.
( crontab -l 2>/dev/null | grep -v 'pi-deploy && make backup' || true
  echo "0 2 * * * set -a; . /root/pi-deploy/.env; set +a; cd /root/pi-deploy && make backup" ) | crontab -

echo "=================================================="
echo "System is ready!"
echo ""
echo "Next steps via SSH:"
echo "  1. Fill in .env with your secrets"
echo "  2. Run: cd /root/pi-deploy && make setup"
echo "  3. Check logs: make logs"
echo "=================================================="

# A kernel upgrade may need a reboot. Uncomment to reboot automatically
# (cloud-init finishes first):
# reboot