import '../models/attendance_appeal_model.dart';
import '../models/attendance_event.dart';
import '../models/teacher_session_summary_model.dart';
import 'api_client.dart';

class AttendanceExtraApiService {
  final ApiClient _api = ApiClient();

  Future<AttendanceEvent> manualCorrectAttendance({
    required int attendanceId,
    String? status,
    String? note,
    String? checkInTimeIso,
    String? checkOutTimeIso,
    required String reason,
  }) async {
    final response = await _api.dio.patch(
      '/attendance/$attendanceId/manual-update',
      data: {
        'status': status,
        'note': note,
        'check_in_time': checkInTimeIso,
        'check_out_time': checkOutTimeIso,
        'reason': reason,
      }..removeWhere((key, value) => value == null),
    );

    return AttendanceEvent.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<AttendanceAppealModel> createAppeal({
    int? attendanceId,
    required String sessionId,
    required String reasonType,
    required String message,
  }) async {
    final response = await _api.dio.post(
      '/attendance/appeals',
      data: {
        'attendance_id': attendanceId,
        'session_id': sessionId,
        'reason_type': reasonType,
        'message': message,
      }..removeWhere((key, value) => value == null),
    );

    return AttendanceAppealModel.fromJson(
      Map<String, dynamic>.from(response.data),
    );
  }

  Future<List<AttendanceAppealModel>> getAppeals({
    String? status,
    String? userId,
    String? sessionId,
  }) async {
    final response = await _api.dio.get(
      '/attendance/appeals',
      queryParameters: {
        'status': status,
        'user_id': userId,
        'session_id': sessionId,
      }..removeWhere((key, value) => value == null || value.toString().isEmpty),
    );

    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(AttendanceAppealModel.fromJson).toList();
  }

  Future<AttendanceAppealModel> reviewAppeal({
    required int appealId,
    required String status,
    String? reviewNote,
    String? correctionStatus,
    String? correctionNote,
    String? correctionCheckInTimeIso,
    String? correctionCheckOutTimeIso,
    int? correctionLateMinutes,
  }) async {
    final response = await _api.dio.patch(
      '/attendance/appeals/$appealId/review',
      data: {
        'status': status,
        'review_note': reviewNote,
        'correction_status': correctionStatus,
        'correction_note': correctionNote,
        'correction_check_in_time': correctionCheckInTimeIso,
        'correction_check_out_time': correctionCheckOutTimeIso,
        'correction_late_minutes': correctionLateMinutes,
      }..removeWhere((key, value) => value == null),
    );

    return AttendanceAppealModel.fromJson(
      Map<String, dynamic>.from(response.data),
    );
  }

  Future<TeacherSessionSummaryResponse> getTeacherSummary({
    String? targetDate,
  }) async {
    final response = await _api.dio.get(
      '/dashboard/teacher/summary',
      queryParameters: {
        'target_date': targetDate,
      }..removeWhere((key, value) => value == null || value.toString().isEmpty),
    );

    return TeacherSessionSummaryResponse.fromJson(
      Map<String, dynamic>.from(response.data),
    );
  }
}
