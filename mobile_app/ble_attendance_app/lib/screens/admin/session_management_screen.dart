import 'package:flutter/material.dart';

import '../../models/class_model.dart';
import '../../models/session_model.dart';
import '../../services/admin_api_service.dart';
import '../../services/auth_service.dart';

class SessionManagementScreen extends StatefulWidget {
  const SessionManagementScreen({super.key});

  @override
  State<SessionManagementScreen> createState() =>
      _SessionManagementScreenState();
}

class _SessionManagementScreenState extends State<SessionManagementScreen> {
  final AdminApiService _api = AdminApiService();
  final AuthService _auth = AuthService();

  bool _loading = true;
  bool _creating = false;

  String? _role;
  String? _orgId;

  List<SessionModel> _sessions = [];
  List<ClassModel> _classes = [];

  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  List<SessionModel> get _visibleSessions {
    final items =
        _todayOnly
            ? _sessions.where((s) => s.sessionDate == _today).toList()
            : List<SessionModel>.from(_sessions);

    items.sort((a, b) {
      final dateCompare = b.sessionDate.compareTo(a.sessionDate);
      if (dateCompare != 0) return dateCompare;
      return (a.startTime ?? '').compareTo(b.startTime ?? '');
    });

    return items;
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final role = await _auth.getRole();
      final orgId = await _auth.getOrganizationId();

      final sessions = await _api.getSessions();
      final classes = await _api.getClasses();

      if (!mounted) return;

      setState(() {
        _role = role;
        _orgId = orgId;
        _sessions = sessions;
        _classes = classes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Session уншихад алдаа: $e')));
    }
  }

  Future<void> _toggleOpen(SessionModel session) async {
    try {
      await _api.updateSession(sessionId: session.id, isOpen: !session.isOpen);

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            session.isOpen ? 'Session хаагдлаа' : 'Session нээгдлээ',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Session update алдаа: $e')));
    }
  }

  Future<void> _showCreateDialog() async {
    if (_classes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Class байхгүй байна')));
      return;
    }

    final idController = TextEditingController(
      text: 'SESSION${DateTime.now().millisecondsSinceEpoch}',
    );
    final dateController = TextEditingController(text: _today);
    final startController = TextEditingController(text: '08:00');
    final endController = TextEditingController(text: '18:00');

    ClassModel? selectedClass = _classes.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Session үүсгэх'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'Session ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ClassModel>(
                      value: selectedClass,
                      decoration: const InputDecoration(
                        labelText: 'Class / Shift',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          _classes.map((c) {
                            return DropdownMenuItem<ClassModel>(
                              value: c,
                              child: Text(
                                '${c.name} (${c.id})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedClass = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                        labelText: 'Date YYYY-MM-DD',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startController,
                      decoration: const InputDecoration(
                        labelText: 'Start HH:mm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endController,
                      decoration: const InputDecoration(
                        labelText: 'End HH:mm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Болих'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Үүсгэх'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || selectedClass == null) return;

    setState(() => _creating = true);

    try {
      await _api.createSession(
        id: idController.text.trim(),
        organizationId: _orgId ?? selectedClass!.organizationId,
        classOrShiftId: selectedClass!.id,
        beaconId: selectedClass!.beaconId,
        sessionDate: dateController.text.trim(),
        startTime: startController.text.trim(),
        endTime: endController.text.trim(),
        isOpen: true,
      );

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Session үүсгэгдлээ')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Session үүсгэхэд алдаа: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _className(String id) {
    for (final c in _classes) {
      if (c.id == id) return c.name;
    }

    return id;
  }

  bool get _canCreate => _role == 'admin' || _role == 'teacher';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessions = _visibleSessions;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.event_note_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sessions (${sessions.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
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
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _todayOnly,
                    title: const Text('Зөвхөн өнөөдрийн session'),
                    onChanged: (value) {
                      setState(() => _todayOnly = value);
                    },
                  ),
                  if (_canCreate) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _creating ? null : _showCreateDialog,
                      icon:
                          _creating
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.add_rounded),
                      label: Text(
                        _creating ? 'Үүсгэж байна...' : 'Session нэмэх',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  'Session байхгүй байна',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            ...sessions.map((s) {
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              s.id,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(label: Text(s.isOpen ? 'Open' : 'Closed')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Class: ${_className(s.classOrShiftId)}'),
                      Text('Date: ${s.sessionDate}'),
                      Text('Time: ${s.startTime ?? '-'} - ${s.endTime ?? '-'}'),
                      Text('Beacon: ${s.beaconId ?? '-'}'),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => _toggleOpen(s),
                        icon: Icon(
                          s.isOpen
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                        ),
                        label: Text(
                          s.isOpen ? 'Close session' : 'Open session',
                        ),
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
