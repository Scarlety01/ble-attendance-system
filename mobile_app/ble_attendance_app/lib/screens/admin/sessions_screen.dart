import 'package:flutter/material.dart';
import '../../models/session_model.dart';
import '../../services/admin_api_service.dart';
import '../../services/auth_service.dart';

class SessionsScreen extends StatefulWidget {
  final bool canCreate;

  const SessionsScreen({super.key, required this.canCreate});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final AdminApiService _api = AdminApiService();
  final AuthService _authService = AuthService();

  bool _loading = true;
  String? _error;
  List<SessionModel> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _api.getSessions();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final orgId = await _authService.getOrganizationId() ?? 'ORG001';

    final idController = TextEditingController();
    final classIdController = TextEditingController();
    final beaconIdController = TextEditingController();
    final dateController = TextEditingController(text: '2026-04-13');
    final startController = TextEditingController(text: '08:30:00');
    final endController = TextEditingController(text: '10:00:00');
    bool isOpen = true;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Шинэ session'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'Session ID',
                      ),
                    ),
                    TextField(
                      controller: classIdController,
                      decoration: const InputDecoration(
                        labelText: 'Class/Shift ID',
                      ),
                    ),
                    TextField(
                      controller: beaconIdController,
                      decoration: const InputDecoration(labelText: 'Beacon ID'),
                    ),
                    TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                        labelText: 'Session Date (YYYY-MM-DD)',
                      ),
                    ),
                    TextField(
                      controller: startController,
                      decoration: const InputDecoration(
                        labelText: 'Start Time (HH:MM:SS)',
                      ),
                    ),
                    TextField(
                      controller: endController,
                      decoration: const InputDecoration(
                        labelText: 'End Time (HH:MM:SS)',
                      ),
                    ),
                    SwitchListTile(
                      value: isOpen,
                      onChanged: (value) {
                        setLocalState(() => isOpen = value);
                      },
                      title: const Text('Open'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _api.createSession(
                        id: idController.text.trim(),
                        organizationId: orgId,
                        classOrShiftId: classIdController.text.trim(),
                        beaconId:
                            beaconIdController.text.trim().isEmpty
                                ? null
                                : beaconIdController.text.trim(),
                        sessionDate: dateController.text.trim(),
                        startTime:
                            startController.text.trim().isEmpty
                                ? null
                                : startController.text.trim(),
                        endTime:
                            endController.text.trim().isEmpty
                                ? null
                                : endController.text.trim(),
                        isOpen: isOpen,
                      );
                      if (!mounted) return;
                      Navigator.pop(context);
                      _load();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Алдаа: $e')));
                    }
                  },
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      floatingActionButton:
          widget.canCreate
              ? FloatingActionButton(
                onPressed: _showCreateDialog,
                child: const Icon(Icons.add),
              )
              : null,
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('Алдаа: $_error'))
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text(item.id),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Class/Shift: ${item.classOrShiftId}'),
                            Text('Beacon: ${item.beaconId ?? '-'}'),
                            Text('Date: ${item.sessionDate}'),
                            Text(
                              'Time: ${item.startTime ?? '-'} - ${item.endTime ?? '-'}',
                            ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(item.isOpen ? 'open' : 'closed'),
                        ),
                      ),
                    );
                  },
                ),
              ),
    );
  }
}
