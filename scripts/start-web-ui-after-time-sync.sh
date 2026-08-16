#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pulseaudio --start || true
"$SCRIPT_DIR/wait-for-lan-time.sh" 180

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
exec /home/jetson/ugv_jetson/ugv-env/bin/python /home/jetson/ugv_jetson/app.py
