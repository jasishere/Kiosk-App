import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/kiosk_step.dart';
import '../app_config.dart';
import '../models/denomination.dart';
import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// Hidden trigger for the on-site service panel.
///
/// This replaces the simulation debug panel, which drove fake Arduino events
/// into the controller. That was the right tool for developing without
/// hardware and exactly the wrong thing to ship: it could fabricate
/// transactions, and it was gated only on a compile-time flag that anyone
/// could ship in the wrong position.
///
/// What an attendant standing at the machine actually needs is the opposite
/// — a read-only view of why it is behaving the way it is. The trigger is an
/// unmarked 3-second press in the top-left corner, then a PIN.
class ServicePanelGate extends StatelessWidget {
  const ServicePanelGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      width: 88,
      height: 88,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _promptForPin(context),
        child: const SizedBox.expand(),
      ),
    );
  }

  Future<void> _promptForPin(BuildContext context) async {
    final controller = context.read<KioskController>();
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _PinDialog(),
    );
    if (entered != AppConfig.servicePin) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<KioskController>.value(
        value: controller,
        child: const _ServicePanel(),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _value = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Service access', style: AppText.heading),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _value.replaceAll(RegExp(r'.'), '• '),
              style: AppText.moneySmall.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 1; i <= 9; i++) _key('$i'),
                _key('⌫', onTap: () {
                  if (_value.isNotEmpty) {
                    setState(
                        () => _value = _value.substring(0, _value.length - 1));
                  }
                }),
                _key('0'),
                _key('✓', onTap: () => Navigator.of(context).pop(_value)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _key(String label, {VoidCallback? onTap}) => SizedBox(
        width: 64,
        height: 56,
        child: OutlinedButton(
          onPressed: onTap ?? () => setState(() => _value += label),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: const BorderSide(color: AppColors.hairline),
          ),
          child: Text(label, style: AppText.bodyStrong),
        ),
      );
}

/// Read-only diagnostics.
///
/// Deliberately cannot move cash. Test dispenses and restocks go through the
/// admin app, where they are attributable to a signed-in person — a control
/// on the kiosk's own panel would be attributable to nobody, behind a PIN
/// that ships in the build configuration.
class _ServicePanel extends StatelessWidget {
  const _ServicePanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpace.xl),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diagnostics', style: AppText.heading),
            const SizedBox(height: AppSpace.lg),
            _Row('Kiosk ID', AppConfig.kioskId),
            _Row('Serial port', AppConfig.serialPort),
            _Row('Controller board',
                controller.hardwareConnected ? 'Connected' : 'Offline'),
            _Row('Note classifier',
                controller.classifierOnline ? 'Online' : 'Offline'),
            _Row('Stock data',
                controller.firebase.inventoryLoaded ? 'Loaded' : 'Unavailable'),
            _Row(
                'Fee',
                controller.firebase.feeEnabled
                    ? '${controller.firebase.feePercent}%'
                    : 'Disabled'),
            _Row('Current step', controller.step.label),
            _Row('Held in machine', peso(controller.amountInserted)),
            const SizedBox(height: AppSpace.md),
            const Divider(color: AppColors.hairline),
            const SizedBox(height: AppSpace.sm),
            Text('Stock on hand', style: AppText.bodyStrong),
            const SizedBox(height: AppSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final slot in kDispenseSlots)
                      _Row(slot.label,
                          '${controller.firebase.availableUnits(slot)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: QuietButton(
                    label: 'Reconnect hardware',
                    onPressed: controller.serial.connect,
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body),
          Text(value, style: AppText.bodyStrong),
        ],
      ),
    );
  }
}
