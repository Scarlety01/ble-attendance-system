import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/audit_log_model.dart';
import '../services/admin_api_service.dart';

enum AuditDateFilter { all, today, last7Days, last30Days, custom }

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AdminApiService _adminService = AdminApiService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _searchText = '';
  String _selectedAction = 'all';
  String _selectedEntityType = 'all';
  AuditDateFilter _dateFilter = AuditDateFilter.all;
  DateTimeRange? _customRange;
  List<AuditLogModel> _items = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
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

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final logs = await _adminService.getAuditLogs();
      if (!mounted) return;
      setState(() => _items = logs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _actions {
    final values =
        _items.map((e) => e.action).where((e) => e.isNotEmpty).toSet().toList();
    values.sort();
    return ['all', ...values];
  }

  List<String> get _entityTypes {
    final values =
        _items
            .map((e) => e.entityType)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
    values.sort();
    return ['all', ...values];
  }

  List<AuditLogModel> get _filteredItems {
    final list =
        _items.where((item) {
          final haystack =
              [
                item.actorUserId,
                item.action,
                item.entityType,
                item.entityId,
                item.reason,
                item.ipAddress,
                item.oldValue,
                item.newValue,
              ].whereType<String>().join(' ').toLowerCase();

          final matchesSearch =
              _searchText.isEmpty || haystack.contains(_searchText);
          final matchesAction =
              _selectedAction == 'all' || item.action == _selectedAction;
          final matchesEntity =
              _selectedEntityType == 'all' ||
              item.entityType == _selectedEntityType;
          final matchesDate = _matchesDateFilter(item.createdAt);

          return matchesSearch && matchesAction && matchesEntity && matchesDate;
        }).toList();

    list.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  int get _todayCount {
    final now = DateTime.now();
    return _items
        .where((e) => e.createdAt != null && _isSameDate(e.createdAt!, now))
        .length;
  }

  int get _userActionCount =>
      _items.where((e) => e.entityType.toLowerCase().contains('user')).length;

  int get _attendanceActionCount =>
      _items
          .where((e) => e.entityType.toLowerCase().contains('attendance'))
          .length;

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _matchesDateFilter(DateTime? createdAt) {
    if (createdAt == null) return _dateFilter == AuditDateFilter.all;

    final itemDate = _dateOnly(createdAt.toLocal());
    final today = _dateOnly(DateTime.now());

    switch (_dateFilter) {
      case AuditDateFilter.all:
        return true;
      case AuditDateFilter.today:
        return _isSameDate(createdAt.toLocal(), DateTime.now());
      case AuditDateFilter.last7Days:
        final start = today.subtract(const Duration(days: 6));
        return !itemDate.isBefore(start) && !itemDate.isAfter(today);
      case AuditDateFilter.last30Days:
        final start = today.subtract(const Duration(days: 29));
        return !itemDate.isBefore(start) && !itemDate.isAfter(today);
      case AuditDateFilter.custom:
        final range = _customRange;
        if (range == null) return true;
        final start = _dateOnly(range.start);
        final end = _dateOnly(range.end);
        return !itemDate.isBefore(start) && !itemDate.isAfter(end);
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: _customRange ?? DateTimeRange(start: now, end: now),
      helpText: 'Audit log огноо сонгох',
      saveText: 'Сонгох',
    );

    if (picked == null) return;

    setState(() {
      _customRange = picked;
      _dateFilter = AuditDateFilter.custom;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchText = '';
      _selectedAction = 'all';
      _selectedEntityType = 'all';
      _dateFilter = AuditDateFilter.all;
      _customRange = null;
    });
  }

  String _dateFilterLabel(AuditDateFilter filter) {
    switch (filter) {
      case AuditDateFilter.all:
        return 'Бүх огноо';
      case AuditDateFilter.today:
        return 'Өнөөдөр';
      case AuditDateFilter.last7Days:
        return '7 хоног';
      case AuditDateFilter.last30Days:
        return '30 хоног';
      case AuditDateFilter.custom:
        if (_customRange == null) return 'Custom';
        final start = _customRange!.start;
        final end = _customRange!.end;
        return '${start.month}/${start.day} - ${end.month}/${end.day}';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _prettyJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  IconData _entityIcon(String entityType) {
    final value = entityType.toLowerCase();
    if (value.contains('user')) return Icons.person_outline;
    if (value.contains('device')) return Icons.devices_outlined;
    if (value.contains('attendance')) return Icons.fact_check_outlined;
    if (value.contains('class')) return Icons.school_outlined;
    if (value.contains('room')) return Icons.meeting_room_outlined;
    return Icons.history_edu_outlined;
  }

  Color _actionColor(BuildContext context, String action) {
    final cs = Theme.of(context).colorScheme;
    final lower = action.toLowerCase();

    if (lower.contains('delete') || lower.contains('remove')) {
      return cs.error;
    }

    if (lower.contains('update') || lower.contains('manual')) {
      return cs.tertiary;
    }

    if (lower.contains('create') ||
        lower.contains('add') ||
        lower.contains('enroll')) {
      return cs.primary;
    }

    return cs.secondary;
  }

  void _showLogDetail(AuditLogModel log) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Icon(_entityIcon(log.entityType))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.action,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${log.entityType} • ${log.entityId}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _DetailRow(label: 'Actor', value: log.actorUserId ?? '-'),
                _DetailRow(label: 'Action', value: log.action),
                _DetailRow(label: 'Entity type', value: log.entityType),
                _DetailRow(label: 'Entity ID', value: log.entityId),
                _DetailRow(label: 'Reason', value: log.reason ?? '-'),
                _DetailRow(label: 'IP address', value: log.ipAddress ?? '-'),
                _DetailRow(label: 'Created', value: _formatDate(log.createdAt)),
                const SizedBox(height: 14),
                _JsonBlock(
                  title: 'Old value',
                  value: _prettyJson(log.oldValue),
                ),
                const SizedBox(height: 12),
                _JsonBlock(
                  title: 'New value',
                  value: _prettyJson(log.newValue),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SearchBar(
        controller: _searchController,
        hintText: 'Actor, action, entity, reason хайх',
        leading: const Icon(Icons.search_rounded),
        trailing:
            _searchText.isNotEmpty
                ? [
                  IconButton(
                    onPressed: () => _searchController.clear(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]
                : null,
      ),
    );
  }

  Widget _buildActionEntityFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
          final itemWidth =
              isNarrow ? constraints.maxWidth : (constraints.maxWidth - 10) / 2;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: itemWidth,
                child: DropdownButtonFormField<String>(
                  value: _selectedAction,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Action',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items:
                      _actions.map((action) {
                        return DropdownMenuItem(
                          value: action,
                          child: Text(
                            action == 'all' ? 'Бүх action' : action,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedAction = value);
                  },
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: DropdownButtonFormField<String>(
                  value: _selectedEntityType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Entity',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items:
                      _entityTypes.map((entity) {
                        return DropdownMenuItem(
                          value: entity,
                          child: Text(
                            entity == 'all' ? 'Бүх entity' : entity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedEntityType = value);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<AuditDateFilter>(
              value: _dateFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Огноо',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items:
                  AuditDateFilter.values.map((filter) {
                    return DropdownMenuItem(
                      value: filter,
                      child: Text(
                        _dateFilterLabel(filter),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
              onChanged: (value) async {
                if (value == null) return;
                if (value == AuditDateFilter.custom) {
                  await _pickCustomDateRange();
                } else {
                  setState(() => _dateFilter = value);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.outlined(
              tooltip: 'Filter цэвэрлэх',
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadLogs,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Audit log ачааллахад алдаа гарлаа',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('Дахин ачаалах'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _AuditSummaryCard(
              total: _items.length,
              today: _todayCount,
              userActions: _userActionCount,
              attendanceActions: _attendanceActionCount,
            ),
          ),
          _buildSearchBar(),
          _buildActionEntityFilters(),
          _buildDateFilter(),
          Expanded(
            child:
                items.isEmpty
                    ? _EmptyAuditLogView(
                      hasActiveFilter:
                          _searchText.isNotEmpty ||
                          _selectedAction != 'all' ||
                          _selectedEntityType != 'all' ||
                          _dateFilter != AuditDateFilter.all,
                      onClearFilters: _clearFilters,
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _AuditLogCard(
                          log: item,
                          color: _actionColor(context, item.action),
                          icon: _entityIcon(item.entityType),
                          formattedDate: _formatDate(item.createdAt),
                          onTap: () => _showLogDetail(item),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _AuditSummaryCard extends StatelessWidget {
  final int total;
  final int today;
  final int userActions;
  final int attendanceActions;

  const _AuditSummaryCard({
    required this.total,
    required this.today,
    required this.userActions,
    required this.attendanceActions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.admin_panel_settings, color: cs.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Audit Log',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Нийт',
                    value: '$total',
                    icon: Icons.list_alt,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Өнөөдөр',
                    value: '$today',
                    icon: Icons.today,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'User',
                    value: '$userActions',
                    icon: Icons.person,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Ирц',
                    value: '$attendanceActions',
                    icon: Icons.fact_check,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  final AuditLogModel log;
  final Color color;
  final IconData icon;
  final String formattedDate;
  final VoidCallback onTap;

  const _AuditLogCard({
    required this.log,
    required this.color,
    required this.icon,
    required this.formattedDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.action,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${log.entityType} • ${log.entityId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ChipLabel(
                          icon: Icons.person_outline,
                          label: log.actorUserId ?? 'system',
                        ),
                        _ChipLabel(
                          icon: Icons.schedule_rounded,
                          label: formattedDate,
                        ),
                        if ((log.reason ?? '').isNotEmpty)
                          _ChipLabel(
                            icon: Icons.notes_rounded,
                            label: log.reason!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ChipLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final String title;
  final String value;

  const _JsonBlock({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

class _EmptyAuditLogView extends StatelessWidget {
  final bool hasActiveFilter;
  final VoidCallback onClearFilters;

  const _EmptyAuditLogView({
    required this.hasActiveFilter,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 56),
        Icon(Icons.manage_search_outlined, size: 56, color: cs.outline),
        const SizedBox(height: 16),
        const Text(
          'Audit log олдсонгүй',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          hasActiveFilter
              ? 'Хайлтын утга эсвэл filter таарах бичлэг алга.'
              : 'Одоогоор audit log бүртгэгдээгүй байна.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        if (hasActiveFilter) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Filter цэвэрлэх'),
            ),
          ),
        ],
      ],
    );
  }
}
