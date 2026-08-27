#!/bin/sh

# Update the system
apt-get -y update
apt-get -y upgrade

# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Git, Make, unattended-upgrades
apt-get -y install git make unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Clone the repository
REPO_URL="${REPO_URL:-https://github.com/Vectorfield4/pi-deploy.git}"
cd /root
git clone "$REPO_URL" pi-deploy
cd pi-deploy

# Create directories + .env from template
make init

# Set up a daily backup at 02:00
(crontab -l 2>/dev/null | grep -v 'make backup'; echo "0 2 * * * cd /root/pi-deploy && make backup") | crontab -

echo "=================================================="
echo "System is ready!"
echo ""
echo "Next steps via SSH:"
echo "  1. Fill in .env with your secrets"
echo "  2. Run: cd /root/pi-deploy && make setup"
echo "  3. Check logs: make logs"
echo "=================================================="
