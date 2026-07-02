class AttendanceAppealModel {
  final int id;
  final String organizationId;
  final int? attendanceId;
  final String userId;
  final String sessionId;
  final String reasonType;
  final String message;
  final String status;
  final String? reviewedBy;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  AttendanceAppealModel({
    required this.id,
    required this.organizationId,
    this.attendanceId,
    required this.userId,
    required this.sessionId,
    required this.reasonType,
    required this.message,
    required this.status,
    this.reviewedBy,
    this.reviewNote,
    this.createdAt,
    this.reviewedAt,
  });

  factory AttendanceAppealModel.fromJson(Map<String, dynamic> json) {
    return AttendanceAppealModel(
      id: json['id'] ?? 0,
      organizationId: json['organization_id'] ?? '',
      attendanceId: json['attendance_id'],
      userId: json['user_id'] ?? '',
      sessionId: json['session_id'] ?? '',
      reasonType: json['reason_type'] ?? '',
      message: json['message'] ?? '',
      status: json['status'] ?? 'pending',
      reviewedBy: json['reviewed_by'],
      reviewNote: json['review_note'],
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
      reviewedAt:
          json['reviewed_at'] != null
              ? DateTime.tryParse(json['reviewed_at'])
              : null,
    );
  }
}
