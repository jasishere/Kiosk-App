import 'package:flutter/material.dart';
import '../services/serial_service.dart';
import '../services/ai_auth_service.dart';

/// Floating panel with buttons that fire simulated Arduino/AI events —
/// only meant to be shown when SerialService/AiAuthService were built with
/// `simulate: true`. Lets you exercise the full insert-cash → authenticate
/// → dispense flow with no Pi, Arduino, or Python service running.
class SimDebugPanel extends StatelessWidget {
  final SerialService serial;
  final AiAuthService aiAuth;
  const SimDebugPanel({super.key, required this.serial, required this.aiAuth});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      bottom: 8,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _btn('₱5 coin', () => serial.simulateCoin(5)),
              _btn('₱20 coin', () => serial.simulateCoin(20)),
              _btn('Insert ₱100 (ok)', () {
                aiAuth.nextSimulatedResult =
                    AuthResult(authentic: true, denomination: 100, confidence: 0.97);
                serial.simulateBillStaged();
              }),
              _btn('Insert bill (fail)', () {
                aiAuth.nextSimulatedResult =
                    AuthResult(authentic: false, denomination: 500, confidence: 0.42);
                serial.simulateBillStaged();
              }),
              _btn('Insert bill (borderline)', () {
                aiAuth.nextSimulatedResult =
                    AuthResult(authentic: false, denomination: 200, confidence: 0.71);
                serial.simulateBillStaged();
              }),
              _btn('Dispense done', serial.simulateDispenseDone),
              _btn('Jam', serial.simulateJam),
              _btn('HW error', () => serial.simulateHardwareError('SIM fault')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: Text(label),
      );
}
