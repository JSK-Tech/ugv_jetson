#!/usr/bin/env bash
set -euo pipefail

timeout_seconds="${1:-120}"
deadline=$((SECONDS + timeout_seconds))

while (( SECONDS < deadline )); do
  if [[ "$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]; then
    echo "Time synchronized: $(date --iso-8601=seconds)"
    exit 0
  fi
  sleep 2
done

echo "Timed out after ${timeout_seconds}s waiting for NTP synchronization from 192.168.50.1." >&2
exit 1
