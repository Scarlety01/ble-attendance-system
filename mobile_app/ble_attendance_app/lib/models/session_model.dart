class SessionModel {
  final String id;
  final String organizationId;
  final String classOrShiftId;
  final String? beaconId;
  final String sessionDate;
  final String? startTime;
  final String? endTime;
  final bool isOpen;
  final DateTime? createdAt;

  SessionModel({
    required this.id,
    required this.organizationId,
    required this.classOrShiftId,
    this.beaconId,
    required this.sessionDate,
    this.startTime,
    this.endTime,
    required this.isOpen,
    this.createdAt,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] ?? '',
      organizationId: json['organization_id'] ?? '',
      classOrShiftId: json['class_or_shift_id'] ?? '',
      beaconId: json['beacon_id'],
      sessionDate: json['session_date'] ?? '',
      startTime: json['start_time'],
      endTime: json['end_time'],
      isOpen: json['is_open'] ?? false,
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
