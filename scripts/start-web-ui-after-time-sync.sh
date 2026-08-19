#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pulseaudio --start || true

# The operator PC may be connected after the Jetson finishes booting. Keep the
# reboot job alive until LAN NTP has actually synchronized instead of giving up
# after its first timeout.
until "$SCRIPT_DIR/wait-for-lan-time.sh" 180; do
  echo "LAN time is not synchronized yet; retrying Web UI startup in 10 seconds." >&2
  sleep 10
done

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
exec /home/jetson/ugv_jetson/ugv-env/bin/python /home/jetson/ugv_jetson/app.py
