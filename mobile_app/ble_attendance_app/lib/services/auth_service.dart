import 'package:dio/dio.dart';

import 'api_client.dart';
import 'local_cache_service.dart';

class AuthService {
  final ApiClient _api = ApiClient();
  final LocalCacheService _cache = LocalCacheService();

  String _extractServerMessage(DioException e) {
    final data = e.response?.data;

    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }

    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }

    final statusCode = e.response?.statusCode;

    if (statusCode == 401) {
      return 'Нэвтрэх нэр эсвэл нууц үг буруу байна';
    }

    if (statusCode == 403) {
      return 'Хэрэглэгч идэвхгүй эсвэл эрхгүй байна';
    }

    if (statusCode == 404) {
      return 'Сервер дээр хэрэглэгч олдсонгүй';
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Сервертэй холбогдож чадсангүй. Wi-Fi болон API_BASE_URL шалгана уу.';
    }

    return e.message ?? 'Тодорхойгүй алдаа гарлаа';
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post(
        '/auth/login',
        data: {
          'username': username.trim().toLowerCase(),
          'password': password.trim(),
        },
      );

      final data = Map<String, dynamic>.from(response.data);

      await _cache.saveAuth(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
        userId: data['user_id'],
        role: data['role'],
        organizationId: data['organization_id'],
      );

      _api.setToken(data['access_token']);

      return data;
    } on DioException catch (e) {
      throw Exception(_extractServerMessage(e));
    } catch (e) {
      throw Exception('Нэвтрэх үед алдаа гарлаа: $e');
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _cache.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api.dio.post(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } catch (_) {}

    await _cache.clearAll();
    _api.clearToken();
  }

  Future<bool> hasToken() async {
    final token = await _cache.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getUserId() => _cache.getUserId();

  Future<String?> getRole() => _cache.getRole();

  Future<String?> getOrganizationId() => _cache.getOrganizationId();
}
