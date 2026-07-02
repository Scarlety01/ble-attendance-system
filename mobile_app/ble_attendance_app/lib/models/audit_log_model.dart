class AuditLogModel {
  final int id;
  final String organizationId;
  final String? actorUserId;
  final String action;
  final String entityType;
  final String entityId;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final String? ipAddress;
  final DateTime? createdAt;

  AuditLogModel({
    required this.id,
    required this.organizationId,
    this.actorUserId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.oldValue,
    this.newValue,
    this.reason,
    this.ipAddress,
    this.createdAt,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] ?? 0,
      organizationId: json['organization_id'] ?? '',
      actorUserId: json['actor_user_id'],
      action: json['action'] ?? '',
      entityType: json['entity_type'] ?? '',
      entityId: json['entity_id'] ?? '',
      oldValue: json['old_value'],
      newValue: json['new_value'],
      reason: json['reason'],
      ipAddress: json['ip_address'],
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
