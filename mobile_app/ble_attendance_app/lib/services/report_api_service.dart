import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

class ReportApiService {
  final ApiClient _api = ApiClient();

  Map<String, dynamic> _query({
    String? classId,
    String? sessionId,
    String? userId,
    String? status,
    int? limit,
    int? offset,
  }) {
    final query = <String, dynamic>{};

    if (classId != null && classId.isNotEmpty) {
      query['class_id'] = classId;
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      query['session_id'] = sessionId;
    }
    if (userId != null && userId.isNotEmpty) {
      query['user_id'] = userId;
    }
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }
    if (limit != null) {
      query['limit'] = limit;
    }
    if (offset != null) {
      query['offset'] = offset;
    }

    return query;
  }

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
      return 'Нэвтрэх хугацаа дууссан байна. Дахин нэвтэрнэ үү.';
    }

    if (statusCode == 403) {
      return 'Тайлан харах эрхгүй байна.';
    }

    if (statusCode == 404) {
      return 'Тайлангийн мэдээлэл олдсонгүй.';
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Сервертэй холбогдож чадсангүй. Wi-Fi болон API_BASE_URL шалгана уу.';
    }

    return e.message ?? 'Тайлан авах үед тодорхойгүй алдаа гарлаа.';
  }

  Future<Map<String, dynamic>> getMonthlySummary(
    String month, {
    String? classId,
    String? sessionId,
    String? userId,
  }) async {
    try {
      final response = await _api.dio.get(
        '/report/summary/$month',
        queryParameters: _query(
          classId: classId,
          sessionId: sessionId,
          userId: userId,
        ),
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      throw Exception(_extractServerMessage(e));
    }
  }

  Future<Map<String, dynamic>> getMonthlyReport(
    String month, {
    String? classId,
    String? sessionId,
    String? userId,
    String? status,
    int limit = 1000,
    int offset = 0,
  }) async {
    try {
      final response = await _api.dio.get(
        '/report/monthly/$month',
        queryParameters: _query(
          classId: classId,
          sessionId: sessionId,
          userId: userId,
          status: status,
          limit: limit,
          offset: offset,
        ),
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      throw Exception(_extractServerMessage(e));
    }
  }

  Future<Uint8List> downloadExcel(
    String month, {
    String? classId,
    String? sessionId,
    String? userId,
    String? status,
  }) async {
    try {
      final response = await _api.dio.get<List<int>>(
        '/report/excel/$month',
        queryParameters: _query(
          classId: classId,
          sessionId: sessionId,
          userId: userId,
          status: status,
        ),
        options: Options(responseType: ResponseType.bytes),
      );

      return Uint8List.fromList(response.data ?? <int>[]);
    } on DioException catch (e) {
      throw Exception(_extractServerMessage(e));
    }
  }

  Future<Uint8List> downloadPdf(
    String month, {
    String? classId,
    String? sessionId,
    String? userId,
    String? status,
  }) async {
    try {
      final response = await _api.dio.get<List<int>>(
        '/report/pdf/$month',
        queryParameters: _query(
          classId: classId,
          sessionId: sessionId,
          userId: userId,
          status: status,
        ),
        options: Options(responseType: ResponseType.bytes),
      );

      return Uint8List.fromList(response.data ?? <int>[]);
    } on DioException catch (e) {
      throw Exception(_extractServerMessage(e));
    }
  }
}
