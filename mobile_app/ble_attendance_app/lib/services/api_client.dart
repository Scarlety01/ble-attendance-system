import 'package:dio/dio.dart';
import '../core/config/app_config.dart';
import 'local_cache_service.dart';

class ApiClient {
  ApiClient._internal() {
    _setupInterceptors();
  }

  static final ApiClient _instance = ApiClient._internal();

  factory ApiClient() => _instance;

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  final LocalCacheService _cache = LocalCacheService();

  bool _isRefreshing = false;
  Future<String?>? _refreshFuture;

  Future<void> init() async {
    final token = await _cache.getAccessToken();
    if (token != null && token.isNotEmpty) {
      setToken(token);
    }
  }

  void setToken(String token) {
    dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearToken() {
    dio.options.headers.remove('Authorization');
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _cache.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final response = error.response;
          final requestOptions = error.requestOptions;

          final is401 = response?.statusCode == 401;
          final isRefreshCall = requestOptions.path.contains('/auth/refresh');

          if (!is401 || isRefreshCall) {
            return handler.next(error);
          }

          try {
            final newAccessToken = await _refreshAccessToken();

            if (newAccessToken == null || newAccessToken.isEmpty) {
              await _cache.clearAll();
              clearToken();
              return handler.next(error);
            }

            final newHeaders = Map<String, dynamic>.from(
              requestOptions.headers,
            );
            newHeaders['Authorization'] = 'Bearer $newAccessToken';

            final retryResponse = await dio.request(
              requestOptions.path,
              data: requestOptions.data,
              queryParameters: requestOptions.queryParameters,
              options: Options(
                method: requestOptions.method,
                headers: newHeaders,
                responseType: requestOptions.responseType,
                contentType: requestOptions.contentType,
                sendTimeout: requestOptions.sendTimeout,
                receiveTimeout: requestOptions.receiveTimeout,
              ),
            );

            return handler.resolve(retryResponse);
          } catch (_) {
            await _cache.clearAll();
            clearToken();
            return handler.next(error);
          }
        },
      ),
    );
  }

  Future<String?> _refreshAccessToken() async {
    if (_isRefreshing && _refreshFuture != null) {
      return _refreshFuture;
    }

    _isRefreshing = true;
    _refreshFuture = _doRefresh();

    try {
      return await _refreshFuture;
    } finally {
      _isRefreshing = false;
      _refreshFuture = null;
    }
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _cache.getRefreshToken();
    final userId = await _cache.getUserId();
    final role = await _cache.getRole();
    final orgId = await _cache.getOrganizationId();

    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final refreshDio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final response = await refreshDio.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );

    final data = Map<String, dynamic>.from(response.data);
    final accessToken = data['access_token']?.toString();
    final newRefreshToken = data['refresh_token']?.toString();

    if (accessToken == null ||
        accessToken.isEmpty ||
        newRefreshToken == null ||
        newRefreshToken.isEmpty) {
      return null;
    }

    await _cache.saveAuth(
      accessToken: accessToken,
      refreshToken: newRefreshToken,
      userId: data['user_id']?.toString() ?? userId ?? '',
      role: data['role']?.toString() ?? role ?? '',
      organizationId: data['organization_id']?.toString() ?? orgId ?? '',
    );

    setToken(accessToken);
    return accessToken;
  }
}
