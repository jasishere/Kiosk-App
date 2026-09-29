# Coinvert Kiosk — Flutter app

Production rewrite of the kiosk UI + transaction logic. Start here:

1. `docs/HARDWARE.md` — the serial protocol, BOM, wiring notes, and the
   TFT/keypad vs. touchscreen discrepancy that needs resolving before final
   assembly. Read this before touching firmware or hardware.
2. `firmware/coinvert_firmware.ino` — reference Arduino sketch implementing
   that protocol. Pin numbers and timeouts are placeholders — tune to your
   actual build.
3. `lib/` — the Flutter app. `flutter analyze` has NOT been run on this
   (no Dart toolchain was available while writing it) — expect to fix some
   compile errors on first build.
4. `test/change_planner_test.dart` — run this first. It's the exact-change
   solver that guarantees the kiosk never silently under-pays a customer;
   it's validated against a brute-force solver over hundreds of randomised
   cases in-test.

## Before you build

- Copy your real `lib/firebase_options.dart` over the one here if it's not
  already yours (this one was carried over unchanged from your upload).
- Add your brand artwork to `assets/` (see assets/README.md).
- Resolve the TFT+keypad vs. touchscreen question in HARDWARE.md §5.
- Wire the second (coin) photo-interrupter sensor — this build assumes it
  exists; see HARDWARE.md §2.

## Build

    flutter pub get
    flutter analyze
    flutter test
    flutter build linux --release \
      --dart-define=KIOSK_ID=kiosk-01 \
      --dart-define=SERIAL_PORT=/dev/ttyACM0 \
      --dart-define=AI_BASE_URL=http://127.0.0.1:8000
