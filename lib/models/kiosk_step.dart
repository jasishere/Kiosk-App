/// The kiosk flow steps — mirrors the `steps` array in the original JS mockup.
enum KioskStep {
  welcome,
  modeSelect,
  insertCash,
  authenticating,
  selectOutput,
  dispensing,
  complete,
}

extension KioskStepX on KioskStep {
  String get label {
    switch (this) {
      case KioskStep.welcome:
        return 'Welcome';
      case KioskStep.modeSelect:
        return 'Mode select';
      case KioskStep.insertCash:
        return 'Insert cash';
      case KioskStep.authenticating:
        return 'Authenticating';
      case KioskStep.selectOutput:
        return 'Select output';
      case KioskStep.dispensing:
        return 'Dispensing';
      case KioskStep.complete:
        return 'Complete';
    }
  }
}
