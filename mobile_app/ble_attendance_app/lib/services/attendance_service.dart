import 'package:dio/dio.dart';

import '../core/config/app_config.dart';
import '../core/utils/device_utils.dart';
import 'api_client.dart';
import 'local_cache_service.dart';

class AttendanceService {
  final ApiClient _api = ApiClient();
  final LocalCacheService _cache = LocalCacheService();

  bool _isOfflineError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.response == null;
  }

  String _extractServerMessage(DioException e) {
    final data = e.response?.data;

    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }

    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }

    return e.message ?? 'Тодорхойгүй алдаа гарлаа';
  }

  bool _isDuplicateCheckIn({
    required int? statusCode,
    required String message,
  }) {
    final lower = message.toLowerCase();

    return statusCode == 409 ||
        lower.contains('duplicate check-in') ||
        lower.contains('duplicate check-in cache') ||
        lower.contains('duplicate check-in (cache)') ||
        message.contains('Ирц аль хэдийн') ||
        message.contains('аль хэдийн бүртгэгдсэн') ||
        message.contains('аль хэдийн');
  }

  bool _isDuplicateCheckOut({
    required int? statusCode,
    required String message,
  }) {
    final lower = message.toLowerCase();

    return statusCode == 409 ||
        lower.contains('already checked out') ||
        lower.contains('duplicate check-out') ||
        lower.contains('duplicate checkout') ||
        message.contains('Check-out аль хэдийн') ||
        message.contains('аль хэдийн бүртгэгдсэн') ||
        message.contains('аль хэдийн');
  }

  Future<Map<String, dynamic>> checkIn({
    required String userId,
    required String sessionId,
    required String deviceUuid,
    required String beaconUuid,
    String? major,
    String? minor,
    required int rssi,
    required double distance,
    List<int> rssiSamples = const [],
    String? note,
  }) async {
    final role = await _cache.getRole() ?? 'student';
    if (!AppConfig.canUseBle(role)) {
      throw Exception('Admin хэрэглэгч BLE check-in хийх боломжгүй.');
    }

    final detectedAt = DateTime.now().toUtc();

    final payload = {
      'user_id': userId,
      'session_id': sessionId,
      'device_uuid': deviceUuid,
      'beacon_uuid': beaconUuid,
      'major': major,
      'minor': minor,
      'rssi': rssi,
      'distance': distance,
      'client_timestamp': detectedAt.toIso8601String(),
      'nonce': DeviceUtils.generateNonce(),

      // Backend-ийн RSSI variance / anti-spoofing шалгалтад ашиглана.
      'rssi_samples': List<int>.from(rssiSamples),

      'note': note ?? 'BLE auto check-in',
    };

    try {
      final response = await _api.dio.post('/attendance/check', data: payload);
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final message = _extractServerMessage(e);

      // Backend Redis cache duplicate-г 400 "Duplicate check-in (cache)"
      // гэж буцаадаг тул үүнийг UI дээр ERROR гэж харуулахгүй.
      if (_isDuplicateCheckIn(statusCode: statusCode, message: message)) {
        return {
          'already_checked_in': true,
          'message': 'Аль хэдийн check-in бүртгэгдсэн байна',
        };
      }

      if (_isOfflineError(e)) {
        await _cache.enqueuePendingAttendance({
          'type': 'check_in',
          'payload': payload,
          'detected_at': detectedAt.toIso8601String(),
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });

        return {
          'queued': true,
          'message': 'Сүлжээ тасарсан тул check-in local queue-д хадгаллаа',
        };
      }

      throw Exception(message);
    } catch (e) {
      throw Exception('Check-in алдаа: $e');
    }
  }

  Future<Map<String, dynamic>> checkOut({
    required String sessionId,
    required String deviceUuid,
    String? note,
  }) async {
    final role = await _cache.getRole() ?? 'student';
    if (!AppConfig.canUseBle(role)) {
      throw Exception('Admin хэрэглэгч BLE check-out хийх боломжгүй.');
    }

    final detectedAt = DateTime.now().toUtc();

    final payload = {
      'session_id': sessionId,
      'device_uuid': deviceUuid,
      'client_timestamp': detectedAt.toIso8601String(),
      'nonce': DeviceUtils.generateNonce(),
      'note': note ?? 'BLE auto check-out',
    };

    try {
      final response = await _api.dio.post(
        '/attendance/checkout',
        data: payload,
      );
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final message = _extractServerMessage(e);

      if (_isDuplicateCheckOut(statusCode: statusCode, message: message)) {
        return {
          'already_checked_out': true,
          'message': 'Аль хэдийн check-out бүртгэгдсэн байна',
        };
      }

      if (_isOfflineError(e)) {
        await _cache.enqueuePendingAttendance({
          'type': 'check_out',
          'payload': payload,
          'detected_at': detectedAt.toIso8601String(),
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });

        return {
          'queued': true,
          'message': 'Сүлжээ тасарсан тул check-out local queue-д хадгаллаа',
        };
      }

      throw Exception(message);
    } catch (e) {
      throw Exception('Check-out алдаа: $e');
    }
  }

  Future<int> syncPendingAttendances() async {
    final role = await _cache.getRole() ?? 'student';
    if (!AppConfig.canUseBle(role)) {
      return 0;
    }

    final items = await _cache.getPendingAttendanceQueue();
    if (items.isEmpty) return 0;

    int synced = 0;
    final remaining = <Map<String, dynamic>>[];

    for (final item in items) {
      final type = item['type'];
      final payload = Map<String, dynamic>.from(item['payload'] ?? {});

      final detectedAt =
          item['detected_at']?.toString() ??
          item['queued_at']?.toString() ??
          DateTime.now().toUtc().toIso8601String();

      // Offline sync үед backend-д бодит илрүүлсэн цагийг тусад нь өгнө.
      // client_timestamp / nonce нь зөвхөн sync request-ийн freshness/replay шалгалтад ашиглагдана.
      final syncTimestamp = DateTime.now().toUtc().toIso8601String();
      payload['client_timestamp'] = syncTimestamp;
      payload['nonce'] = DeviceUtils.generateNonce();

      try {
        if (type != 'check_in' && type != 'check_out') {
          remaining.add(item);
          continue;
        }

        await _api.dio.post(
          '/attendance/sync',
          data: {
            'type': type,
            'payload': payload,
            'detected_at': detectedAt,
            'sync_timestamp': syncTimestamp,
            'nonce': payload['nonce'],
          },
        );

        synced++;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final message = _extractServerMessage(e);

        if (_isOfflineError(e)) {
          remaining.add({
            ...item,
            'payload': payload,
            'last_error': message,
            'last_try_at': DateTime.now().toIso8601String(),
          });
          continue;
        }

        final duplicateCheckIn = _isDuplicateCheckIn(
          statusCode: statusCode,
          message: message,
        );

        final duplicateCheckOut = _isDuplicateCheckOut(
          statusCode: statusCode,
          message: message,
        );

        // Давхардсан бүртгэл бол сервер дээр аль хэдийн хадгалагдсан гэж үзээд
        // queue-с хасна.
        if (duplicateCheckIn || duplicateCheckOut) {
          synced++;
          continue;
        }

        // Дахин оролдоод ч засагдахгүй validation error-уудыг queue-д үлдээхгүй.
        final shouldDrop =
            message.contains('Timestamp') ||
            message.contains('Replay') ||
            message.contains('nonce') ||
            message.contains('beacon') ||
            message.contains('Beacon') ||
            message.contains('Session') ||
            message.contains('session') ||
            message.contains('Бүртгэлтэй төхөөрөмж олдсонгүй') ||
            message.contains('Энэ session-д таарах beacon биш байна') ||
            message.contains('Beacon major') ||
            message.contains('Beacon minor') ||
            message.contains('Beacon-оос хэт хол') ||
            message.contains('цагийн хүрээнээс гадуур') ||
            message.contains('бүртгэлгүй хэрэглэгч') ||
            message.contains('RSSI хэт тогтвортой');

        if (!shouldDrop) {
          remaining.add({
            ...item,
            'payload': payload,
            'last_error': message,
            'last_try_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        remaining.add({
          ...item,
          'payload': payload,
          'last_error': e.toString(),
          'last_try_at': DateTime.now().toIso8601String(),
        });
      }
    }

    await _cache.savePendingAttendanceQueue(remaining);
    return synced;
  }
}
