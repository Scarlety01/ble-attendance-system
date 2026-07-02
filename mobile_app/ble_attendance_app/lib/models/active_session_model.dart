class ActiveSessionModel {
  final String sessionId;
  final String classOrShiftId;
  final String className;
  final String roomName;
  final String? beaconId;
  final String beaconUuid;
  final String? major;
  final String? minor;
  final int? txPower;
  final double thresholdDistance;
  final String sessionDate;
  final String? startTime;
  final String? endTime;
  final bool isOpen;

  ActiveSessionModel({
    required this.sessionId,
    required this.classOrShiftId,
    required this.className,
    required this.roomName,
    this.beaconId,
    required this.beaconUuid,
    this.major,
    this.minor,
    this.txPower,
    required this.thresholdDistance,
    required this.sessionDate,
    this.startTime,
    this.endTime,
    required this.isOpen,
  });

  factory ActiveSessionModel.fromJson(Map<String, dynamic> json) {
    return ActiveSessionModel(
      sessionId: json['session_id'] ?? '',
      classOrShiftId: json['class_or_shift_id'] ?? '',
      className: json['class_name'] ?? '',
      roomName: json['room_name'] ?? '-',
      beaconId: json['beacon_id'],
      beaconUuid: json['beacon_uuid'] ?? '',
      major: json['major'],
      minor: json['minor'],
      txPower:
          json['tx_power'] is num ? (json['tx_power'] as num).toInt() : null,
      thresholdDistance:
          json['threshold_distance'] is num
              ? (json['threshold_distance'] as num).toDouble()
              : 3.0,
      sessionDate: json['session_date'] ?? '',
      startTime: json['start_time'],
      endTime: json['end_time'],
      isOpen: json['is_open'] ?? false,
    );
  }
}
