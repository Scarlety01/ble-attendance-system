import '../models/attendance_event.dart';
import 'api_client.dart';

class HistoryApiService {
  final ApiClient _api = ApiClient();

  Future<List<AttendanceEvent>> getHistory(
    String userId, {
    String? fromDate,
    String? toDate,
    String? status,
    String? sessionId,
    String? classId,
    int limit = 300,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'offset': offset};

    if (fromDate != null && fromDate.isNotEmpty) query['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) query['to_date'] = toDate;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (sessionId != null && sessionId.isNotEmpty)
      query['session_id'] = sessionId;
    if (classId != null && classId.isNotEmpty) query['class_id'] = classId;

    final response = await _api.dio.get(
      '/attendance/history/$userId',
      queryParameters: query,
    );

    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(AttendanceEvent.fromJson).toList();
  }

  Future<List<AttendanceEvent>> getAllAttendance({
    String? sessionId,
    String? classId,
    String? userId,
    String? status,
    String? fromDate,
    String? toDate,
    int limit = 500,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'offset': offset};

    if (sessionId != null && sessionId.isNotEmpty)
      query['session_id'] = sessionId;
    if (classId != null && classId.isNotEmpty) query['class_id'] = classId;
    if (userId != null && userId.isNotEmpty) query['user_id'] = userId;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (fromDate != null && fromDate.isNotEmpty) query['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) query['to_date'] = toDate;

    final response = await _api.dio.get(
      '/attendance/all',
      queryParameters: query,
    );

    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(AttendanceEvent.fromJson).toList();
  }
}
