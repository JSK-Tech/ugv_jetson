#!/usr/bin/env bash
# Start the 2D mapping launch and camera viewer in separately tracked groups.
set -euo pipefail

CONTAINER="ugv_jetson_ros_humble"
RUNTIME_DIR="/home/jetson/ugv_runtime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RUNTIME_DIR"
"$SCRIPT_DIR/wait-for-lan-time.sh"
"$SCRIPT_DIR/stop-2d-mapping.sh" --quiet

if docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 launch ugv_slam gmapping.launch.py' >/dev/null"; then
  echo "An unmanaged 2D mapping launch is still running. Stop it first, then rerun this script." >&2
  exit 1
fi
if docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 launch ugv_slam rtabmap_rgbd.launch.py|[r]tabmap_slam/rtabmap' >/dev/null"; then
  echo "A 3D mapping process is still running. Stop it first, then rerun this script." >&2
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
  exec ros2 launch ugv_slam gmapping.launch.py use_rviz:=false > /tmp/ugv_gmapping.log 2>&1
'

sleep 3
MAP_PID="$(docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]os2 launch ugv_slam gmapping.launch.py' | tail -n 1")"
if [[ -z "$MAP_PID" ]]; then
  echo "2D mapping launch did not start. See /tmp/ugv_gmapping.log in the container." >&2
  exit 1
fi
printf '%s\n' "$MAP_PID" > "$RUNTIME_DIR/2d-mapping.pid"

/usr/bin/setsid /home/jetson/ugv_jetson/ugv-env/bin/python \
  /home/jetson/ugv_jetson/camera_viewer.py \
  > /home/jetson/ugv_camera_viewer.log 2>&1 < /dev/null &
CAMERA_PID="$!"
printf '%s\n' "$CAMERA_PID" > "$RUNTIME_DIR/camera-viewer.pid"

sleep 3
if ! curl --fail --silent http://127.0.0.1:5001/health >/dev/null; then
  echo "Camera viewer did not become ready. See /home/jetson/ugv_camera_viewer.log." >&2
  exit 1
fi
if ! curl --fail --silent http://127.0.0.1:5002/health >/dev/null; then
  echo "ROS2 gimbal bridge did not become ready. See /tmp/ugv_gmapping.log." >&2
  exit 1
fi

echo "2D mapping started (container process group: $MAP_PID, camera viewer: $CAMERA_PID)."
