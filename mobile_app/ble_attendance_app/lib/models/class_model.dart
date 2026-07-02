class ClassModel {
  final String id;
  final String organizationId;
  final String departmentId;
  final String? teacherId;
  final String? roomId;
  final String? beaconId;
  final String name;
  final String? code;
  final String type;
  final String? dayOfWeek;
  final String? startTime;
  final String? endTime;
  final String? semesterStartDate;
  final String? semesterEndDate;
  final int lateAfterMinutes;
  final bool isActive;
  final DateTime? createdAt;

  ClassModel({
    required this.id,
    required this.organizationId,
    required this.departmentId,
    this.teacherId,
    this.roomId,
    this.beaconId,
    required this.name,
    this.code,
    required this.type,
    this.dayOfWeek,
    this.startTime,
    this.endTime,
    this.semesterStartDate,
    this.semesterEndDate,
    required this.lateAfterMinutes,
    required this.isActive,
    this.createdAt,
  });

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id'] ?? '',
      organizationId: json['organization_id'] ?? '',
      departmentId: json['department_id'] ?? '',
      teacherId: json['teacher_id'],
      roomId: json['room_id'],
      beaconId: json['beacon_id'],
      name: json['name'] ?? '',
      code: json['code'],
      type: json['type'] ?? 'class',
      dayOfWeek: json['day_of_week'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      semesterStartDate: json['semester_start_date'],
      semesterEndDate: json['semester_end_date'],
      lateAfterMinutes: json['late_after_minutes'] ?? 10,
      isActive: json['is_active'] ?? false,
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
