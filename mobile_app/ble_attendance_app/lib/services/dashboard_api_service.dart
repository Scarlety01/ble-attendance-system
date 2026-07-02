import 'api_client.dart';

class DashboardOverview {
  final String? month;
  final int totalAttendance;
  final int totalPresent;
  final int totalLate;
  final int openSessions;

  const DashboardOverview({
    this.month,
    required this.totalAttendance,
    required this.totalPresent,
    required this.totalLate,
    required this.openSessions,
  });

  double get lateRate {
    if (totalAttendance == 0) return 0.0;
    return (totalLate / totalAttendance) * 100.0;
  }

  double get presentRate {
    if (totalAttendance == 0) return 0.0;
    return (totalPresent / totalAttendance) * 100.0;
  }

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    return DashboardOverview(
      month: json['month']?.toString(),
      totalAttendance:
          json['total_attendance'] is num
              ? (json['total_attendance'] as num).toInt()
              : 0,
      totalPresent:
          json['total_present'] is num
              ? (json['total_present'] as num).toInt()
              : 0,
      totalLate:
          json['total_late'] is num ? (json['total_late'] as num).toInt() : 0,
      openSessions:
          json['open_sessions'] is num
              ? (json['open_sessions'] as num).toInt()
              : 0,
    );
  }
}

class DashboardDailyTrendItem {
  final String date;
  final int count;

  const DashboardDailyTrendItem({required this.date, required this.count});

  factory DashboardDailyTrendItem.fromJson(Map<String, dynamic> json) {
    return DashboardDailyTrendItem(
      date: json['date']?.toString() ?? '',
      count: json['count'] is num ? (json['count'] as num).toInt() : 0,
    );
  }
}

class DashboardSessionSummaryItem {
  final String sessionId;
  final int total;
  final int present;
  final int late;
  final int checkedOut;

  const DashboardSessionSummaryItem({
    required this.sessionId,
    required this.total,
    required this.present,
    required this.late,
    required this.checkedOut,
  });

  double get attendanceRate {
    if (total == 0) return 0.0;
    return ((present + late + checkedOut) / total * 100.0).clamp(0.0, 100.0);
  }

  factory DashboardSessionSummaryItem.fromJson(Map<String, dynamic> json) {
    return DashboardSessionSummaryItem(
      sessionId: json['session_id']?.toString() ?? '',
      total: json['total'] is num ? (json['total'] as num).toInt() : 0,
      present: json['present'] is num ? (json['present'] as num).toInt() : 0,
      late: json['late'] is num ? (json['late'] as num).toInt() : 0,
      checkedOut:
          json['checked_out'] is num ? (json['checked_out'] as num).toInt() : 0,
    );
  }
}

class DashboardLateRankingItem {
  final String userId;
  final int lateCount;
  final int lateMinutesSum;

  const DashboardLateRankingItem({
    required this.userId,
    required this.lateCount,
    required this.lateMinutesSum,
  });

  factory DashboardLateRankingItem.fromJson(Map<String, dynamic> json) {
    return DashboardLateRankingItem(
      userId: json['user_id']?.toString() ?? '',
      lateCount:
          json['late_count'] is num ? (json['late_count'] as num).toInt() : 0,
      lateMinutesSum:
          json['late_minutes_sum'] is num
              ? (json['late_minutes_sum'] as num).toInt()
              : 0,
    );
  }
}

class DashboardApiService {
  final ApiClient _api = ApiClient();

  Future<DashboardOverview> getOverview({String? month}) async {
    final response = await _api.dio.get(
      '/dashboard/overview',
      queryParameters: {
        'month': month,
      }..removeWhere((key, value) => value == null || value.toString().isEmpty),
    );

    return DashboardOverview.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<List<DashboardDailyTrendItem>> getDailyTrend(String month) async {
    final response = await _api.dio.get(
      '/dashboard/daily-trend',
      queryParameters: {'month': month},
    );

    final data = Map<String, dynamic>.from(response.data);
    final items = data['items'];

    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map(
          (e) => DashboardDailyTrendItem.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  Future<List<DashboardSessionSummaryItem>> getSessionSummary(
    String month,
  ) async {
    final response = await _api.dio.get(
      '/dashboard/session-summary',
      queryParameters: {'month': month},
    );

    final data = Map<String, dynamic>.from(response.data);
    final items = data['items'];

    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map(
          (e) => DashboardSessionSummaryItem.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<List<DashboardLateRankingItem>> getLateRanking(String month) async {
    final response = await _api.dio.get(
      '/dashboard/late-ranking',
      queryParameters: {'month': month},
    );

    final data = Map<String, dynamic>.from(response.data);
    final items = data['items'];

    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map(
          (e) =>
              DashboardLateRankingItem.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }
}
