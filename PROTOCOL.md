# Coinvert Serial Protocol — Raspberry Pi 5 ⇄ Arduino Mega

Transport: USB serial (Arduino Mega shows up as `/dev/ttyACM0` or
`/dev/ttyUSB0` on the Pi). Baud rate: **115200**. Line-based ASCII,
each message terminated with `\n`. Every message is a single line —
no multi-line payloads.

This keeps the Arduino's job purely mechanical/electrical (reading
sensors, driving motors) and keeps all decision-making (AI auth,
transaction logic, Firebase) on the Pi side, matching the thesis's
architecture (Raspberry Pi 5 = orchestration, Arduino Mega = real-time
hardware control).

## Message format

```
<TYPE>:<field1>:<field2>:...
```

All values are plain integers/strings, colon-delimited, no spaces.

## Arduino → Pi (events)

| Message | Meaning | Example |
|---|---|---|
| `COIN:<value>` | Coin accepted by coin selector, value in pesos | `COIN:5` |
| `BILL:<value>` | Bill accepted by TB74 acceptor (pre-AI, sensor-level denom guess) | `BILL:100` |
| `BILL_REJECTED` | TB74 rejected the note (basic sensor check failed) | `BILL_REJECTED` |
| `BILL_STAGED` | Bill physically staged in front of camera, ready for UV/AI capture | `BILL_STAGED` |
| `DISPENSE_ITEM:<type>:<denom>` | One item successfully dispensed (photo-interrupter confirmed) | `DISPENSE_ITEM:BILL:100` |
| `DISPENSE_DONE` | Full dispense batch complete | `DISPENSE_DONE` |
| `DISPENSE_JAM:<type>:<denom>` | Jam detected on a specific dispenser | `DISPENSE_JAM:COIN:5` |
| `SENSOR_JAM:<component>` | General jam/fault (transport path, hopper, etc.) | `SENSOR_JAM:TRANSPORT` |
| `ERROR:<code>:<message>` | Hardware-level error | `ERROR:E01:Coin hopper empty` |
| `KEYPAD:<key>` | Membrane keypad press (if used for input alongside touchscreen) | `KEYPAD:3` |
| `HEARTBEAT` | Sent every 2s so the Pi can detect a disconnected/frozen Arduino | `HEARTBEAT` |
| `READY` | Sent once on boot after Arduino self-test passes | `READY` |

## Pi → Arduino (commands)

| Message | Meaning | Example |
|---|---|---|
| `UV:ON` / `UV:OFF` | Enable/disable the 365nm UV LED for authentication capture | `UV:ON` |
| `CAPTURE_ACK` | Tells Arduino the Pi's camera has captured the frame it needs (Arduino can retract UV / move bill onward) | `CAPTURE_ACK` |
| `ACCEPT_BILL` | AI authentication passed — allow the staged bill to be accepted into the vault | `ACCEPT_BILL` |
| `REJECT_BILL` | AI authentication failed — return the staged bill to the user | `REJECT_BILL` |
| `DISPENSE:BILL:<denom>:<count>` | Dispense `count` bills of `denom` | `DISPENSE:BILL:100:2` |
| `DISPENSE:COIN:<denom>:<count>` | Dispense `count` coins of `denom` | `DISPENSE:COIN:5:4` |
| `RESET` | Reset all actuators to idle/home position (used on error recovery or transaction cancel) | `RESET` |
| `PING` | Liveness check — Arduino should reply `PONG` | `PING` |

## Typical transaction sequence (Pabarya / breakdown mode)

```
Pi  → RESET
Ard → READY
...user inserts a ₱100 bill...
Ard → BILL:100
Ard → BILL_STAGED
Pi  → UV:ON
...Pi camera captures frame, runs local AI auth call...
Pi  → CAPTURE_ACK
Pi  → UV:OFF
  (AI result: authentic)
Pi  → ACCEPT_BILL
...user confirms output mix, e.g. 5x ₱20...
Pi  → DISPENSE:BILL:20:5
Ard → DISPENSE_ITEM:BILL:20
Ard → DISPENSE_ITEM:BILL:20
Ard → DISPENSE_ITEM:BILL:20
Ard → DISPENSE_ITEM:BILL:20
Ard → DISPENSE_ITEM:BILL:20
Ard → DISPENSE_DONE
```

If AI auth fails instead:
```
Pi  → REJECT_BILL
```

## Error handling notes

- If no `HEARTBEAT` is received for >5s, the Pi should show a
  "Kiosk temporarily unavailable" screen and attempt to reopen the
  serial port.
- `SENSOR_JAM:*` / `DISPENSE_JAM:*` should pause the transaction,
  show an error screen, and log the event to Firebase
  (`kiosk_errors` collection) for maintenance alerts — this matches
  the thesis's non-functional requirement for error logging and
  admin alerting.
- Any unrecognized line from the Arduino should be logged but not
  crash the app (forward-compatible parsing).
