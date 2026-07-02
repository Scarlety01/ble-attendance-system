class BeaconModel {
  final String id;
  final String organizationId;
  final String? roomId;
  final String uuid;
  final String? major;
  final String? minor;
  final String name;
  final String? advertiserType;
  final int? txPower;
  final double thresholdDistance;
  final bool isActive;
  final DateTime? createdAt;

  BeaconModel({
    required this.id,
    required this.organizationId,
    this.roomId,
    required this.uuid,
    this.major,
    this.minor,
    required this.name,
    this.advertiserType,
    this.txPower,
    required this.thresholdDistance,
    required this.isActive,
    this.createdAt,
  });

  factory BeaconModel.fromJson(Map<String, dynamic> json) {
    return BeaconModel(
      id: json['id'] ?? '',
      organizationId: json['organization_id'] ?? '',
      roomId: json['room_id'],
      uuid: json['uuid'] ?? '',
      major: json['major'],
      minor: json['minor'],
      name: json['name'] ?? '',
      advertiserType: json['advertiser_type'],
      txPower: json['tx_power'],
      thresholdDistance:
          json['threshold_distance'] is num
              ? (json['threshold_distance'] as num).toDouble()
              : 2.0,
      isActive: json['is_active'] ?? false,
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
