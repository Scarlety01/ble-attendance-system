import 'package:flutter/material.dart';

import '../../models/teacher_session_summary_model.dart';
import '../../services/attendance_extra_api_service.dart';

class TeacherSessionSummaryScreen extends StatefulWidget {
  const TeacherSessionSummaryScreen({super.key});

  @override
  State<TeacherSessionSummaryScreen> createState() =>
      _TeacherSessionSummaryScreenState();
}

class _TeacherSessionSummaryScreenState
    extends State<TeacherSessionSummaryScreen> {
  final AttendanceExtraApiService _service = AttendanceExtraApiService();

  bool _loading = true;
  TeacherSessionSummaryResponse? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final summary = await _service.getTeacherSummary();

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Teacher summary алдаа: $e')));
    }
  }

  Widget _stat(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessions = _summary?.sessions ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Өнөөдрийн session summary',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Date: ${_summary?.today ?? '-'}'),
          const SizedBox(height: 16),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('Өнөөдрийн session байхгүй байна')),
            )
          else
            ...sessions.map((s) {
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            child: Icon(
                              s.isOpen
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s.className,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          Chip(label: Text('${s.attendanceRate}%')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Room: ${s.roomName}'),
                      Text('Session: ${s.sessionId}'),
                      Text('Time: ${s.startTime ?? '-'} - ${s.endTime ?? '-'}'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _stat(
                            'Total',
                            '${s.totalStudents}',
                            Icons.groups_rounded,
                          ),
                          _stat(
                            'Present',
                            '${s.present}',
                            Icons.check_circle_rounded,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _stat('Late', '${s.late}', Icons.schedule_rounded),
                          _stat('Absent', '${s.absent}', Icons.cancel_rounded),
                        ],
                      ),
                      Row(
                        children: [
                          _stat(
                            'Check-out',
                            '${s.checkedOut}',
                            Icons.logout_rounded,
                          ),
                          _stat(
                            s.isOpen ? 'Open' : 'Closed',
                            s.isOpen ? 'ON' : 'OFF',
                            s.isOpen
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
