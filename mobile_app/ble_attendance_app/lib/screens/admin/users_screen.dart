import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/admin_api_service.dart';
import '../../services/auth_service.dart';

class UsersScreen extends StatefulWidget {
  final bool canCreate;

  const UsersScreen({super.key, required this.canCreate});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final AdminApiService _api = AdminApiService();
  final AuthService _authService = AuthService();

  bool _loading = true;
  String? _error;
  List<UserModel> _items = [];

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
      final users = await _api.getUsers();
      if (!mounted) return;
      setState(() => _items = users);
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
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();

    String role = 'student';
    bool isActive = true;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Шинэ хэрэглэгч'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(labelText: 'ID'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      items: const [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('student'),
                        ),
                        DropdownMenuItem(
                          value: 'teacher',
                          child: Text('teacher'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('admin')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => role = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                    SwitchListTile(
                      value: isActive,
                      onChanged: (value) {
                        setLocalState(() => isActive = value);
                      },
                      title: const Text('Active'),
                      contentPadding: EdgeInsets.zero,
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
                      await _api.createUser(
                        id: idController.text.trim(),
                        organizationId: orgId,
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
                        role: role,
                        isActive: isActive,
                      );

                      if (!mounted) return;

                      Navigator.pop(context);
                      await _load();
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

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'teacher':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Алдаа: $_error'));
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
          children: const [
            Icon(Icons.people_outline_rounded, size: 56),
            SizedBox(height: 12),
            Center(
              child: Text(
                'Хэрэглэгч олдсонгүй',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final roleColor = _roleColor(item.role);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  item.fullName.isNotEmpty
                      ? item.fullName[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(item.fullName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${item.id}'),
                  Text('Username: ${item.username}'),
                  Text('Email: ${item.email ?? '-'}'),
                  Text('Phone: ${item.phone ?? '-'}'),
                ],
              ),
              trailing: Chip(
                label: Text(item.role),
                backgroundColor: roleColor.withOpacity(0.15),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      floatingActionButton:
          widget.canCreate
              ? FloatingActionButton(
                onPressed: _showCreateDialog,
                child: const Icon(Icons.add),
              )
              : null,
      body: _buildBody(),
    );
  }
}
