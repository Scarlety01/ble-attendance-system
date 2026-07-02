import '../models/active_session_model.dart';
import 'api_client.dart';

class ActiveSessionService {
  final ApiClient _api = ApiClient();

  Future<List<ActiveSessionModel>> getActiveTodaySessions() async {
    final response = await _api.dio.get('/sessions/active-today');

    final list = List<Map<String, dynamic>>.from(response.data);
    return list.map(ActiveSessionModel.fromJson).toList();
  }
}
