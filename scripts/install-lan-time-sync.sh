#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with: sudo $0"
  exit 1
fi

install -d -m 0755 /etc/systemd/timesyncd.conf.d
cat > /etc/systemd/timesyncd.conf.d/ugv-lan.conf <<'EOF'
[Time]
NTP=192.168.50.1
FallbackNTP=
RootDistanceMaxSec=30
EOF

timedatectl set-timezone Asia/Tokyo
timedatectl set-ntp true
systemctl enable systemd-timesyncd.service
systemctl restart systemd-timesyncd.service

echo "LAN time sync is configured. Waiting for 192.168.50.1 after Ethernet is available."
timedatectl status
