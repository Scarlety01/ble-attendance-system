import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/config/app_config.dart';
import '../models/attendance_event.dart';
import '../models/audit_log_model.dart';
import '../models/beacon_model.dart';
import '../models/class_model.dart';
import '../models/class_student_model.dart';
import '../models/device_model.dart';
import '../models/room_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import 'api_client.dart';
import 'local_cache_service.dart';

class AdminApiService {
  final ApiClient _api = ApiClient();
  final LocalCacheService _cache = LocalCacheService();

  WebSocket? _socket;
  StreamController<Map<String, dynamic>>? _wsController;

  Future<List<UserModel>> getUsers() async {
    final response = await _api.dio.get('/users');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(UserModel.fromJson).toList();
  }

  Future<UserModel> createUser({
    required String id,
    required String organizationId,
    String? departmentId,
    required String username,
    required String fullName,
    String? email,
    String? phone,
    required String password,
    required String role,
    required bool isActive,
  }) async {
    final response = await _api.dio.post(
      '/users',
      data: {
        'id': id,
        'organization_id': organizationId,
        'department_id': departmentId,
        'username': username,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'is_active': isActive,
      },
    );
    return UserModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<DeviceModel>> getDevices() async {
    final response = await _api.dio.get('/devices');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(DeviceModel.fromJson).toList();
  }

  Future<DeviceModel> createDevice({
    required String userId,
    required String uuid,
    String? name,
    String? platform,
    String? deviceType,
    required bool isRegistered,
    required bool isActive,
  }) async {
    final response = await _api.dio.post(
      '/devices',
      data: {
        'user_id': userId,
        'uuid': uuid,
        'name': name,
        'platform': platform,
        'device_type': deviceType,
        'is_registered': isRegistered,
        'is_active': isActive,
      },
    );
    return DeviceModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<UserModel> updateUser({
    required String userId,
    String? departmentId,
    String? fullName,
    String? email,
    String? phone,
    String? role,
    bool? isActive,
  }) async {
    final response = await _api.dio.patch(
      '/users/$userId',
      data: {
        'department_id': departmentId,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'is_active': isActive,
      }..removeWhere((key, value) => value == null),
    );

    return UserModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<DeviceModel> updateDevice({
    required int deviceId,
    String? name,
    String? platform,
    String? deviceType,
    bool? isRegistered,
    bool? isActive,
  }) async {
    final response = await _api.dio.patch(
      '/devices/$deviceId',
      data: {
        'name': name,
        'platform': platform,
        'device_type': deviceType,
        'is_registered': isRegistered,
        'is_active': isActive,
      }..removeWhere((key, value) => value == null),
    );

    return DeviceModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<RoomModel>> getRooms() async {
    final response = await _api.dio.get('/rooms');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(RoomModel.fromJson).toList();
  }

  Future<RoomModel> createRoom({
    required String id,
    required String organizationId,
    required String name,
    String? building,
    String? floor,
    int? capacity,
    String? description,
  }) async {
    final response = await _api.dio.post(
      '/rooms',
      data: {
        'id': id,
        'organization_id': organizationId,
        'name': name,
        'building': building,
        'floor': floor,
        'capacity': capacity,
        'description': description,
      },
    );
    return RoomModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<RoomModel> updateRoom({
    required String roomId,
    String? name,
    String? building,
    String? floor,
    int? capacity,
    String? description,
  }) async {
    final response = await _api.dio.patch(
      '/rooms/$roomId',
      data: {
        'name': name,
        'building': building,
        'floor': floor,
        'capacity': capacity,
        'description': description,
      }..removeWhere((key, value) => value == null),
    );
    return RoomModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<BeaconModel>> getBeacons() async {
    final response = await _api.dio.get('/beacons');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(BeaconModel.fromJson).toList();
  }

  Future<BeaconModel> createBeacon({
    required String id,
    required String organizationId,
    String? roomId,
    required String uuid,
    String? major,
    String? minor,
    required String name,
    String? advertiserType,
    int? txPower,
    required double thresholdDistance,
    required bool isActive,
  }) async {
    final response = await _api.dio.post(
      '/beacons',
      data: {
        'id': id,
        'organization_id': organizationId,
        'room_id': roomId,
        'uuid': uuid,
        'major': major,
        'minor': minor,
        'name': name,
        'advertiser_type': advertiserType,
        'tx_power': txPower,
        'threshold_distance': thresholdDistance,
        'is_active': isActive,
      },
    );
    return BeaconModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<BeaconModel> updateBeacon({
    required String beaconId,
    String? roomId,
    String? uuid,
    String? major,
    String? minor,
    String? name,
    String? advertiserType,
    int? txPower,
    double? thresholdDistance,
    bool? isActive,
  }) async {
    final response = await _api.dio.patch(
      '/beacons/$beaconId',
      data: {
        'room_id': roomId,
        'uuid': uuid,
        'major': major,
        'minor': minor,
        'name': name,
        'advertiser_type': advertiserType,
        'tx_power': txPower,
        'threshold_distance': thresholdDistance,
        'is_active': isActive,
      }..removeWhere((key, value) => value == null),
    );
    return BeaconModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<ClassModel>> getClasses() async {
    final response = await _api.dio.get('/classes');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(ClassModel.fromJson).toList();
  }

  Future<ClassModel> createClass({
    required String id,
    required String organizationId,
    required String departmentId,
    String? teacherId,
    String? roomId,
    String? beaconId,
    required String name,
    String? code,
    required String type,
    String? dayOfWeek,
    String? startTime,
    String? endTime,
    String? semesterStartDate,
    String? semesterEndDate,
    required int lateAfterMinutes,
    required bool isActive,
  }) async {
    final response = await _api.dio.post(
      '/classes',
      data: {
        'id': id,
        'organization_id': organizationId,
        'department_id': departmentId,
        'teacher_id': teacherId,
        'room_id': roomId,
        'beacon_id': beaconId,
        'name': name,
        'code': code,
        'type': type,
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
        'semester_start_date': semesterStartDate,
        'semester_end_date': semesterEndDate,
        'late_after_minutes': lateAfterMinutes,
        'is_active': isActive,
      }..removeWhere((key, value) => value == null),
    );

    return ClassModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<ClassModel> updateClass({
    required String classId,
    String? teacherId,
    String? roomId,
    String? beaconId,
    String? name,
    String? code,
    String? type,
    String? dayOfWeek,
    String? startTime,
    String? endTime,
    String? semesterStartDate,
    String? semesterEndDate,
    int? lateAfterMinutes,
    bool? isActive,
  }) async {
    final response = await _api.dio.patch(
      '/classes/$classId',
      data: {
        'teacher_id': teacherId,
        'room_id': roomId,
        'beacon_id': beaconId,
        'name': name,
        'code': code,
        'type': type,
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
        'semester_start_date': semesterStartDate,
        'semester_end_date': semesterEndDate,
        'late_after_minutes': lateAfterMinutes,
        'is_active': isActive,
      }..removeWhere((key, value) => value == null),
    );

    return ClassModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<SessionModel>> getSessions() async {
    final response = await _api.dio.get('/sessions');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(SessionModel.fromJson).toList();
  }

  Future<SessionModel> createSession({
    required String id,
    required String organizationId,
    required String classOrShiftId,
    String? beaconId,
    required String sessionDate,
    String? startTime,
    String? endTime,
    required bool isOpen,
  }) async {
    final response = await _api.dio.post(
      '/sessions',
      data: {
        'id': id,
        'organization_id': organizationId,
        'class_or_shift_id': classOrShiftId,
        'beacon_id': beaconId,
        'session_date': sessionDate,
        'start_time': startTime,
        'end_time': endTime,
        'is_open': isOpen,
      },
    );
    return SessionModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<SessionModel> updateSession({
    required String sessionId,
    String? beaconId,
    String? sessionDate,
    String? startTime,
    String? endTime,
    bool? isOpen,
  }) async {
    final response = await _api.dio.patch(
      '/sessions/$sessionId',
      data: {
        'beacon_id': beaconId,
        'session_date': sessionDate,
        'start_time': startTime,
        'end_time': endTime,
        'is_open': isOpen,
      }..removeWhere((key, value) => value == null),
    );
    return SessionModel.fromJson(Map<String, dynamic>.from(response.data));
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

  Future<List<ClassStudentModel>> getClassStudents(String classId) async {
    final response = await _api.dio.get('/classes/$classId/students');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(ClassStudentModel.fromJson).toList();
  }

  Future<ClassStudentModel> addClassStudent({
    required String classId,
    required String userId,
  }) async {
    final response = await _api.dio.post(
      '/classes/$classId/students',
      data: {'user_id': userId},
    );
    return ClassStudentModel.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<void> removeClassStudent({
    required String classId,
    required String userId,
  }) async {
    await _api.dio.delete('/classes/$classId/students/$userId');
  }

  Future<List<ClassStudentModel>> getStudentClasses(String userId) async {
    final response = await _api.dio.get('/students/$userId/classes');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(ClassStudentModel.fromJson).toList();
  }

  Future<AttendanceEvent> manualUpdateAttendance({
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
      },
    );
    return AttendanceEvent.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<AuditLogModel>> getAuditLogs() async {
    final response = await _api.dio.get('/audit-logs');
    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(AuditLogModel.fromJson).toList();
  }

  Future<Stream<Map<String, dynamic>>> connectRealtime({
    required String organizationId,
  }) async {
    await disconnectRealtime();

    final baseUri = Uri.parse(AppConfig.baseUrl);
    final accessToken = await _cache.getAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Realtime холболт үүсгэхэд access token олдсонгүй');
    }

    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';

    final wsUri = Uri(
      scheme: wsScheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '/ws/$organizationId',
      queryParameters: {'token': accessToken},
    );

    _wsController = StreamController<Map<String, dynamic>>.broadcast();

    try {
      _socket = await WebSocket.connect(wsUri.toString());
    } catch (e) {
      await _safeCloseController();
      throw Exception('Realtime холболт үүсгэж чадсангүй: $e');
    }

    _socket!.listen(
      (event) {
        try {
          final decoded = jsonDecode(event.toString());

          if (decoded is Map<String, dynamic>) {
            _wsController?.add(decoded);
          } else if (decoded is Map) {
            _wsController?.add(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          // Parse error-г stream crash болгохгүй
          // print('WS parse error: $e');
        }
      },
      onDone: () async {
        await _safeCloseController();
      },
      onError: (_) async {
        await _safeCloseController();
      },
      cancelOnError: true,
    );

    return _wsController!.stream;
  }

  Future<void> _safeCloseController() async {
    if (_wsController != null && !_wsController!.isClosed) {
      await _wsController!.close();
    }
    _wsController = null;
  }

  Future<void> disconnectRealtime() async {
    try {
      await _socket?.close();
    } catch (_) {}

    _socket = null;
    await _safeCloseController();
  }

  Future<void> dispose() async {
    await disconnectRealtime();
  }
}
