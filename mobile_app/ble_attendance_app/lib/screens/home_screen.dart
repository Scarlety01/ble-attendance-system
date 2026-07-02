import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/attendance_service.dart';
import '../services/notification_service.dart';

import 'admin/admin_dashboard_screen.dart';
import 'ble_screen.dart';
import 'history_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

import 'admin/session_management_screen.dart';
import 'admin/offline_queue_screen.dart';
import 'admin/attendance_appeals_screen.dart';
import 'admin/teacher_session_summary_screen.dart';
import 'admin/users_screen.dart';
import 'admin/classes_screen.dart';
import 'admin/beacons_screen.dart';
import 'audit_log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _AppTab {
  final String title;
  final Widget page;
  final NavigationDestination destination;

  const _AppTab({
    required this.title,
    required this.page,
    required this.destination,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final AttendanceService _attendanceService = AttendanceService();
  final NotificationService _notificationService = NotificationService();

  int _currentIndex = 0;
  String? _role;
  String? _userId;
  bool _loading = true;

  bool get _isAdmin => _role == 'admin';
  bool get _isTeacher => _role == 'teacher';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _notificationService.init();

      final role = await _authService.getRole();
      final userId = await _authService.getUserId();

      int synced = 0;
      if (role == 'student' || role == 'teacher') {
        synced = await _attendanceService.syncPendingAttendances();
      }

      if (synced > 0) {
        _notificationService.add(
          title: 'Sync амжилттай',
          message: '$synced pending бүртгэл сервер рүү илгээгдлээ',
          type: 'success',
        );
      }

      if (!mounted) return;

      setState(() {
        _role = role;
        _userId = userId;
        _loading = false;
        _currentIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Эхлүүлэх үед алдаа гарлаа: $e')));
    }
  }

  Future<void> _logout() async {
    await _authService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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

  List<_AppTab> get _tabs {
    if (_isAdmin) {
      return [
        _AppTab(
          title: 'Dashboard',
          page: AdminDashboardScreen(role: _role!),
          destination: const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dash',
          ),
        ),
        const _AppTab(
          title: 'Sessions',
          page: SessionManagementScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Session',
          ),
        ),
        const _AppTab(
          title: 'History',
          page: HistoryScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
        ),
        const _AppTab(
          title: 'Report',
          page: ReportScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Report',
          ),
        ),
        _AppTab(
          title: 'More',
          page: _MoreScreen(
            role: _roleLabel(_role),
            userId: _userId ?? '-',
            roleIcon: _roleIcon(_role),
            onLogout: _logout,
            items: const [
              _MoreItem(
                title: 'Users',
                subtitle: 'Хэрэглэгчийн бүртгэл',
                icon: Icons.people_rounded,
                page: UsersScreen(canCreate: true),
              ),
              _MoreItem(
                title: 'Classes',
                subtitle: 'Хичээл / ээлжийн бүртгэл',
                icon: Icons.class_rounded,
                page: ClassesScreen(canCreate: true),
              ),
              _MoreItem(
                title: 'Beacons',
                subtitle: 'BLE beacon бүртгэл',
                icon: Icons.bluetooth_searching_rounded,
                page: BeaconsScreen(canCreate: true),
              ),
              _MoreItem(
                title: 'Appeals',
                subtitle: 'Ирц засуулах хүсэлтүүд',
                icon: Icons.support_agent_rounded,
                page: AttendanceAppealsScreen(),
              ),
              _MoreItem(
                title: 'Audit Log',
                subtitle: 'Системийн өөрчлөлтийн бүртгэл',
                icon: Icons.fact_check_rounded,
                page: AuditLogScreen(),
              ),
              _MoreItem(
                title: 'Notifications',
                subtitle: 'Мэдэгдлийн төв',
                icon: Icons.notifications_rounded,
                page: NotificationsScreen(),
              ),
            ],
          ),
          destination: const NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_rounded),
            label: 'More',
          ),
        ),
      ];
    }

    if (_isTeacher) {
      return [
        const _AppTab(
          title: 'My Sessions',
          page: TeacherSessionSummaryScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Summary',
          ),
        ),
        const _AppTab(
          title: 'BLE Scan',
          page: BleScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.bluetooth_searching_rounded),
            selectedIcon: Icon(Icons.bluetooth_rounded),
            label: 'BLE',
          ),
        ),
        const _AppTab(
          title: 'Sessions',
          page: SessionManagementScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Session',
          ),
        ),
        const _AppTab(
          title: 'History',
          page: HistoryScreen(),
          destination: NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
        ),
        _AppTab(
          title: 'More',
          page: _MoreScreen(
            role: _roleLabel(_role),
            userId: _userId ?? '-',
            roleIcon: _roleIcon(_role),
            onLogout: _logout,
            items: const [
              _MoreItem(
                title: 'Offline Queue',
                subtitle: 'Sync хүлээгдэж буй бүртгэлүүд',
                icon: Icons.cloud_off_rounded,
                page: OfflineQueueScreen(),
              ),
              _MoreItem(
                title: 'Appeals',
                subtitle: 'Ирц засуулах хүсэлтүүд',
                icon: Icons.support_agent_rounded,
                page: AttendanceAppealsScreen(),
              ),
              _MoreItem(
                title: 'Report',
                subtitle: 'Сарын тайлан',
                icon: Icons.bar_chart_rounded,
                page: ReportScreen(),
              ),
              _MoreItem(
                title: 'Notifications',
                subtitle: 'Мэдэгдлийн төв',
                icon: Icons.notifications_rounded,
                page: NotificationsScreen(),
              ),
            ],
          ),
          destination: const NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_rounded),
            label: 'More',
          ),
        ),
      ];
    }

    return [
      const _AppTab(
        title: 'BLE Scan',
        page: BleScreen(),
        destination: NavigationDestination(
          icon: Icon(Icons.bluetooth_searching_rounded),
          selectedIcon: Icon(Icons.bluetooth_rounded),
          label: 'BLE',
        ),
      ),
      const _AppTab(
        title: 'History',
        page: HistoryScreen(),
        destination: NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history_rounded),
          label: 'History',
        ),
      ),
      const _AppTab(
        title: 'Notifications',
        page: NotificationsScreen(),
        destination: NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          selectedIcon: Icon(Icons.notifications_rounded),
          label: 'Notify',
        ),
      ),
      _AppTab(
        title: 'More',
        page: _MoreScreen(
          role: _roleLabel(_role),
          userId: _userId ?? '-',
          roleIcon: _roleIcon(_role),
          onLogout: _logout,
          items: const [
            _MoreItem(
              title: 'Report',
              subtitle: 'Сарын тайлан',
              icon: Icons.bar_chart_rounded,
              page: ReportScreen(),
            ),
          ],
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.more_horiz_rounded),
          selectedIcon: Icon(Icons.more_rounded),
          label: 'More',
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tabs = _tabs;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_role == null || _userId == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 56,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Нэвтрэх шаардлагатай',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const Text('Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);
    final currentTab = tabs[safeIndex];

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Material(
          color: cs.surface,
          child: ColoredBox(color: cs.surface, child: currentTab.page),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: tabs.map((e) => e.destination).toList(),
      ),
    );
  }
}

class _MoreItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget page;

  const _MoreItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.page,
  });
}

class _MoreScreen extends StatelessWidget {
  final String role;
  final String userId;
  final IconData roleIcon;
  final VoidCallback onLogout;
  final List<_MoreItem> items;

  const _MoreScreen({
    required this.role,
    required this.userId,
    required this.roleIcon,
    required this.onLogout,
    required this.items,
  });

  void _open(BuildContext context, _MoreItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WrappedMorePage(title: item.title, child: item.page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          const Text(
            'More',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withOpacity(0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(roleIcon, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userId,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'Logout',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                elevation: 0,
                color: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => _open(context, item),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: cs.primaryContainer.withOpacity(
                            0.75,
                          ),
                          child: Icon(item.icon, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.subtitle,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
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

class _WrappedMorePage extends StatelessWidget {
  final String title;
  final Widget child;

  const _WrappedMorePage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Буцах',
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Material(
        color: cs.surface,
        child: SafeArea(
          top: false,
          child: ColoredBox(color: cs.surface, child: child),
        ),
      ),
    );
  }
}
