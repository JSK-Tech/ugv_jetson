#!/usr/bin/env bash
# Start RTAB-Map, OAK-D Lite, D500, and the camera viewer in tracked groups.
set -euo pipefail

CONTAINER="ugv_jetson_ros_humble"
RUNTIME_DIR="/home/jetson/ugv_runtime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RUNTIME_DIR"
"$SCRIPT_DIR/wait-for-lan-time.sh"
"$SCRIPT_DIR/stop-3d-mapping.sh" --quiet

if docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 launch ugv_slam gmapping.launch.py|[s]lam_gmapping' >/dev/null"; then
  echo "A 2D mapping process is still running. Stop it first, then rerun this script." >&2
  exit 1
fi
if docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 launch ugv_slam rtabmap_rgbd.launch.py|[r]tabmap_slam/rtabmap' >/dev/null"; then
  echo "An unmanaged 3D mapping process is still running. Stop it first, then rerun this script." >&2
  exit 1
fi
if pgrep -f '[c]amera_viewer.py' >/dev/null; then
  echo "An unmanaged camera viewer is still running. Stop it first, then rerun this script." >&2
  exit 1
fi
if docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 run ugv_tools keyboard_ctrl' >/dev/null"; then
  echo "An existing keyboard controller is still running. Stop it first, then rerun this script." >&2
  exit 1
fi

docker exec -d "$CONTAINER" /usr/bin/setsid /bin/bash -lc '
  source /opt/ros/humble/setup.bash
  source /home/ws/ugv_ws/install/setup.bash
  export UGV_MODEL=ugv_rover
  export LDLIDAR_MODEL=ld19
  exec ros2 launch ugv_slam rtabmap_rgbd.launch.py use_rviz:=false > /tmp/ugv_rtabmap.log 2>&1
'

sleep 8
MAP_PID="$(docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 launch ugv_slam rtabmap_rgbd.launch.py' | tail -n 1")"
if [[ -z "$MAP_PID" ]]; then
  echo "3D mapping launch did not start. See /tmp/ugv_rtabmap.log in the container." >&2
  exit 1
fi
printf '%s\n' "$MAP_PID" > "$RUNTIME_DIR/3d-mapping.pid"

/usr/bin/setsid /home/jetson/ugv_jetson/ugv-env/bin/python \
  /home/jetson/ugv_jetson/camera_viewer.py \
  > /home/jetson/ugv_camera_viewer.log 2>&1 < /dev/null &
CAMERA_PID="$!"
printf '%s\n' "$CAMERA_PID" > "$RUNTIME_DIR/camera-viewer.pid"

sleep 7
if ! docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]tabmap_slam/rtabmap' >/dev/null" || \
   ! curl --fail --silent http://127.0.0.1:5001/health >/dev/null || \
   ! curl --fail --silent http://127.0.0.1:5002/health >/dev/null; then
  echo "3D mapping startup checks failed. See /tmp/ugv_rtabmap.log and /home/jetson/ugv_camera_viewer.log." >&2
  "$SCRIPT_DIR/stop-3d-mapping.sh" --quiet
  exit 1
fi

echo "3D mapping started (container process group: $MAP_PID, camera viewer: $CAMERA_PID)."
