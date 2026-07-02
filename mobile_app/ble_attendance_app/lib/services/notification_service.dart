import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';

class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  static const String _storageKey = 'app_notifications';
  static const int _maxItems = 100;

  final List<AppNotification> _items = [];
  int _counter = 0;
  bool _initialized = false;

  List<AppNotification> get items => List.unmodifiable(_items.reversed);

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items
            ..clear()
            ..addAll(
              decoded.whereType<Map>().map(
                (e) => AppNotification.fromJson(Map<String, dynamic>.from(e)),
              ),
            );
        }
      } catch (_) {
        await prefs.remove(_storageKey);
      }
    }

    _counter = _items.fold<int>(0, (maxId, item) {
      final parsed = int.tryParse(item.id) ?? 0;
      return parsed > maxId ? parsed : maxId;
    });

    _initialized = true;
  }

  NotificationType _mapType(String type) {
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

  void add({
    required String title,
    required String message,
    String type = 'info',
  }) {
    final now = DateTime.now();
    final notificationType = _mapType(type);

    // Ижил алдааны мэдэгдэл BLE scan давталтаар олон дахин үүсэхээс хамгаална.
    final hasRecentDuplicate = _items.any((item) {
      return item.title == title &&
          item.message == message &&
          item.type == notificationType &&
          now.difference(item.createdAt).inMinutes < 10;
    });

    if (hasRecentDuplicate) return;

    _counter++;

    _items.add(
      AppNotification(
        id: _counter.toString(),
        title: title,
        message: message,
        createdAt: now,
        type: notificationType,
        isRead: false,
      ),
    );

    if (_items.length > _maxItems) {
      _items.removeRange(0, _items.length - _maxItems);
    }

    _schedulePersist();
  }

  void clearByType(NotificationType type) {
    _items.removeWhere((item) => item.type == type);
    _schedulePersist();
  }

  void markAsRead(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;

    _items[index] = _items[index].copyWith(isRead: true);
    _schedulePersist();
  }

  void markAllAsRead() {
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
    _schedulePersist();
  }

  void remove(String id) {
    _items.removeWhere((item) => item.id == id);
    _schedulePersist();
  }

  void clear() {
    _items.clear();
    _schedulePersist();
  }

  void _schedulePersist() {
    Future<void>.microtask(_persist);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}
