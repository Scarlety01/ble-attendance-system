class RssiUtils {
  static double estimateDistance({
    required int rssi,
    int txPower = -59,
    double n = 2.0,
  }) {
    final exponent = (txPower - rssi) / (10 * n);
    return double.parse(pow10(exponent).toStringAsFixed(2));
  }

  static double adaptiveThresholdDistance(int rssi) {
    if (rssi >= -60) return 2.0;
    if (rssi >= -70) return 3.0;
    return 4.0;
  }

  static double pow10(double exponent) {
    return exponent == 0 ? 1.0 : _exp(exponent * 2.302585092994046);
  }

  static double _exp(double x) {
    double sum = 1.0;
    double term = 1.0;
    for (int i = 1; i < 30; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }
}
