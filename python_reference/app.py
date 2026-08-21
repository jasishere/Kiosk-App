"""
Coinvert AI Authentication Service — reference stub.

Runs on the Raspberry Pi 5 alongside the Flutter kiosk app. Owns the
Raspberry Pi Camera Module V3 and drives the banknote authentication
pipeline described in the thesis: UV-fluorescence capture (365nm LED,
triggered by the Arduino over serial before this service is called)
+ YOLOv8 classification via OpenCV.

This file is a STUB — it wires up the HTTP contract that
lib/services/ai_auth_service.dart expects, with a placeholder
classifier you should replace with your trained YOLOv8 model. Swap
`run_classifier()` with your real Roboflow-trained model inference and
this becomes the real service without touching the Flutter side.

Run:
    pip install flask opencv-python picamera2 ultralytics
    python app.py

Endpoints:
    GET  /health          -> {"status": "ok"}
    POST /authenticate     -> {"authentic": bool, "denomination": int, "confidence": float}
"""

from flask import Flask, jsonify
import time
import random  # placeholder only — remove once real model is wired in

app = Flask(__name__)

# --- Replace this block with real camera + model setup -------------------
# from picamera2 import Picamera2
# from ultralytics import YOLO
#
# camera = Picamera2()
# camera.start()
# model = YOLO("weights/coinvert_banknote_yolov8.pt")
# ---------------------------------------------------------------------------


def capture_frame():
    """
    Capture a single frame from the Pi Camera Module V3 while the UV LED
    is on (the Arduino has already been told UV:ON by the Flutter app
    before this endpoint is called — see PROTOCOL.md).

    Replace with real capture, e.g.:
        frame = camera.capture_array()
        return frame
    """
    time.sleep(0.3)  # simulate capture latency
    return None  # placeholder


def run_classifier(frame):
    """
    Run the trained YOLOv8 model (via OpenCV/ultralytics) on the captured
    frame and return (authentic: bool, denomination: int|None, confidence: float).

    Replace with real inference, e.g.:
        results = model.predict(frame)
        best = results[0].boxes[0]
        denom = CLASS_TO_DENOM[int(best.cls)]
        confidence = float(best.conf)
        authentic = confidence >= AUTH_THRESHOLD
        return authentic, denom, confidence
    """
    time.sleep(0.5)  # simulate inference latency
    # Placeholder logic — replace entirely.
    authentic = random.random() > 0.1
    denom = random.choice([20, 50, 100, 200, 500, 1000])
    confidence = round(random.uniform(0.85, 0.99), 3)
    return authentic, denom, confidence


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/authenticate", methods=["POST"])
def authenticate():
    frame = capture_frame()
    authentic, denom, confidence = run_classifier(frame)
    return jsonify(
        {
            "authentic": authentic,
            "denomination": denom,
            "confidence": confidence,
        }
    )


if __name__ == "__main__":
    # Bind to localhost only — this service should never be reachable
    # from outside the kiosk's own Raspberry Pi.
    app.run(host="127.0.0.1", port=8000)
