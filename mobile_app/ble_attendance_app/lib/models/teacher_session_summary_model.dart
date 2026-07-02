class TeacherSessionSummaryItem {
  final String sessionId;
  final String classOrShiftId;
  final String className;
  final String roomName;
  final String sessionDate;
  final String? startTime;
  final String? endTime;
  final bool isOpen;

  /// Backend одоогоор field name-ийг total_students гэж буцааж байгаа.
  /// Гэхдээ утга нь teacher + student буюу нийт оролцогч байж болно.
  /// UI дээр "Нийт оролцогч" гэж харуулахад илүү зөв.
  final int totalParticipants;

  /// Хуучин UI код эвдэхгүйн тулд alias хэвээр үлдээв.
  int get totalStudents => totalParticipants;

  final int present;
  final int late;
  final int checkedOut;
  final int absent;
  final double attendanceRate;

  TeacherSessionSummaryItem({
    required this.sessionId,
    required this.classOrShiftId,
    required this.className,
    required this.roomName,
    required this.sessionDate,
    this.startTime,
    this.endTime,
    required this.isOpen,
    required this.totalParticipants,
    required this.present,
    required this.late,
    required this.checkedOut,
    required this.absent,
    required this.attendanceRate,
  });

  factory TeacherSessionSummaryItem.fromJson(Map<String, dynamic> json) {
    final rawRate =
        json['attendance_rate'] is num
            ? (json['attendance_rate'] as num).toDouble()
            : 0.0;

    final rawTotal = json['total_participants'] ?? json['total_students'];

    return TeacherSessionSummaryItem(
      sessionId: json['session_id'] ?? '',
      classOrShiftId: json['class_or_shift_id'] ?? '',
      className: json['class_name'] ?? '',
      roomName: json['room_name'] ?? '-',
      sessionDate: json['session_date'] ?? '',
      startTime: json['start_time'],
      endTime: json['end_time'],
      isOpen: json['is_open'] ?? false,
      totalParticipants: rawTotal is num ? rawTotal.toInt() : 0,
      present: json['present'] is num ? (json['present'] as num).toInt() : 0,
      late: json['late'] is num ? (json['late'] as num).toInt() : 0,
      checkedOut:
          json['checked_out'] is num ? (json['checked_out'] as num).toInt() : 0,
      absent: json['absent'] is num ? (json['absent'] as num).toInt() : 0,

      // UI дээр 200% гарахаас давхар хамгаална.
      attendanceRate: rawRate.clamp(0.0, 100.0),
    );
  }
}

class TeacherSessionSummaryResponse {
  final String teacherId;
  final String today;
  final List<TeacherSessionSummaryItem> sessions;

  TeacherSessionSummaryResponse({
    required this.teacherId,
    required this.today,
    required this.sessions,
  });

  factory TeacherSessionSummaryResponse.fromJson(Map<String, dynamic> json) {
    final rawSessions = json['sessions'];

    return TeacherSessionSummaryResponse(
      teacherId: json['teacher_id'] ?? '',
      today: json['today'] ?? '',
      sessions:
          rawSessions is List
              ? rawSessions
                  .whereType<Map>()
                  .map(
                    (e) => TeacherSessionSummaryItem.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
              : [],
    );
  }
}
