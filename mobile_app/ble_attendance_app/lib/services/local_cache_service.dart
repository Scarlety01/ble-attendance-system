import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalCacheService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _roleKey = 'role';
  static const _orgIdKey = 'organization_id';
  static const _pendingAttendanceKey = 'pending_attendance_queue';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> saveAuth({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String role,
    required String organizationId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_roleKey, role);
    await prefs.setString(_orgIdKey, organizationId);
  }

  Future<String?> getAccessToken() async {
    return _secureStorage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  Future<String?> getOrganizationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_orgIdKey);
  }

  Future<List<Map<String, dynamic>>> getPendingAttendanceQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingAttendanceKey) ?? [];
    return raw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
  }

  Future<void> savePendingAttendanceQueue(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = items.map(jsonEncode).toList();
    await prefs.setStringList(_pendingAttendanceKey, raw);
  }

  Future<void> enqueuePendingAttendance(Map<String, dynamic> item) async {
    final items = await getPendingAttendanceQueue();
    items.add(item);
    await savePendingAttendanceQueue(items);
  }

  Future<void> removePendingAttendanceAt(int index) async {
    final items = await getPendingAttendanceQueue();
    if (index >= 0 && index < items.length) {
      items.removeAt(index);
      await savePendingAttendanceQueue(items);
    }
  }

  Future<void> clearPendingAttendanceQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingAttendanceKey);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_orgIdKey);
    await prefs.remove(_pendingAttendanceKey);
  }
}
