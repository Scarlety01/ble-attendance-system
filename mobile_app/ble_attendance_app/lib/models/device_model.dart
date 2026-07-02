class DeviceModel {
  final int id;
  final String userId;
  final String uuid;
  final String? name;
  final String? platform;
  final String? deviceType;
  final bool isRegistered;
  final bool isActive;
  final DateTime? verifiedAt;
  final DateTime? revokedAt;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  DeviceModel({
    required this.id,
    required this.userId,
    required this.uuid,
    this.name,
    this.platform,
    this.deviceType,
    required this.isRegistered,
    required this.isActive,
    this.verifiedAt,
    this.revokedAt,
    this.lastSeenAt,
    this.createdAt,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? '',
      uuid: json['uuid'] ?? '',
      name: json['name'],
      platform: json['platform'],
      deviceType: json['device_type'],
      isRegistered: json['is_registered'] ?? false,
      isActive: json['is_active'] ?? false,
      verifiedAt:
          json['verified_at'] != null
              ? DateTime.tryParse(json['verified_at'])
              : null,
      revokedAt:
          json['revoked_at'] != null
              ? DateTime.tryParse(json['revoked_at'])
              : null,
      lastSeenAt:
          json['last_seen_at'] != null
              ? DateTime.tryParse(json['last_seen_at'])
              : null,
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
