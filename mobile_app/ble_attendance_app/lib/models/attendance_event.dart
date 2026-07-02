class AttendanceEvent {
  final int? id;
  final String sessionId;
  final String userId;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final double? distanceM;
  final int? rssi;
  final String? status;
  final String? detectionMethod;
  final int? lateMinutes;
  final String? note;

  AttendanceEvent({
    this.id,
    required this.sessionId,
    required this.userId,
    this.checkInTime,
    this.checkOutTime,
    this.distanceM,
    this.rssi,
    this.status,
    this.detectionMethod,
    this.lateMinutes,
    this.note,
  });

  static DateTime? _parseBackendDateTime(dynamic value) {
    if (value == null) return null;

    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'None' || raw == 'null') return null;

    try {
      final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');

      final hasTimezone =
          normalized.endsWith('Z') ||
          RegExp(r'([+-]\d{2}:\d{2})$').hasMatch(normalized);

      final parsed = DateTime.parse(normalized);

      // Backend timezone-гүй naive datetime буцаавал түүнийг local/app time гэж үзнэ.
      // Өмнө нь Z залгаснаас Улаанбаатарын цаг UTC гэж ойлгогдон 8 цагаар зөрөх эрсдэлтэй байсан.
      return hasTimezone ? parsed.toLocal() : parsed;
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  factory AttendanceEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceEvent(
      id: json['id'],
      sessionId: json['session_id'] ?? '',
      userId: json['user_id'] ?? '',
      checkInTime: _parseBackendDateTime(json['check_in_time']),
      checkOutTime: _parseBackendDateTime(json['check_out_time']),
      distanceM:
          json['distance_m'] is num
              ? (json['distance_m'] as num).toDouble()
              : null,
      rssi: json['rssi'],
      status: json['status'],
      detectionMethod: json['detection_method'],
      lateMinutes: json['late_minutes'],
      note: json['note'],
    );
  }
}
