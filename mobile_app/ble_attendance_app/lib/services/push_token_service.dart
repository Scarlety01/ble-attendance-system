import 'api_client.dart';

class PushTokenService {
  final ApiClient _api = ApiClient();

  Future<void> registerPushToken({
    required String deviceUuid,
    required String platform,
    required String token,
  }) async {
    await _api.dio.post(
      '/push-tokens',
      data: {'device_uuid': deviceUuid, 'platform': platform, 'token': token},
    );
  }
}
