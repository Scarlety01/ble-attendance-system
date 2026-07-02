class RoomModel {
  final String id;
  final String organizationId;
  final String name;
  final String? building;
  final String? floor;
  final int? capacity;
  final String? description;
  final DateTime? createdAt;

  RoomModel({
    required this.id,
    required this.organizationId,
    required this.name,
    this.building,
    this.floor,
    this.capacity,
    this.description,
    this.createdAt,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] ?? '',
      organizationId: json['organization_id'] ?? '',
      name: json['name'] ?? '',
      building: json['building'],
      floor: json['floor'],
      capacity: json['capacity'],
      description: json['description'],
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
