import 'package:flutter/material.dart';

import '../models/attendance_event.dart';
import '../services/auth_service.dart';
import '../services/history_api_service.dart';
import 'attendance_appeal_sheet.dart';

enum HistoryStatusFilter { all, present, late, checkedOut, absent }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryApiService _historyService = HistoryApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;

  List<AttendanceEvent> _items = [];

  DateTime? _fromDate;
  DateTime? _toDate;

  String? _userId;
  String? _role;

  HistoryStatusFilter _statusFilter = HistoryStatusFilter.all;
  String _searchText = '';

  bool get _isAdminOrTeacher => _role == 'admin' || _role == 'teacher';
  bool get _isStudent => _role == 'student';

  @override
  void initState() {
    super.initState();

    _loadHistory();

    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? _toApiDate(DateTime? dt) {
    if (dt == null) return null;

    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String? _apiStatus() {
    switch (_statusFilter) {
      case HistoryStatusFilter.all:
        return null;
      case HistoryStatusFilter.present:
        return 'present';
      case HistoryStatusFilter.late:
        return 'late';
      case HistoryStatusFilter.checkedOut:
        return 'checked_out';
      case HistoryStatusFilter.absent:
        return 'absent';
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = await _authService.getUserId();
      final role = await _authService.getRole();

      if (userId == null || userId.isEmpty) {
        throw Exception('User ID олдсонгүй');
      }

      final status = _apiStatus();

      List<AttendanceEvent> history;

      if (role == 'admin' || role == 'teacher') {
        history = await _historyService.getAllAttendance(
          fromDate: _toApiDate(_fromDate),
          toDate: _toApiDate(_toDate),
          status: status,
        );
      } else {
        history = await _historyService.getHistory(
          userId,
          fromDate: _toApiDate(_fromDate),
          toDate: _toApiDate(_toDate),
          status: status,
        );
      }

      history.sort((a, b) {
        final aTime = a.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;

      setState(() {
        _userId = userId;
        _role = role;
        _items = _filterItemsLocally(history);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _normalizeSessionId(String sessionId) {
    final parts = sessionId.split('_');

    if (parts.length >= 2) {
      final last = parts.last;
      final isDateSuffix = RegExp(r'^\d{8}$').hasMatch(last);

      if (isDateSuffix) {
        return parts.sublist(0, parts.length - 1).join('_');
      }
    }

    return sessionId;
  }

  List<AttendanceEvent> _filterItemsLocally(List<AttendanceEvent> source) {
    final filtered =
        source.where((item) {
          final checkIn = item.checkInTime;

          if (checkIn != null) {
            final checkDate = DateTime(
              checkIn.year,
              checkIn.month,
              checkIn.day,
            );

            if (_fromDate != null) {
              final from = DateTime(
                _fromDate!.year,
                _fromDate!.month,
                _fromDate!.day,
              );

              if (checkDate.isBefore(from)) return false;
            }

            if (_toDate != null) {
              final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);

              if (checkDate.isAfter(to)) return false;
            }
          }

          if (_searchText.isNotEmpty) {
            final target =
                '${item.userId} ${item.sessionId} ${item.status ?? ''} ${item.detectionMethod ?? ''} ${item.note ?? ''}'
                    .toLowerCase();

            if (!target.contains(_searchText)) return false;
          }

          return true;
        }).toList();

    final Map<String, AttendanceEvent> firstBySessionUserAndDate = {};

    for (final item in filtered) {
      final normalizedSessionId = _normalizeSessionId(item.sessionId);

      // Backend daily session ID ашигладаг: SESSION002_YYYYMMDD.
      // Өмнөх код зөвхөн session + user-ээр key үүсгэснээс олон өдрийн ирц
      // нэг мөр болж алга болдог байсан. Одоо огноог key-д заавал оруулна.
      final checkDate = item.checkInTime?.toLocal();
      final dateKey =
          checkDate == null
              ? item.sessionId
              : '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';

      final key = '${normalizedSessionId}_${item.userId}_$dateKey';

      final existing = firstBySessionUserAndDate[key];

      if (existing == null) {
        firstBySessionUserAndDate[key] = item;
        continue;
      }

      final existingTime =
          existing.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final currentTime =
          item.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (currentTime.isBefore(existingTime)) {
        firstBySessionUserAndDate[key] = item;
      }
    }

    final result = firstBySessionUserAndDate.values.toList();

    result.sort((a, b) {
      final aTime = a.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return result;
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1),
      lastDate: DateTime(2030, 12),
      helpText: 'Эхлэх огноо',
    );

    if (picked == null) return;

    setState(() => _fromDate = picked);
    await _loadHistory();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1),
      lastDate: DateTime(2030, 12),
      helpText: 'Дуусах огноо',
    );

    if (picked == null) return;

    setState(() => _toDate = picked);
    await _loadHistory();
  }

  Future<void> _clearFilter() async {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _statusFilter = HistoryStatusFilter.all;
      _searchController.clear();
      _searchText = '';
    });

    await _loadHistory();
  }

  Future<void> _openAppealSheet(AttendanceEvent item) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) {
        return AttendanceAppealSheet(attendance: item);
      },
    );

    if (result == true) {
      await _loadHistory();
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';

    final local = date.toLocal();

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatOnlyDate(DateTime? date) {
    if (date == null) return '-';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'teacher':
        return 'Teacher';
      case 'student':
        return 'Student';
      default:
        return 'User';
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'teacher':
        return Icons.school_rounded;
      case 'student':
        return Icons.person_rounded;
      default:
        return Icons.account_circle_rounded;
    }
  }

  Color _statusColor(String? status, BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    switch ((status ?? '').toLowerCase()) {
      case 'present':
        return cs.primary;
      case 'late':
        return cs.tertiary;
      case 'absent':
        return cs.error;
      case 'checked_out':
        return cs.secondary;
      default:
        return cs.outline;
    }
  }

  IconData _statusIcon(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'present':
        return Icons.check_circle_rounded;
      case 'late':
        return Icons.schedule_rounded;
      case 'absent':
        return Icons.cancel_rounded;
      case 'checked_out':
        return Icons.logout_rounded;
      default:
        return Icons.fact_check_rounded;
    }
  }

  String _statusLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'present':
        return 'present';
      case 'late':
        return 'late';
      case 'absent':
        return 'absent';
      case 'checked_out':
        return 'checked-out';
      default:
        return status ?? '-';
    }
  }

  String _statusFilterLabel(HistoryStatusFilter filter) {
    switch (filter) {
      case HistoryStatusFilter.all:
        return 'Бүгд';
      case HistoryStatusFilter.present:
        return 'Ирсэн';
      case HistoryStatusFilter.late:
        return 'Хоцорсон';
      case HistoryStatusFilter.checkedOut:
        return 'Check-out';
      case HistoryStatusFilter.absent:
        return 'Тасалсан';
    }
  }

  Widget _buildFilterCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                CircleAvatar(child: Icon(Icons.filter_alt_rounded)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Огноо болон төлөвөөр шүүх',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            SearchBar(
              controller: _searchController,
              hintText:
                  _isAdminOrTeacher
                      ? 'User ID, session, status хайх'
                      : 'Session, status хайх',
              leading: const Icon(Icons.search_rounded),
              trailing:
                  _searchText.isNotEmpty
                      ? [
                        IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchText = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ]
                      : null,
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromDate,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text('Эхлэх: ${_formatOnlyDate(_fromDate)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickToDate,
                    icon: const Icon(Icons.event_rounded),
                    label: Text('Дуусах: ${_formatOnlyDate(_toDate)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            DropdownButtonFormField<HistoryStatusFilter>(
              value: _statusFilter,
              decoration: const InputDecoration(
                labelText: 'Төлөв',
                border: OutlineInputBorder(),
              ),
              items:
                  HistoryStatusFilter.values.map((filter) {
                    return DropdownMenuItem(
                      value: filter,
                      child: Text(_statusFilterLabel(filter)),
                    );
                  }).toList(),
              onChanged: (value) async {
                if (value == null) return;

                setState(() => _statusFilter = value);
                await _loadHistory();
              },
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearFilter,
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: const Text('Цэвэрлэх'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loadHistory,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _isAdminOrTeacher
                    ? 'Нийт: ${_items.length} бичлэг • Admin/Teacher эрхтэй тул student болон teacher ирц харагдана.'
                    : 'Нийт: ${_items.length} бичлэг',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, AttendanceEvent item) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(item.status, context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showAttendanceDetail(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(_statusIcon(item.status), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session:',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.sessionId,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(_statusLabel(item.status)),
                      backgroundColor: color.withValues(alpha: 0.10),
                      labelStyle: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                      side: BorderSide.none,
                    ),
                    const SizedBox(height: 8),
                    if (_isAdminOrTeacher) ...[
                      Text(
                        'User: ${item.userId}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text('Check-in: ${_formatDate(item.checkInTime)}'),
                    Text('Check-out: ${_formatDate(item.checkOutTime)}'),
                    Text('RSSI: ${item.rssi ?? '-'}'),
                    Text(
                      'Distance: ${item.distanceM == null ? '-' : '${item.distanceM!.toStringAsFixed(2)} m'}',
                    ),
                    Text('Method: ${item.detectionMethod ?? '-'}'),
                    if ((item.note ?? '').isNotEmpty)
                      Text('Note: ${item.note}'),

                    if (_isStudent) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _openAppealSheet(item),
                        icon: const Icon(Icons.support_agent_rounded),
                        label: const Text('Ирц засуулах хүсэлт'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttendanceDetail(AttendanceEvent item) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.42,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Icon(_statusIcon(item.status))),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ирцийн дэлгэрэнгүй',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _DetailRow(label: 'ID', value: '${item.id ?? '-'}'),
                _DetailRow(label: 'User', value: item.userId),
                _DetailRow(label: 'Session', value: item.sessionId),
                _DetailRow(label: 'Status', value: _statusLabel(item.status)),
                _DetailRow(
                  label: 'Check-in',
                  value: _formatDate(item.checkInTime),
                ),
                _DetailRow(
                  label: 'Check-out',
                  value: _formatDate(item.checkOutTime),
                ),
                _DetailRow(label: 'RSSI', value: '${item.rssi ?? '-'}'),
                _DetailRow(
                  label: 'Distance',
                  value:
                      item.distanceM == null
                          ? '-'
                          : '${item.distanceM!.toStringAsFixed(2)} m',
                ),
                _DetailRow(label: 'Method', value: item.detectionMethod ?? '-'),
                _DetailRow(
                  label: 'Late min',
                  value: '${item.lateMinutes ?? 0}',
                ),
                _DetailRow(label: 'Note', value: item.note ?? '-'),
                if (_isStudent) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openAppealSheet(item);
                    },
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Ирц засуулах хүсэлт илгээх'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyView() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.manage_search_rounded, size: 70),
            SizedBox(height: 16),
            Text(
              'Ирцийн бичлэг олдсонгүй',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Filter эсвэл хайлтын утгаа өөрчилж үзнэ үү.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56),
            const SizedBox(height: 12),
            const Text(
              'History уншихад алдаа гарлаа',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(_error ?? '-', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Дахин оролдох'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorView();
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildFilterCard(context),
          if (_items.isEmpty)
            _buildEmptyView()
          else
            ..._items.map((item) => _buildHistoryCard(context, item)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
