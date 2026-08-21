# Coinvert Kiosk — Flutter (production build)

Real, hardware-driven kiosk app matching your thesis architecture:

```
┌─────────────────────────┐      serial (115200 baud)     ┌──────────────┐
│  Raspberry Pi 5          │ ─────────────────────────────▶│ Arduino Mega │
│  - Flutter kiosk UI      │◀───────────────────────────── │ (bill/coin,  │
│  - KioskController       │        events (COIN, BILL,    │  motors,     │
│    (lib/state/)          │        DISPENSE_DONE, ...)     │  sensors)    │
│                          │                                └──────────────┘
│  ── HTTP (localhost) ──▶ │
│  Python/OpenCV service   │
│  (python_reference/)     │
│  YOLOv8 banknote auth    │
└─────────────────────────┘
            │
            ▼ Firestore / Auth
       Firebase (cloud)
```

## Project layout

```
lib/
  main.dart                  // app entry, wires services + controller
  theme/colors.dart
  models/kiosk_step.dart
  services/
    serial_service.dart      // Arduino Mega serial I/O
    ai_auth_service.dart     // calls local Python AI service
    firebase_service.dart    // transaction/error logging, admin auth
  state/
    kiosk_controller.dart    // the real state machine — start here
  widgets/
    kiosk_frame.dart
    error_overlay.dart
    logo_badge.dart
    buttons.dart
  screens/                   // one file per kiosk screen
assets/
  coinvert_logo.png
python_reference/
  app.py                     // stub AI service — replace run_classifier()
PROTOCOL.md                  // Arduino <-> Pi serial message spec
pubspec.yaml
```

## Setup

### 1. Flutter deps
```bash
flutter pub get
```

### 2. Firebase
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```
This generates `lib/firebase_options.dart`. Then in `lib/main.dart`,
uncomment:
```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```
and delete the bare `await Firebase.initializeApp();` fallback below it.

In the Firebase console:
- Enable **Firestore** (the app writes to `kiosks/{kioskId}/transactions`
  and `kiosks/{kioskId}/errors`).
- Enable **Authentication → Email/Password** and create your admin
  account(s) — `FirebaseService.adminSignIn()` is ready for a companion
  admin dashboard app to use.
- Set `kKioskId` in `main.dart` to a unique ID per physical kiosk.

### 3. Arduino Mega
Flash your Arduino Mega with firmware that speaks the protocol in
**PROTOCOL.md** — it's the messages `SerialService` already sends and
listens for. That file is the contract; the Arduino sketch itself isn't
included here since it depends on your exact pin mapping for the
TB74 bill acceptor, coin selector, servo, stepper, and sensors from your
hardware section.

Confirm the port: on the Pi, run `dmesg | grep tty` after plugging in
the Mega, then set `SerialService(portName: '/dev/ttyACM0')` (or
whatever it enumerates as) in `main.dart`.

### 4. Python AI authentication service
```bash
cd python_reference
pip install flask opencv-python picamera2 ultralytics
python app.py
```
This stub returns randomized results so you can test the full Flutter
flow today. Replace `capture_frame()` and `run_classifier()` with your
real Pi Camera V3 capture and trained YOLOv8 model (trained via
Roboflow + Google Colab per your methodology) — the HTTP contract
Flutter expects won't change.

Run it as a systemd service on the Pi so it starts on boot alongside
the kiosk app.

### 5. Run the kiosk app
```bash
flutter run -d linux    # or your Pi's configured device
```

## What's real vs. what's still a stub

| Piece | Status |
|---|---|
| Kiosk UI (7 screens) | Real, pixel-matched to your mockup |
| State machine (`KioskController`) | Real — driven by serial events, not buttons |
| Arduino serial protocol | Defined (PROTOCOL.md) — you still need to flash matching firmware |
| AI authentication call | Real HTTP contract — `run_classifier()` in the Python stub needs your trained model |
| Firebase logging | Real — needs your Firebase project connected via `flutterfire configure` |
| Custom mix picker (denomination selection UI) | **Not built** — "Quick mix" (greedy breakdown) works; custom mix currently shows a placeholder message |
| Admin dashboard | Not built — `FirebaseService` and `adminSignIn()` are ready for one |
| Low-inventory awareness on kiosk itself | Service method exists (`watchInventory`) but no screen consumes it yet |

## Next steps I'd suggest

1. Flash the Arduino Mega and test the serial link with the app's
   status-bar hardware icon (turns red on disconnect).
2. Get your trained YOLOv8 weights into `python_reference/app.py` and
   confirm the HTTP round-trip end to end with a real bill.
3. Build the custom-mix denomination picker (bottom sheet suggested).
4. Build a companion admin dashboard (could be a second Flutter target
   using the same `FirebaseService`).
