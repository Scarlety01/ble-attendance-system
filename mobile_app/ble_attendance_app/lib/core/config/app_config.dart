class BeaconTarget {
  final String beaconUuid;
  final String? major;
  final String? minor;
  final String sessionId;
  final String roomName;
  final double checkInDistance;
  final double checkOutDistance;
  final int minRssi;

  const BeaconTarget({
    required this.beaconUuid,
    required this.sessionId,
    required this.roomName,
    this.major,
    this.minor,
    this.checkInDistance = 3.0,
    this.checkOutDistance = 5.0,
    this.minRssi = -80,
  });

  factory BeaconTarget.fromActiveSession({
    required String beaconUuid,
    required String sessionId,
    required String roomName,
    String? major,
    String? minor,
    double thresholdDistance = 3.0,
    int minRssi = -80,
  }) {
    return BeaconTarget(
      beaconUuid: beaconUuid,
      sessionId: sessionId,
      roomName: roomName,
      major: major,
      minor: minor,
      checkInDistance: thresholdDistance,
      checkOutDistance: thresholdDistance + 2.0,
      minRssi: minRssi,
    );
  }
}

class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http:/192.168.10.15:8000',
  );

  static const int stableInRequired = 2;
  static const int stableOutRequired = 3;

  static const Duration duplicateCheckWindow = Duration(seconds: 10);
  static const Duration scanTimeout = Duration(seconds: 12);
  static const Duration rescanDelay = Duration(seconds: 2);

  /// Demo fallback target. BLE screen дээр check-in хийхдээ ашиглахгүй.
  /// Зөвхөн тест/гарын авлага хийх үед лавлах утга болгон үлдээсэн.
  static const List<BeaconTarget> beaconTargets = [
    BeaconTarget(
      beaconUuid: String.fromEnvironment(
        'DEFAULT_BEACON_UUID',
        defaultValue: 'BLE Advertiser',
      ),
      sessionId: String.fromEnvironment(
        'DEFAULT_SESSION_ID',
        defaultValue: 'SESSION002',
      ),
      roomName: String.fromEnvironment(
        'DEFAULT_ROOM_NAME',
        defaultValue: 'Room 402',
      ),
      major: String.fromEnvironment('DEFAULT_BEACON_MAJOR', defaultValue: '1'),
      minor: String.fromEnvironment('DEFAULT_BEACON_MINOR', defaultValue: '1'),
      checkInDistance: 3.0,
      checkOutDistance: 5.0,
      minRssi: -80,
    ),
  ];

  static bool canUseBle(String role) {
    final normalizedRole = role.toLowerCase().trim();
    return normalizedRole == 'student' || normalizedRole == 'teacher';
  }

  static String deviceUuidForUser({
    required String userId,
    required String role,
  }) {
    if (!canUseBle(role)) {
      throw Exception('Admin хэрэглэгч BLE check-in хийх боломжгүй.');
    }

    return 'DEVICE_$userId';
  }
}
