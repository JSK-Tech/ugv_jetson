"""Camera viewer and pan/tilt controls for ROS2 mapping."""

import atexit
import threading
import time

import cv2
from flask import Flask, Response, jsonify


HOST = "0.0.0.0"
PORT = 5001
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
JPEG_QUALITY = 70

app = Flask(__name__)


class CameraStream:
    """Own the camera so browser clients never compete for it."""

    def __init__(self):
        self._camera = None
        self._frame = None
        self._lock = threading.Lock()
        self._running = threading.Event()
        self._thread = None

    def start(self):
        if self._thread and self._thread.is_alive():
            return
        self._running.set()
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running.clear()
        if self._thread:
            self._thread.join(timeout=2)
        if self._camera:
            self._camera.release()
            self._camera = None

    def frame(self):
        with self._lock:
            return self._frame

    def _open_camera(self):
        camera = cv2.VideoCapture(-1)
        if not camera.isOpened():
            camera.release()
            camera = cv2.VideoCapture(0)
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        return camera

    def _capture_loop(self):
        while self._running.is_set():
            if not self._camera or not self._camera.isOpened():
                self._camera = self._open_camera()
                if not self._camera.isOpened():
                    time.sleep(1)
                    continue
            ok, image = self._camera.read()
            if not ok:
                self._camera.release()
                self._camera = None
                time.sleep(0.2)
                continue
            ok, encoded = cv2.imencode(
                ".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY]
            )
            if ok:
                with self._lock:
                    self._frame = encoded.tobytes()


camera_stream = CameraStream()
atexit.register(camera_stream.stop)


@app.get("/")
def camera_viewer():
    return """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>UGV Camera</title>
  <style>
    body { margin: 0; background: #101317; color: #e7edf2; font: 16px sans-serif; }
    main { max-width: 960px; margin: 0 auto; padding: 16px; }
    h1 { font-size: 18px; font-weight: 600; margin: 0 0 12px; }
    .video { display: block; width: 100%; height: auto; background: #252b31; }
    .panel { width: 208px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin: 16px auto 0; }
    .panel button { height: 48px; border: 1px solid #5c6975; border-radius: 4px; background: #222a31; color: #f1f5f7; font-size: 24px; cursor: pointer; }
    .panel button:hover { background: #33404b; }
    .panel button:active { background: #4a5a68; }
    .panel .empty { visibility: hidden; }
    .status { grid-column: 1 / -1; margin: 0; color: #aab6c0; font-size: 12px; text-align: center; }
  </style>
</head>
<body>
  <main>
    <h1>UGV Camera</h1>
    <img class="video" src="/video_feed" alt="UGV camera stream">
    <section class="panel" aria-label="Pan tilt controls">
      <span class="empty"></span>
      <button data-pan="0" data-tilt="8" title="Tilt up" aria-label="Tilt up">&uarr;</button>
      <span class="empty"></span>
      <button data-pan="-12" data-tilt="0" title="Pan left" aria-label="Pan left">&larr;</button>
      <button data-pan="0" data-tilt="0" data-home="true" title="Center" aria-label="Center">O</button>
      <button data-pan="12" data-tilt="0" title="Pan right" aria-label="Pan right">&rarr;</button>
      <span class="empty"></span>
      <button data-pan="0" data-tilt="-8" title="Tilt down" aria-label="Tilt down">&darr;</button>
      <span class="empty"></span>
      <p class="status" id="status">ROS2 gimbal: checking...</p>
    </section>
  </main>
  <script>
    const limits = { pan: [-180, 180], tilt: [-30, 90] };
    let pan = 0, tilt = 0, timer = null;
    const status = document.getElementById("status");
    const endpoint = `http://${location.hostname}:5002`;

    async function send(home, deltaPan = 0, deltaTilt = 0) {
      if (home) { pan = 0; tilt = 0; }
      else {
        pan = Math.max(limits.pan[0], Math.min(limits.pan[1], pan + deltaPan));
        tilt = Math.max(limits.tilt[0], Math.min(limits.tilt[1], tilt + deltaTilt));
      }
      try {
        const response = await fetch(`${endpoint}/gimbal?pan=${pan}&tilt=${tilt}&speed=300`, { method: "POST" });
        if (!response.ok) throw new Error("gimbal request failed");
        status.textContent = `Pan ${pan} deg, Tilt ${tilt} deg`;
      } catch (_) {
        status.textContent = "ROS2 gimbal: unavailable";
      }
    }

    function stopRepeat() { clearInterval(timer); timer = null; }
    document.querySelectorAll("button[data-pan]").forEach((button) => {
      const action = () => send(button.dataset.home === "true", Number(button.dataset.pan), Number(button.dataset.tilt));
      button.addEventListener("pointerdown", (event) => {
        event.preventDefault();
        action();
        timer = setInterval(action, 300);
      });
      ["pointerup", "pointerleave", "pointercancel"].forEach((name) => {
        button.addEventListener(name, stopRepeat);
      });
    });
    fetch(`${endpoint}/health`)
      .then((response) => {
        if (!response.ok) throw new Error("bridge unavailable");
        status.textContent = "Pan 0 deg, Tilt 0 deg";
      })
      .catch(() => { status.textContent = "ROS2 gimbal: unavailable"; });
  </script>
</body>
</html>"""


@app.get("/health")
def health():
    return jsonify(camera_ready=camera_stream.frame() is not None)


@app.get("/video_feed")
def video_feed():
    def frames():
        while True:
            frame = camera_stream.frame()
            if frame is None:
                time.sleep(0.1)
                continue
            yield b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + frame + b"\r\n"
            time.sleep(0.01)

    return Response(frames(), mimetype="multipart/x-mixed-replace; boundary=frame")


if __name__ == "__main__":
    camera_stream.start()
    app.run(host=HOST, port=PORT, threaded=True)
