#!/usr/bin/env bash
set -euo pipefail

# Run from a terminal opened on the Jetson HDMI desktop, not through SSH.
if [[ -z "${DISPLAY:-}" ]]; then
  echo "ERROR: DISPLAY is not set. Run this from the Jetson HDMI desktop terminal, not SSH."
  exit 1
fi

if ! command -v xhost >/dev/null 2>&1; then
  echo "ERROR: xhost is not installed. Install the x11-xserver-utils package on the Jetson host."
  exit 1
fi

xhost +SI:localuser:root
echo "Container GUI access is enabled for local root."
