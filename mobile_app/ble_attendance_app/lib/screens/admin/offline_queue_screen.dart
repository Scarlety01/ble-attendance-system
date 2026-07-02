import 'package:flutter/material.dart';

import '../../services/attendance_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/notification_service.dart';

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  final LocalCacheService _cache = LocalCacheService();
  final AttendanceService _attendanceService = AttendanceService();
  final NotificationService _notificationService = NotificationService();

  bool _loading = true;
  bool _syncing = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _cache.getPendingAttendanceQueue();

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _syncAll() async {
    if (_syncing) return;

    setState(() => _syncing = true);

    try {
      final synced = await _attendanceService.syncPendingAttendances();
      await _load();

      _notificationService.add(
        title: 'Offline sync',
        message: '$synced бүртгэл sync хийгдлээ',
        type: synced > 0 ? 'success' : 'info',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$synced бүртгэл sync хийгдлээ')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync алдаа: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _deleteOne(int index) async {
    await _cache.removePendingAttendanceAt(index);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Queue item устгагдлаа')));
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Бүгдийг устгах уу?'),
            content: const Text(
              'Offline queue дээр байгаа бүх pending бүртгэл устах болно.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Болих'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Устгах'),
              ),
            ],
          ),
    );

    if (ok != true) return;

    await _cache.savePendingAttendanceQueue([]);
    await _load();
  }

  String _label(String type) {
    switch (type) {
      case 'check_in':
        return 'Check-in';
      case 'check_out':
        return 'Check-out';
      default:
        return type;
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'check_in':
        return Icons.login_rounded;
      case 'check_out':
        return Icons.logout_rounded;
      default:
        return Icons.cloud_off_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.cloud_off_rounded)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pending sync: ${_items.length}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _items.isEmpty || _syncing ? null : _syncAll,
            icon:
                _syncing
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync_rounded),
            label: Text(_syncing ? 'Sync хийж байна...' : 'Sync all'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _items.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear all'),
          ),
          const SizedBox(height: 16),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  'Offline queue хоосон байна',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final type = item['type']?.toString() ?? '-';
              final payload = Map<String, dynamic>.from(item['payload'] ?? {});
              final queuedAt = item['queued_at']?.toString() ?? '-';
              final lastError = item['last_error']?.toString();

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_icon(type))),
                  title: Text(
                    _label(type),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Session: ${payload['session_id'] ?? '-'}\n'
                      'Queued: $queuedAt'
                      '${lastError == null ? '' : '\nError: $lastError'}',
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _deleteOne(index),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
