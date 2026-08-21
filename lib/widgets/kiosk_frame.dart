import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../models/kiosk_step.dart';
import '../state/kiosk_controller.dart';
import '../screens/welcome_step.dart';
import '../screens/mode_select_step.dart';
import '../screens/insert_cash_step.dart';
import '../screens/authenticating_step.dart';
import '../screens/select_output_step.dart';
import '../screens/dispensing_step.dart';
import '../screens/complete_step.dart';

/// The device frame: status bar (clock/wifi/battery) + content area.
/// Reads the current step from KioskController — no local nav state.
class KioskFrame extends StatelessWidget {
  const KioskFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.select<KioskController, KioskStep>((c) => c.step);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.screenBg, AppColors.greenTint.withValues(alpha: 0.35)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.screenBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _StatusBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 22),
              child: _StepBody(step: step),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live status bar — everything shown here comes from real
/// KioskController/system state, not placeholders. WiFi and battery
/// icons from the original mockup were removed: a Pi-powered kiosk on
/// mains power with no OS-level wifi signal exposed to Flutter has no
/// real value to show for either, and faking them was actively
/// misleading about the device's actual state.
class _StatusBar extends StatefulWidget {
  const _StatusBar();

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  late DateTime _now = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final hardwareOk =
        context.select<KioskController, bool>((c) => c.hardwareConnected);
    final aiOk =
        context.select<KioskController, bool>((c) => c.aiServiceOnline);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _timeLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.statusIcon,
              letterSpacing: 0.4,
            ),
          ),
          Row(
            children: [
              Tooltip(
                message: hardwareOk ? 'Hardware connected' : 'Hardware offline',
                child: Icon(
                  Icons.memory,
                  size: 14,
                  color: hardwareOk ? AppColors.statusIcon : Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: aiOk ? 'AI service online' : 'AI service offline',
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: aiOk ? AppColors.statusIcon : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dispatches to the correct step widget based on real controller state,
/// cross-fading + sliding between them so moving through the transaction
/// flow feels alive rather than snapping instantly step to step.
class _StepBody extends StatelessWidget {
  final KioskStep step;
  const _StepBody({required this.step});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 460),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation);
        final scale = Tween<double>(begin: 0.97, end: 1.0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(step),
        child: _stepWidget(step),
      ),
    );
  }

  Widget _stepWidget(KioskStep step) {
    switch (step) {
      case KioskStep.welcome:
        return const WelcomeStep();
      case KioskStep.modeSelect:
        return const ModeSelectStep();
      case KioskStep.insertCash:
        return const InsertCashStep();
      case KioskStep.authenticating:
        return const AuthenticatingStep();
      case KioskStep.selectOutput:
        return const SelectOutputStep();
      case KioskStep.dispensing:
        return const DispensingStep();
      case KioskStep.complete:
        return const CompleteStep();
    }
  }
}
