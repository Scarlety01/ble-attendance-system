class ClassStudentModel {
  final int id;
  final String organizationId;
  final String classOrShiftId;
  final String userId;
  final DateTime? createdAt;

  ClassStudentModel({
    required this.id,
    required this.organizationId,
    required this.classOrShiftId,
    required this.userId,
    this.createdAt,
  });

  factory ClassStudentModel.fromJson(Map<String, dynamic> json) {
    return ClassStudentModel(
      id: json['id'] ?? 0,
      organizationId: json['organization_id'] ?? '',
      classOrShiftId: json['class_or_shift_id'] ?? '',
      userId: json['user_id'] ?? '',
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null,
    );
  }
}
