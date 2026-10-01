class FloodConfig {
  const FloodConfig._();

  static const String blue = 'blue';
  static const String red = 'red';

  static const int minPhones = 2;
  static const int maxPhones = 6;

  static const double countdownSeconds = 3.0;

  static const double briefingSeconds = 3.0;

  static const double preRoundSeconds = briefingSeconds + countdownSeconds;

  static const double maxRoundLength = 45.0;

  static const double winAt = 1.0;

  static const double basePush = 1.0 / 20;

  static const double minTapIntervalSeconds = 0.04;

  static const int colorBlue = 0xFF2F6FED;
  static const int colorRed = 0xFFED4B2F;
}

class FloodGrowingConfig {
  const FloodGrowingConfig._();

  static const double rampWindow = 15.0;
}
