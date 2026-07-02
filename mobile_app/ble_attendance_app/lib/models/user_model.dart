class UserModel {
  final String id;
  final String organizationId;
  final String? departmentId;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final bool isActive;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.organizationId,
    this.departmentId,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    required this.isActive,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      organizationId: json['organization_id'] ?? '',
      departmentId: json['department_id'],
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      role: json['role'] ?? 'student',
      isActive: json['is_active'] ?? false,
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
