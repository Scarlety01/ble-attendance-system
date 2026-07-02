import 'package:flutter/material.dart';

enum NotificationType { success, error, warning, info, attendance }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final NotificationType type;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.type,
    this.isRead = false,
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? createdAt,
    NotificationType? type,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      type: _mapType(json['type'] as String? ?? 'info'),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'created_at': createdAt.toIso8601String(),
      'type': type.name,
      'is_read': isRead,
    };
  }

  static NotificationType _mapType(String type) {
    switch (type) {
      case 'success':
        return NotificationType.success;
      case 'error':
        return NotificationType.error;
      case 'warning':
        return NotificationType.warning;
      case 'attendance':
        return NotificationType.attendance;
      default:
        return NotificationType.info;
    }
  }
}

IconData notificationIcon(NotificationType type) {
  switch (type) {
    case NotificationType.success:
      return Icons.check_circle_rounded;
    case NotificationType.error:
      return Icons.error_rounded;
    case NotificationType.warning:
      return Icons.warning_amber_rounded;
    case NotificationType.attendance:
      return Icons.bluetooth_connected_rounded;
    case NotificationType.info:
      return Icons.info_rounded;
  }
}

Color notificationColor(BuildContext context, NotificationType type) {
  final cs = Theme.of(context).colorScheme;
  switch (type) {
    case NotificationType.success:
      return cs.primary;
    case NotificationType.error:
      return cs.error;
    case NotificationType.warning:
      return cs.tertiary;
    case NotificationType.attendance:
      return cs.secondary;
    case NotificationType.info:
      return cs.outline;
  }
}

String notificationTypeLabel(NotificationType type) {
  switch (type) {
    case NotificationType.success:
      return 'Амжилттай';
    case NotificationType.error:
      return 'Алдаа';
    case NotificationType.warning:
      return 'Анхааруулга';
    case NotificationType.attendance:
      return 'Ирц';
    case NotificationType.info:
      return 'Мэдээлэл';
  }
}
