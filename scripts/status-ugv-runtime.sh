#!/usr/bin/env bash
# Report managed processes and detect known legacy processes without stopping them.
set -euo pipefail

CONTAINER="ugv_jetson_ros_humble"
RUNTIME_DIR="/home/jetson/ugv_runtime"

echo "Managed runtime PID files:"
for file in "$RUNTIME_DIR/2d-mapping.pid" "$RUNTIME_DIR/3d-mapping.pid" "$RUNTIME_DIR/camera-viewer.pid"; do
  if [[ -f "$file" ]]; then
    echo "  $(basename "$file"): $(<"$file")"
  else
    echo "  $(basename "$file"): none"
  fi
done

echo ""
echo "Mapping launch processes in container:"
docker exec "$CONTAINER" /bin/bash -lc "pgrep -af '[r]os2 launch ugv_slam gmapping.launch.py' || true"
docker exec "$CONTAINER" /bin/bash -lc "pgrep -af '[r]os2 launch ugv_slam rtabmap_rgbd.launch.py|[s]lam_gmapping|[r]tabmap_slam/rtabmap' || true"

echo ""
if docker exec "$CONTAINER" /bin/bash -lc "pgrep -f '[r]tabmap_slam/rtabmap' >/dev/null"; then
  echo "3D input topic publishers:"
  docker exec "$CONTAINER" /bin/bash -lc '
    source /opt/ros/humble/setup.bash
    source /home/ws/ugv_ws/install/setup.bash
    for topic in /oak/rgb/image_rect /oak/stereo/image_raw /scan; do
      printf "  %s: " "$topic"
      ros2 topic info "$topic" 2>/dev/null | awk "/Publisher count:/ { print \$3 }"
    done
  '
  echo ""
fi

echo "Keyboard controller processes in container:"
docker exec "$CONTAINER" /bin/bash -lc "pgrep -af '[r]os2 run ugv_tools keyboard_ctrl' || true"

echo ""
echo "Camera viewer processes on Jetson:"
pgrep -af '[c]amera_viewer.py' || true

echo ""
echo "Service health:"
curl --fail --silent http://127.0.0.1:5001/health || true
echo ""
curl --fail --silent http://127.0.0.1:5002/health || true
echo ""
