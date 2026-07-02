import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../services/report_api_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

enum _ExportType { excel, pdf }

class _ReportScreenState extends State<ReportScreen> {
  final ReportApiService _reportService = ReportApiService();

  bool _loading = true;
  _ExportType? _activeExport;

  bool get _exportingExcel => _activeExport == _ExportType.excel;
  bool get _exportingPdf => _activeExport == _ExportType.pdf;
  bool get _isExporting => _activeExport != null;

  String? _error;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _report;

  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadData();
  }

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024, 1),
      lastDate: DateTime(2030, 12),
      helpText: 'Сарын тайлан сонгох',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked == null) return;

    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
    });

    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _reportService.getMonthlySummary(_monthKey);
      final report = await _reportService.getMonthlyReport(_monthKey);

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _report = report;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showExportBusyMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Өмнөх экспорт дуусаагүй байна. Түр хүлээнэ үү.'),
      ),
    );
  }

  Future<void> _exportExcel() async {
    if (_isExporting) {
      _showExportBusyMessage();
      return;
    }

    setState(() => _activeExport = _ExportType.excel);

    try {
      final bytes = await _reportService.downloadExcel(_monthKey);

      if (bytes.isEmpty) {
        throw Exception('Файл хоосон байна');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/attendance_$_monthKey.xlsx');

      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      // Share sheet нээхээс ӨМНӨ loading-г унтраана.
      // Ингэхгүй бол iOS дээр Share.shareXFiles удаан хүлээгдээд
      // "Excel татаж байна..." гэж гацсан мэт харагддаг.
      setState(() => _activeExport = null);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Excel тайлан бэлэн боллоо. Save to Files сонгоно уу.'),
        ),
      );

      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'attendance_$_monthKey.xlsx',
        ),
      ], text: 'Ирцийн Excel тайлан $_monthKey');
    } catch (e) {
      if (!mounted) return;

      setState(() => _activeExport = null);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel экспортын алдаа: $e')));
    } finally {
      if (mounted && _activeExport == _ExportType.excel) {
        setState(() => _activeExport = null);
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_isExporting) {
      _showExportBusyMessage();
      return;
    }

    setState(() => _activeExport = _ExportType.pdf);

    try {
      final bytes = await _reportService.downloadPdf(_monthKey);

      if (bytes.isEmpty) {
        throw Exception('Файл хоосон байна');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/attendance_$_monthKey.pdf');

      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      // Share sheet нээхээс ӨМНӨ loading-г унтраана.
      setState(() => _activeExport = null);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF тайлан бэлэн боллоо. Save to Files сонгоно уу.'),
        ),
      );

      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: 'attendance_$_monthKey.pdf',
        ),
      ], text: 'Ирцийн PDF тайлан $_monthKey');
    } catch (e) {
      if (!mounted) return;

      setState(() => _activeExport = null);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF экспортын алдаа: $e')));
    } finally {
      if (mounted && _activeExport == _ExportType.pdf) {
        setState(() => _activeExport = null);
      }
    }
  }

  Color _statusColor(String status, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'present':
        return cs.primary;
      case 'late':
        return cs.tertiary;
      case 'absent':
        return cs.error;
      default:
        return cs.secondary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Icons.check_circle;
      case 'late':
        return Icons.schedule;
      case 'absent':
        return Icons.cancel;
      default:
        return Icons.analytics;
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    return value;
  }

  Widget _buildTopCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            CircleAvatar(radius: 22, child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(
    BuildContext context,
    String status,
    int count,
    int total,
  ) {
    final color = _statusColor(status, context);
    final progress = total == 0 ? 0.0 : count / total;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(_statusIcon(status), color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportButton({
    required bool isActive,
    required IconData icon,
    required String label,
    required Future<void> Function() onPressed,
  }) {
    return FilledButton.icon(
      onPressed: (_loading || _isExporting) ? null : onPressed,
      icon:
          isActive
              ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Icon(icon),
      label: Text(isActive ? '$label татаж байна...' : label),
    );
  }

  Widget _buildExportButtons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _exportButton(
          isActive: _exportingExcel,
          icon: Icons.table_view,
          label: 'Excel',
          onPressed: _exportExcel,
        ),
        _exportButton(
          isActive: _exportingPdf,
          icon: Icons.picture_as_pdf,
          label: 'PDF',
          onPressed: _exportPdf,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Алдаа: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Дахин оролдох'),
              ),
            ],
          ),
        ),
      );
    }

    final summaryList = List<Map<String, dynamic>>.from(
      _summary?['summary'] ?? [],
    );
    final records = List<Map<String, dynamic>>.from(_report?['records'] ?? []);
    final total = (_report?['total'] ?? 0) as int;

    final presentCount = summaryList
        .where(
          (e) => (e['status']?.toString().toLowerCase() ?? '') == 'present',
        )
        .fold<int>(0, (a, b) => a + ((b['count'] ?? 0) as int));

    final lateCount = summaryList
        .where((e) => (e['status']?.toString().toLowerCase() ?? '') == 'late')
        .fold<int>(0, (a, b) => a + ((b['count'] ?? 0) as int));

    return RefreshIndicator(
      onRefresh: _isExporting ? () async {} : _loadData,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Сарын тайлан',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Сонгосон сар: $_monthKey',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isExporting ? null : _pickMonth,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Сар сонгох'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildExportButtons(),
                ],
              ),
            ),
          ),
          _buildTopCard(
            icon: Icons.dataset,
            title: 'Нийт бүртгэл',
            value: '$total',
          ),
          _buildTopCard(
            icon: Icons.check_circle,
            title: 'Ирсэн',
            value: '$presentCount',
          ),
          _buildTopCard(
            icon: Icons.schedule,
            title: 'Хоцорсон',
            value: '$lateCount',
          ),
          const SizedBox(height: 8),
          const Text(
            'Төлөвийн задлал',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (summaryList.isEmpty)
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Summary хоосон байна'),
              ),
            ),
          ...summaryList.map((item) {
            final status = item['status']?.toString() ?? '-';
            final count = (item['count'] ?? 0) as int;
            return _buildSummaryBar(context, status, count, total);
          }),
          const SizedBox(height: 12),
          const Text(
            'Сүүлийн бүртгэлүүд',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Дэлгэрэнгүй бүртгэл алга'),
              ),
            ),
          ...records
              .take(20)
              .map(
                (item) => Card(
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        _statusIcon(item['status']?.toString() ?? ''),
                      ),
                    ),
                    title: Text(
                      'User: ${item['user_id'] ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Session: ${item['session_id'] ?? '-'}\n'
                        'Status: ${item['status'] ?? '-'}\n'
                        'Date: ${_formatDate(item['date']?.toString())}',
                      ),
                    ),
                    isThreeLine: true,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _statusColor(
                          item['status']?.toString() ?? '',
                          context,
                        ).withValues(alpha: 0.12),
                      ),
                      child: Text(
                        '${item['late_minutes'] ?? 0} мин',
                        style: TextStyle(
                          color: _statusColor(
                            item['status']?.toString() ?? '',
                            context,
                          ),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
