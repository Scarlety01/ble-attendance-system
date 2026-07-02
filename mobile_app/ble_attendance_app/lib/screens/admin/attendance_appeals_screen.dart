import 'package:flutter/material.dart';

import '../../models/attendance_appeal_model.dart';
import '../../services/attendance_extra_api_service.dart';
import '../../services/auth_service.dart';

class AttendanceAppealsScreen extends StatefulWidget {
  const AttendanceAppealsScreen({super.key});

  @override
  State<AttendanceAppealsScreen> createState() =>
      _AttendanceAppealsScreenState();
}

class _AttendanceAppealsScreenState extends State<AttendanceAppealsScreen> {
  final AttendanceExtraApiService _service = AttendanceExtraApiService();
  final AuthService _auth = AuthService();

  bool _loading = true;
  String? _role;
  String _status = 'pending';
  List<AttendanceAppealModel> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final role = await _auth.getRole();
      final items = await _service.getAppeals(
        status: _status == 'all' ? null : _status,
      );

      if (!mounted) return;
      setState(() {
        _role = role;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Appeal уншихад алдаа: $e')));
    }
  }

  Future<void> _review(AttendanceAppealModel item, String status) async {
    final noteController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(
              status == 'approved' ? 'Approve хийх үү?' : 'Reject хийх үү?',
            ),
            content: TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Review note',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Болих'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Хадгалах'),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      await _service.reviewAppeal(
        appealId: item.id,
        status: status,
        reviewNote: noteController.text.trim(),
        correctionStatus: status == 'approved' ? 'present' : null,
        correctionNote: status == 'approved' ? 'Appeal approved' : null,
        correctionLateMinutes: status == 'approved' ? 0 : null,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Review алдаа: $e')));
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'approved':
        return cs.primary;
      case 'rejected':
        return cs.error;
      default:
        return cs.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final canReview = _role == 'admin' || _role == 'teacher';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'approved', label: Text('Approved')),
              ButtonSegment(value: 'rejected', label: Text('Rejected')),
              ButtonSegment(value: 'all', label: Text('All')),
            ],
            selected: {_status},
            onSelectionChanged: (value) async {
              setState(() => _status = value.first);
              await _load();
            },
          ),
          const SizedBox(height: 16),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('Appeal байхгүй байна')),
            )
          else
            ..._items.map((a) {
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            child: Icon(Icons.support_agent_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${a.userId} • ${a.sessionId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(a.status),
                            backgroundColor: _statusColor(
                              context,
                              a.status,
                            ).withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Reason: ${a.reasonType}'),
                      const SizedBox(height: 6),
                      Text(a.message),
                      if (a.reviewNote != null && a.reviewNote!.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text('Review: ${a.reviewNote}'),
                      ],
                      if (canReview && a.status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _review(a, 'rejected'),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _review(a, 'approved'),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                      ],
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
