import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/kiosk_step.dart';
import '../screens/authenticating_step.dart';
import '../screens/complete_step.dart';
import '../screens/dispensing_step.dart';
import '../screens/insert_cash_step.dart';
import '../screens/mode_select_step.dart';
import '../screens/out_of_service_step.dart';
import '../screens/select_output_step.dart';
import '../screens/welcome_step.dart';
import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import 'ledger_rail.dart';

/// Outer chrome: a slim status strip, the step content, and — once a
/// transaction is underway — a persistent ledger rail down the right.
///
/// The rail is the structural idea the rest of the layout is built around.
/// Every screen in the old build re-stated the amount in its own way, which
/// meant the customer had to re-find their money on each step. Here it lives
/// in one fixed place from the moment the first coin drops until the cash is
/// in the tray.
class KioskFrame extends StatelessWidget {
  const KioskFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.select<KioskController, KioskStep>((c) => c.step);
    final showLedger = step.isTransactional ||
        step == KioskStep.dispensing ||
        step == KioskStep.complete;

    return Container(
      color: AppColors.canvas,
      child: Column(
        children: [
          const _StatusStrip(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.md,
                AppSpace.xl,
                AppSpace.xl,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _StepBody(step: step)),
                  // Animated width rather than a conditional child: the rail
                  // slides in and out instead of the content jumping sideways
                  // the instant the step changes.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: showLedger
                        ? const Padding(
                            padding: EdgeInsets.only(left: AppSpace.lg),
                            child: LedgerRail(),
                          )
                        : const SizedBox(height: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clock plus two honest hardware indicators.
///
/// The mockup's wifi and battery glyphs are gone: a mains-powered Pi exposes
/// neither to Flutter, so both were decoration that actively misrepresented
/// the machine's state. What replaces them is the only two things an
/// attendant walking past actually needs to see.
class _StatusStrip extends StatefulWidget {
  const _StatusStrip();

  @override
  State<_StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<_StatusStrip> {
  late DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Ticks on the minute boundary rather than every second — the display
    // only shows hours and minutes, so a 1 Hz setState was rebuilding the
    // strip sixty times for every visible change.
    _scheduleTick();
  }

  void _scheduleTick() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 1));
    _clock = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m ${_now.hour < 12 ? 'am' : 'pm'}';
  }

  @override
  Widget build(BuildContext context) {
    final hardware =
        context.select<KioskController, bool>((c) => c.hardwareConnected);
    final classifier =
        context.select<KioskController, bool>((c) => c.classifierOnline);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_timeLabel, style: AppText.caption),
          Row(
            children: [
              _Indicator(
                icon: Icons.developer_board,
                ok: hardware,
                okLabel: 'Hardware connected',
                badLabel: 'Hardware offline',
              ),
              const SizedBox(width: AppSpace.md),
              _Indicator(
                icon: Icons.center_focus_strong,
                ok: classifier,
                okLabel: 'Note checking online',
                badLabel: 'Note checking offline — coins only',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  final IconData icon;
  final bool ok;
  final String okLabel;
  final String badLabel;

  const _Indicator({
    required this.icon,
    required this.ok,
    required this.okLabel,
    required this.badLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ok ? okLabel : badLabel,
      child: Icon(
        icon,
        size: 17,
        color: ok ? AppColors.textMuted : AppColors.danger,
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  final KioskStep step;
  const _StepBody({required this.step});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // Motion that answers the customer's action: content rises slightly as
      // it arrives. No scale — combining fade, slide and scale on every step
      // reads as a transition effect rather than a response.
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(step), child: _widgetFor(step)),
    );
  }

  Widget _widgetFor(KioskStep step) => switch (step) {
        KioskStep.welcome => const WelcomeStep(),
        KioskStep.modeSelect => const ModeSelectStep(),
        KioskStep.insertCash => const InsertCashStep(),
        KioskStep.authenticating => const AuthenticatingStep(),
        KioskStep.selectOutput => const SelectOutputStep(),
        KioskStep.dispensing => const DispensingStep(),
        KioskStep.complete => const CompleteStep(),
        KioskStep.outOfService => const OutOfServiceStep(),
      };
}
