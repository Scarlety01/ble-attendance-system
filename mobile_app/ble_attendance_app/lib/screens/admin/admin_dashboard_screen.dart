import 'package:flutter/material.dart';

import '../../models/attendance_event.dart';
import '../../models/device_model.dart';
import '../../models/user_model.dart';
import '../../services/admin_api_service.dart';
import '../../services/auth_service.dart';
import '../../services/history_api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String role;

  const AdminDashboardScreen({super.key, required this.role});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminApiService _adminService = AdminApiService();
  final HistoryApiService _historyService = HistoryApiService();
  final AuthService _authService = AuthService();

  bool _loading = true;
  String? _error;

  String? _currentUserId;

  List<UserModel> _users = [];
  List<DeviceModel> _devices = [];
  List<AttendanceEvent> _attendance = [];

  bool get _isAdmin => widget.role == 'admin';
  bool get _isTeacher => widget.role == 'teacher';

  List<UserModel> get _students =>
      _users.where((user) => user.role == 'student').toList();

  List<UserModel> get _teachers =>
      _users.where((user) => user.role == 'teacher').toList();

  List<UserModel> get _admins =>
      _users.where((user) => user.role == 'admin').toList();

  List<AttendanceEvent> get _todayAttendance {
    final now = DateTime.now();

    return _attendance.where((item) {
        final checkIn = item.checkInTime;
        if (checkIn == null) return false;

        final local = checkIn.toLocal();

        return local.year == now.year &&
            local.month == now.month &&
            local.day == now.day;
      }).toList()
      ..sort((a, b) {
        final at = a.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
  }

  List<AttendanceEvent> get _latestAttendance {
    final items = List<AttendanceEvent>.from(_todayAttendance);
    if (items.length <= 5) return items;
    return items.take(5).toList();
  }

  List<AttendanceEvent> get _lateAttendance {
    return _todayAttendance.where((item) {
      return (item.status ?? '').toLowerCase() == 'late' ||
          (item.lateMinutes ?? 0) > 0;
    }).toList();
  }

  AttendanceEvent? get _myTodayAttendance {
    if (_currentUserId == null || _currentUserId!.isEmpty) return null;

    final mine =
        _todayAttendance.where((item) {
          return item.userId == _currentUserId;
        }).toList();

    if (mine.isEmpty) return null;

    mine.sort((a, b) {
      final at = a.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.checkInTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });

    return mine.first;
  }

  Map<String, List<AttendanceEvent>> get _sessionGroups {
    final map = <String, List<AttendanceEvent>>{};

    for (final item in _todayAttendance) {
      map.putIfAbsent(item.sessionId, () => []);
      map[item.sessionId]!.add(item);
    }

    return map;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = await _authService.getUserId();

      if (_isAdmin) {
        final users = await _adminService.getUsers();
        final devices = await _adminService.getDevices();

        if (!mounted) return;

        setState(() {
          _currentUserId = userId;
          _users = users;
          _devices = devices;
          _attendance = [];
        });
      } else {
        final attendance = await _historyService.getAllAttendance();

        if (!mounted) return;

        setState(() {
          _currentUserId = userId;
          _users = [];
          _devices = [];
          _attendance = attendance;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Админ';
      case 'teacher':
        return 'Багш';
      case 'student':
        return 'Оюутан';
      default:
        return role;
    }
  }

  IconData _roleIcon(String role) {
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

  Color _roleColor(BuildContext context, String role) {
    final cs = Theme.of(context).colorScheme;

    switch (role) {
      case 'admin':
        return cs.error;
      case 'teacher':
        return cs.tertiary;
      case 'student':
        return cs.primary;
      default:
        return cs.secondary;
    }
  }

  Color _statusColor(BuildContext context, String? status) {
    final cs = Theme.of(context).colorScheme;

    switch ((status ?? '').toLowerCase()) {
      case 'present':
        return cs.primary;
      case 'late':
        return cs.tertiary;
      case 'checked_out':
        return cs.secondary;
      case 'absent':
        return cs.error;
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
      case 'checked_out':
        return Icons.logout_rounded;
      case 'absent':
        return Icons.cancel_rounded;
      default:
        return Icons.event_available_rounded;
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '-';

    final local = value.toLocal();

    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';

    final local = value.toLocal();

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _defaultDeviceUuid(String userId) {
    return 'DEVICE_$userId';
  }

  // ---------------------------------------------------------------------------
  // Admin dialogs
  // ---------------------------------------------------------------------------

  Future<void> _showCreateUserDialog({String initialRole = 'student'}) async {
    final idController = TextEditingController();
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    final organizationController = TextEditingController(text: 'ORG001');
    final departmentController = TextEditingController(text: 'DEP001');

    String selectedRole = initialRole;
    bool isActive = true;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (idController.text.trim().isEmpty ||
                  usernameController.text.trim().isEmpty ||
                  fullNameController.text.trim().isEmpty ||
                  passwordController.text.trim().length < 6 ||
                  organizationController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Заавал бөглөх талбаруудыг шалгана уу'),
                  ),
                );
                return;
              }

              setDialogState(() => saving = true);

              try {
                await _adminService.createUser(
                  id: idController.text.trim(),
                  organizationId: organizationController.text.trim(),
                  departmentId:
                      departmentController.text.trim().isEmpty
                          ? null
                          : departmentController.text.trim(),
                  username: usernameController.text.trim(),
                  fullName: fullNameController.text.trim(),
                  email:
                      emailController.text.trim().isEmpty
                          ? null
                          : emailController.text.trim(),
                  phone:
                      phoneController.text.trim().isEmpty
                          ? null
                          : phoneController.text.trim(),
                  password: passwordController.text.trim(),
                  role: selectedRole,
                  isActive: isActive,
                );

                if (!mounted) return;

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${_roleLabel(selectedRole)} хэрэглэгч амжилттай нэмэгдлээ',
                    ),
                  ),
                );

                await _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Хэрэглэгч нэмэхэд алдаа: $e')),
                );
              } finally {
                if (mounted) {
                  setDialogState(() => saving = false);
                }
              }
            }

            return AlertDialog(
              title: Text('${_roleLabel(selectedRole)} нэмэх'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogTextField(
                      controller: idController,
                      label: 'User ID',
                      icon: Icons.badge_rounded,
                    ),
                    _dialogTextField(
                      controller: usernameController,
                      label: 'Нэвтрэх нэр',
                      icon: Icons.account_circle_rounded,
                    ),
                    _dialogTextField(
                      controller: fullNameController,
                      label: 'Овог нэр',
                      icon: Icons.person_rounded,
                    ),
                    _dialogTextField(
                      controller: emailController,
                      label: 'Email',
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _dialogTextField(
                      controller: phoneController,
                      label: 'Утас',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    _dialogTextField(
                      controller: passwordController,
                      label: 'Нууц үг',
                      icon: Icons.lock_rounded,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.manage_accounts_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('Оюутан'),
                        ),
                        DropdownMenuItem(value: 'teacher', child: Text('Багш')),
                        DropdownMenuItem(value: 'admin', child: Text('Админ')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedRole = value);
                      },
                    ),
                    _dialogTextField(
                      controller: organizationController,
                      label: 'Organization ID',
                      icon: Icons.apartment_rounded,
                    ),
                    _dialogTextField(
                      controller: departmentController,
                      label: 'Department ID',
                      icon: Icons.business_rounded,
                    ),
                    SwitchListTile(
                      value: isActive,
                      title: const Text('Идэвхтэй'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isActive = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Хадгалж байна...' : 'Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditUserDialog(UserModel user) async {
    final fullNameController = TextEditingController(text: user.fullName);
    final emailController = TextEditingController(text: user.email ?? '');
    final phoneController = TextEditingController(text: user.phone ?? '');
    final departmentController = TextEditingController(
      text: user.departmentId ?? '',
    );

    String selectedRole = user.role;
    bool isActive = user.isActive;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (fullNameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Овог нэр хоосон байна')),
                );
                return;
              }

              setDialogState(() => saving = true);

              try {
                await _adminService.updateUser(
                  userId: user.id,
                  departmentId:
                      departmentController.text.trim().isEmpty
                          ? null
                          : departmentController.text.trim(),
                  fullName: fullNameController.text.trim(),
                  email:
                      emailController.text.trim().isEmpty
                          ? null
                          : emailController.text.trim(),
                  phone:
                      phoneController.text.trim().isEmpty
                          ? null
                          : phoneController.text.trim(),
                  role: selectedRole,
                  isActive: isActive,
                );

                if (!mounted) return;

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Хэрэглэгч шинэчлэгдлээ')),
                );

                await _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Хэрэглэгч засахад алдаа: $e')),
                );
              } finally {
                if (mounted) {
                  setDialogState(() => saving = false);
                }
              }
            }

            return AlertDialog(
              title: Text('Хэрэглэгч засах: ${user.id}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _readOnlyInfo('User ID', user.id),
                    _readOnlyInfo('Username', user.username),
                    _dialogTextField(
                      controller: fullNameController,
                      label: 'Овог нэр',
                      icon: Icons.person_rounded,
                    ),
                    _dialogTextField(
                      controller: emailController,
                      label: 'Email',
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _dialogTextField(
                      controller: phoneController,
                      label: 'Утас',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    _dialogTextField(
                      controller: departmentController,
                      label: 'Department ID',
                      icon: Icons.business_rounded,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.manage_accounts_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('Оюутан'),
                        ),
                        DropdownMenuItem(value: 'teacher', child: Text('Багш')),
                        DropdownMenuItem(value: 'admin', child: Text('Админ')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedRole = value);
                      },
                    ),
                    SwitchListTile(
                      value: isActive,
                      title: const Text('Идэвхтэй'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isActive = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Хадгалж байна...' : 'Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateDeviceDialog({String? userId}) async {
    String? selectedUserId =
        userId ?? (_users.isNotEmpty ? _users.first.id : null);

    final uuidController = TextEditingController(
      text: selectedUserId == null ? '' : _defaultDeviceUuid(selectedUserId),
    );
    final nameController = TextEditingController();
    final platformController = TextEditingController(text: 'iOS');
    final typeController = TextEditingController(text: 'phone');

    bool isRegistered = true;
    bool isActive = true;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (selectedUserId == null ||
                  selectedUserId!.isEmpty ||
                  uuidController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Хэрэглэгч болон UUID оруулна уу'),
                  ),
                );
                return;
              }

              setDialogState(() => saving = true);

              try {
                await _adminService.createDevice(
                  userId: selectedUserId!,
                  uuid: uuidController.text.trim(),
                  name:
                      nameController.text.trim().isEmpty
                          ? null
                          : nameController.text.trim(),
                  platform:
                      platformController.text.trim().isEmpty
                          ? null
                          : platformController.text.trim(),
                  deviceType:
                      typeController.text.trim().isEmpty
                          ? null
                          : typeController.text.trim(),
                  isRegistered: isRegistered,
                  isActive: isActive,
                );

                if (!mounted) return;

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Төхөөрөмж нэмэгдлээ')),
                );

                await _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Device нэмэхэд алдаа: $e')),
                );
              } finally {
                if (mounted) {
                  setDialogState(() => saving = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Төхөөрөмж нэмэх'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedUserId,
                      decoration: const InputDecoration(
                        labelText: 'Хэрэглэгч',
                        prefixIcon: Icon(Icons.person_search_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items:
                          _users
                              .map(
                                (user) => DropdownMenuItem(
                                  value: user.id,
                                  child: Text(
                                    '${user.id} • ${user.fullName} • ${_roleLabel(user.role)}',
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setDialogState(() {
                          selectedUserId = value;
                          uuidController.text = _defaultDeviceUuid(value);
                        });
                      },
                    ),
                    _dialogTextField(
                      controller: uuidController,
                      label: 'Device UUID',
                      icon: Icons.fingerprint_rounded,
                    ),
                    _dialogTextField(
                      controller: nameController,
                      label: 'Device name',
                      icon: Icons.phone_iphone_rounded,
                    ),
                    _dialogTextField(
                      controller: platformController,
                      label: 'Platform',
                      icon: Icons.smartphone_rounded,
                    ),
                    _dialogTextField(
                      controller: typeController,
                      label: 'Device type',
                      icon: Icons.devices_other_rounded,
                    ),
                    SwitchListTile(
                      value: isRegistered,
                      title: const Text('Бүртгэлтэй'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isRegistered = value);
                      },
                    ),
                    SwitchListTile(
                      value: isActive,
                      title: const Text('Идэвхтэй'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isActive = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Хадгалж байна...' : 'Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDeviceDialog(DeviceModel device) async {
    final nameController = TextEditingController(text: device.name ?? '');
    final platformController = TextEditingController(
      text: device.platform ?? '',
    );
    final typeController = TextEditingController(text: device.deviceType ?? '');

    bool isRegistered = device.isRegistered;
    bool isActive = device.isActive;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              setDialogState(() => saving = true);

              try {
                await _adminService.updateDevice(
                  deviceId: device.id,
                  name:
                      nameController.text.trim().isEmpty
                          ? null
                          : nameController.text.trim(),
                  platform:
                      platformController.text.trim().isEmpty
                          ? null
                          : platformController.text.trim(),
                  deviceType:
                      typeController.text.trim().isEmpty
                          ? null
                          : typeController.text.trim(),
                  isRegistered: isRegistered,
                  isActive: isActive,
                );

                if (!mounted) return;

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Төхөөрөмж шинэчлэгдлээ')),
                );

                await _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Device засахад алдаа: $e')),
                );
              } finally {
                if (mounted) {
                  setDialogState(() => saving = false);
                }
              }
            }

            return AlertDialog(
              title: Text('Device засах: ${device.id}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _readOnlyInfo('User ID', device.userId),
                    _readOnlyInfo('UUID', device.uuid),
                    _dialogTextField(
                      controller: nameController,
                      label: 'Device name',
                      icon: Icons.phone_iphone_rounded,
                    ),
                    _dialogTextField(
                      controller: platformController,
                      label: 'Platform',
                      icon: Icons.smartphone_rounded,
                    ),
                    _dialogTextField(
                      controller: typeController,
                      label: 'Device type',
                      icon: Icons.devices_other_rounded,
                    ),
                    SwitchListTile(
                      value: isRegistered,
                      title: const Text('Бүртгэлтэй'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isRegistered = value);
                      },
                    ),
                    SwitchListTile(
                      value: isActive,
                      title: const Text('Идэвхтэй'),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => isActive = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Хадгалж байна...' : 'Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _dialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _readOnlyInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(value),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: effectiveColor.withValues(alpha: 0.12),
              child: Icon(icon, color: effectiveColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSummary() {
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _metricCard(
          title: 'Оюутан',
          value: '${_students.length}',
          icon: Icons.person_rounded,
        ),
        _metricCard(
          title: 'Багш',
          value: '${_teachers.length}',
          icon: Icons.school_rounded,
        ),
        _metricCard(
          title: 'Админ',
          value: '${_admins.length}',
          icon: Icons.admin_panel_settings_rounded,
        ),
        _metricCard(
          title: 'Device',
          value: '${_devices.length}',
          icon: Icons.devices_rounded,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Admin UI
  // ---------------------------------------------------------------------------

  Widget _buildUserSection({
    required String title,
    required String role,
    required List<UserModel> users,
    required IconData icon,
  }) {
    final color = _roleColor(context, role);

    final sorted = List<UserModel>.from(users)
      ..sort((a, b) => a.id.compareTo(b.id));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ExpansionTile(
        initiallyExpanded: role == 'student',
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          '$title (${sorted.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        subtitle: const Text('Жагсаалт харах, засах, төхөөрөмж холбох'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: FilledButton.icon(
              onPressed: () => _showCreateUserDialog(initialRole: role),
              icon: const Icon(Icons.person_add_rounded),
              label: Text('$title нэмэх'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Бүртгэл алга'),
            )
          else
            ...sorted.map(_buildUserTile),
        ],
      ),
    );
  }

  Widget _buildUserTile(UserModel user) {
    final color = _roleColor(context, user.role);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(_roleIcon(user.role), color: color),
      ),
      title: Text(
        user.fullName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${user.id} • ${user.username} • ${user.email ?? '-'}'),
      trailing: Wrap(
        spacing: 4,
        children: [
          Icon(
            user.isActive ? Icons.check_circle_rounded : Icons.block_rounded,
            color: user.isActive ? Colors.green : Colors.red,
          ),
          IconButton(
            onPressed: () => _showEditUserDialog(user),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            onPressed: () => _showCreateDeviceDialog(userId: user.id),
            icon: const Icon(Icons.add_to_home_screen_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSection() {
    final sorted = List<DeviceModel>.from(_devices)
      ..sort((a, b) => a.userId.compareTo(b.userId));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const CircleAvatar(child: Icon(Icons.devices_rounded)),
        title: Text(
          'Төхөөрөмжүүд (${sorted.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        subtitle: const Text('Device binding жагсаалт, засвар'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: FilledButton.icon(
              onPressed: () => _showCreateDeviceDialog(),
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: const Text('Төхөөрөмж нэмэх'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Төхөөрөмж бүртгэлгүй байна'),
            )
          else
            ...sorted.map(_buildDeviceTile),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(DeviceModel device) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(
          context,
        ).colorScheme.secondary.withValues(alpha: 0.12),
        child: Icon(
          Icons.phone_iphone_rounded,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      title: Text(
        device.name ?? device.uuid,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${device.userId} • ${device.uuid} • ${device.platform ?? '-'}',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          Icon(
            device.isActive ? Icons.check_circle_rounded : Icons.block_rounded,
            color: device.isActive ? Colors.green : Colors.red,
          ),
          IconButton(
            onPressed: () => _showEditDeviceDialog(device),
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Teacher UI
  // ---------------------------------------------------------------------------

  Widget _buildTeacherSummary() {
    final cs = Theme.of(context).colorScheme;
    final total = _todayAttendance.length;
    final present =
        _todayAttendance
            .where((item) => (item.status ?? '').toLowerCase() == 'present')
            .length;
    final late = _lateAttendance.length;
    final checkedOut =
        _todayAttendance.where((item) => item.checkOutTime != null).length;

    return GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _metricCard(
          title: 'Өнөөдөр',
          value: '$total',
          icon: Icons.fact_check_rounded,
          color: cs.primary,
        ),
        _metricCard(
          title: 'Ирсэн',
          value: '$present',
          icon: Icons.check_circle_rounded,
          color: Colors.green,
        ),
        _metricCard(
          title: 'Хоцорсон',
          value: '$late',
          icon: Icons.schedule_rounded,
          color: Colors.orange,
        ),
        _metricCard(
          title: 'Check-out',
          value: '$checkedOut',
          icon: Icons.logout_rounded,
          color: cs.secondary,
        ),
      ],
    );
  }

  Widget _buildMyAttendanceCard() {
    final item = _myTodayAttendance;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: (item == null ? cs.error : cs.primary)
                  .withValues(alpha: 0.12),
              child: Icon(
                item == null
                    ? Icons.pending_actions_rounded
                    : Icons.verified_rounded,
                color: item == null ? cs.error : cs.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Миний өнөөдрийн ирц',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item == null
                        ? 'Одоогоор бүртгэгдээгүй'
                        : '${item.status ?? '-'} • ${_formatDateTime(item.checkInTime)}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if (item != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${item.sessionId} • RSSI ${item.rssi ?? '-'} • ${item.distanceM?.toStringAsFixed(2) ?? '-'} m',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSummaryCard() {
    final groups =
        _sessionGroups.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const CircleAvatar(child: Icon(Icons.meeting_room_rounded)),
        title: const Text(
          'Session summary',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        subtitle: Text('Өнөөдрийн ${groups.length} session'),
        children: [
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Өнөөдөр session бүртгэл алга'),
            )
          else
            ...groups.map((entry) {
              final sessionId = entry.key;
              final items = entry.value;
              final present =
                  items
                      .where((e) => (e.status ?? '').toLowerCase() == 'present')
                      .length;
              final late =
                  items
                      .where(
                        (e) =>
                            (e.status ?? '').toLowerCase() == 'late' ||
                            (e.lateMinutes ?? 0) > 0,
                      )
                      .length;
              final total = items.length;
              final progress = total == 0 ? 0.0 : present / total;

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sessionId,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Нийт: $total • Ирсэн: $present • Хоцорсон: $late'),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: progress,
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

  Widget _buildLatestAttendanceCard() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const CircleAvatar(child: Icon(Icons.update_rounded)),
        title: const Text(
          'Сүүлийн бүртгэлүүд',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${_latestAttendance.length} бичлэг'),
        children: [
          if (_latestAttendance.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Өнөөдөр бүртгэл алга'),
            )
          else
            ..._latestAttendance.map(_buildAttendanceTile),
        ],
      ),
    );
  }

  Widget _buildLateUsersCard() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ExpansionTile(
        initiallyExpanded: _lateAttendance.isNotEmpty,
        leading: const CircleAvatar(child: Icon(Icons.warning_amber_rounded)),
        title: const Text(
          'Хоцорсон хэрэглэгчид',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${_lateAttendance.length} хэрэглэгч'),
        children: [
          if (_lateAttendance.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Өнөөдөр хоцорсон бүртгэл алга'),
            )
          else
            ..._lateAttendance.map(_buildAttendanceTile),
        ],
      ),
    );
  }

  Widget _buildAttendanceTile(AttendanceEvent item) {
    final color = _statusColor(context, item.status);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(_statusIcon(item.status), color: color),
      ),
      title: Text(
        '${item.userId} • ${item.status ?? '-'}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${item.sessionId} • ${_formatTime(item.checkInTime)}'
        ' • late: ${item.lateMinutes ?? 0} мин',
      ),
      trailing: Text(
        item.distanceM == null
            ? '-'
            : '${item.distanceM!.toStringAsFixed(2)} m',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildTeacherQuickActions() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.history_rounded),
                  label: const Text('History tab'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Доод цэснээс History хэсгийг нээнэ үү'),
                      ),
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.bar_chart_rounded),
                  label: const Text('Report tab'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Доод цэснээс Report хэсгийг нээнэ үү'),
                      ),
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.bluetooth_rounded),
                  label: const Text('BLE check-in'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Доод цэснээс BLE хэсгийг нээнэ үү'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherWarningCard() {
    final uncheckedOut =
        _todayAttendance
            .where((item) => item.checkOutTime == null)
            .toList()
            .length;

    if (_lateAttendance.isEmpty && uncheckedOut == 0) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: cs.errorContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: cs.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Анхааруулга: ${_lateAttendance.length} хэрэглэгч хоцорсон, '
                '$uncheckedOut хэрэглэгч check-out хийгээгүй байна.',
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Dashboard ачаалахад алдаа гарлаа:\n$_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Дахин ачаалах'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              _isAdmin ? 'Admin Dashboard' : 'Teacher Dashboard',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _isAdmin
                  ? 'Хэрэглэгч, багш, оюутан болон төхөөрөмж удирдах'
                  : 'Өнөөдрийн ирцийн хяналт, session summary, хоцролтын мэдээлэл',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_isAdmin) ...[
            _buildAdminSummary(),
            _buildUserSection(
              title: 'Оюутнууд',
              role: 'student',
              users: _students,
              icon: Icons.person_rounded,
            ),
            _buildUserSection(
              title: 'Багш нар',
              role: 'teacher',
              users: _teachers,
              icon: Icons.school_rounded,
            ),
            _buildUserSection(
              title: 'Админууд',
              role: 'admin',
              users: _admins,
              icon: Icons.admin_panel_settings_rounded,
            ),
            _buildDeviceSection(),
          ] else if (_isTeacher) ...[
            _buildTeacherSummary(),
            _buildMyAttendanceCard(),
            _buildTeacherWarningCard(),
            _buildSessionSummaryCard(),
            _buildLatestAttendanceCard(),
            _buildLateUsersCard(),
            _buildTeacherQuickActions(),
          ],
        ],
      ),
    );
  }
}
