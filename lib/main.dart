import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'services/ai_auth_service.dart';
import 'services/firebase_service.dart';
import 'services/serial_service.dart';
import 'state/kiosk_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/error_overlay.dart';
import 'widgets/kiosk_frame.dart';
import 'widgets/service_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nothing before runApp() may throw. If it does, the window opens but
  // nothing is ever drawn — which looks exactly like "built fine, not
  // showing". Every startup step is therefore isolated; a failure degrades
  // the kiosk to its out-of-service screen instead of a blank panel.
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (e) {
    debugPrint('[boot] system chrome setup failed: $e');
  }

  // Firestore/Auth via firedart (pure Dart, works on Linux). Best-effort:
  // stock is unknown without it, so the kiosk will not take money.
  try {
    FirebaseService.initialize();
  } catch (e) {
    debugPrint('[boot] Firebase init failed: $e');
  }

  final serial = SerialService();
  final aiAuth = AiAuthService();
  final firebase = FirebaseService(kioskId: AppConfig.kioskId);

  final controller = KioskController(
    serial: serial,
    aiAuth: aiAuth,
    firebase: firebase,
  );
  try {
    await controller.initialize().timeout(const Duration(seconds: 20));
  } catch (e, st) {
    debugPrint('[boot] controller init failed or timed out: $e\n$st');
  }

  runApp(CoinvertKioskApp(controller: controller));
}

class CoinvertKioskApp extends StatelessWidget {
  final KioskController controller;
  const CoinvertKioskApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<KioskController>.value(
      value: controller,
      child: MaterialApp(
        title: 'Coinvert',
        debugShowCheckedModeBanner: false,
        theme: buildKioskTheme(),
        // A kiosk has one fixed panel and no accessibility settings UI, so
        // the OS text scale is pinned. Without this, a scale factor left set
        // on the image would overflow every fixed-height row on the panel.
        builder: (context, child) => MediaQuery.withNoTextScaling(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const KioskScreen(),
      ),
    );
  }
}

class KioskScreen extends StatelessWidget {
  const KioskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Any touch anywhere counts as activity for the idle watchdog, so the
      // countdown can't expire on someone who is mid-way through reading
      // their options.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => controller.registerInteraction(),
        child: SafeArea(
          child: Stack(
            children: const [
              // Fills the panel. The old build letterboxed everything into a
              // fixed 620×372 box — a mockup artifact that wasted most of a
              // real kiosk display.
              Positioned.fill(child: KioskFrame()),
              Positioned.fill(child: ErrorOverlay()),
              ServicePanelGate(),
            ],
          ),
        ),
      ),
    );
  }
}
