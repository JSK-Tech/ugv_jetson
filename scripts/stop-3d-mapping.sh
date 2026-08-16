#!/usr/bin/env bash
# Stop only processes created by start-3d-mapping.sh, then verify termination.
set -euo pipefail

CONTAINER="ugv_jetson_ros_humble"
RUNTIME_DIR="/home/jetson/ugv_runtime"
QUIET="${1:-}"

stop_container_group() {
  local pid="$1"
  if docker exec "$CONTAINER" kill -0 "$pid" 2>/dev/null; then
    docker exec "$CONTAINER" kill -TERM -- "-$pid" 2>/dev/null || docker exec "$CONTAINER" kill -TERM "$pid"
    for _ in {1..10}; do
      sleep 1
      docker exec "$CONTAINER" kill -0 "$pid" 2>/dev/null || return 0
    done
    docker exec "$CONTAINER" kill -KILL -- "-$pid" 2>/dev/null || docker exec "$CONTAINER" kill -KILL "$pid" 2>/dev/null || true
  fi
}

stop_host_group() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid"
    for _ in {1..5}; do
      sleep 1
      kill -0 "$pid" 2>/dev/null || return 0
    done
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  fi
}

if [[ -f "$RUNTIME_DIR/camera-viewer.pid" ]]; then
  stop_host_group "$(<"$RUNTIME_DIR/camera-viewer.pid")"
  rm -f "$RUNTIME_DIR/camera-viewer.pid"
fi
if [[ -f "$RUNTIME_DIR/3d-mapping.pid" ]]; then
  stop_container_group "$(<"$RUNTIME_DIR/3d-mapping.pid")"
  rm -f "$RUNTIME_DIR/3d-mapping.pid"
fi
if [[ "$QUIET" != "--quiet" ]]; then
  echo "Tracked 3D mapping and camera viewer processes have been stopped."
  echo "Run status-ugv-runtime.sh to check for unmanaged legacy processes."
fi
