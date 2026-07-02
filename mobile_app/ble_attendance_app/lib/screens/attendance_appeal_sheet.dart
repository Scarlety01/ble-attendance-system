import 'package:flutter/material.dart';

import '../models/attendance_event.dart';
import '../services/attendance_extra_api_service.dart';

class AttendanceAppealSheet extends StatefulWidget {
  final AttendanceEvent attendance;

  const AttendanceAppealSheet({super.key, required this.attendance});

  @override
  State<AttendanceAppealSheet> createState() => _AttendanceAppealSheetState();
}

class _AttendanceAppealSheetState extends State<AttendanceAppealSheet> {
  final AttendanceExtraApiService _service = AttendanceExtraApiService();
  final TextEditingController _messageController = TextEditingController();

  bool _submitting = false;

  String _reasonType = 'ble_not_detected';

  final List<_ReasonOption> _reasons = const [
    _ReasonOption(value: 'ble_not_detected', label: 'BLE уншаагүй'),
    _ReasonOption(value: 'wrong_status', label: 'Ирцийн төлөв буруу'),
    _ReasonOption(value: 'wrong_time', label: 'Цаг буруу бүртгэгдсэн'),
    _ReasonOption(value: 'device_issue', label: 'Төхөөрөмжийн асуудал'),
    _ReasonOption(value: 'other', label: 'Бусад'),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();

    if (message.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Тайлбар оруулна уу')));
      return;
    }

    setState(() => _submitting = true);

    try {
      await _service.createAppeal(
        attendanceId: widget.attendance.id,
        sessionId: widget.attendance.sessionId,
        reasonType: _reasonType,
        message: message,
      );

      if (!mounted) return;

      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ирц засуулах хүсэлт амжилттай илгээгдлээ'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Хүсэлт илгээхэд алдаа: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';

    final local = date.toLocal();

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final attendance = widget.attendance;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          top: 8,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.support_agent_rounded)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Ирц засуулах хүсэлт',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _InfoRow(label: 'Session', value: attendance.sessionId),
              _InfoRow(label: 'User', value: attendance.userId),
              _InfoRow(label: 'Status', value: attendance.status ?? '-'),
              _InfoRow(
                label: 'Check-in',
                value: _formatDate(attendance.checkInTime),
              ),
              _InfoRow(
                label: 'Check-out',
                value: _formatDate(attendance.checkOutTime),
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _reasonType,
                decoration: const InputDecoration(
                  labelText: 'Шалтгаан',
                  border: OutlineInputBorder(),
                ),
                items: _reasons.map((reason) {
                  return DropdownMenuItem<String>(
                    value: reason.value,
                    child: Text(reason.label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _reasonType = value);
                },
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _messageController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Тайлбар',
                  hintText:
                      'Жишээ: Би Room 402 дээр байсан боловч BLE check-in бүртгэгдээгүй.',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 18),

              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_submitting ? 'Илгээж байна...' : 'Хүсэлт илгээх'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonOption {
  final String value;
  final String label;

  const _ReasonOption({required this.value, required this.label});
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
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
