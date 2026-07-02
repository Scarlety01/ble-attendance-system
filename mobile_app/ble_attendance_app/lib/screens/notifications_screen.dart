import 'package:flutter/material.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';

enum NotificationFilter {
  all,
  unread,
  attendance,
  warning,
  error,
  success,
  info,
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NotificationService _notificationService = NotificationService();

  NotificationFilter _selectedFilter = NotificationFilter.all;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  Future<void> _loadNotifications() async {
    await _notificationService.init();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppNotification> get _notifications => _notificationService.items;

  List<AppNotification> get _filteredNotifications {
    return _notifications.where((n) {
      final matchesSearch =
          n.title.toLowerCase().contains(_searchText) ||
          n.message.toLowerCase().contains(_searchText);

      final matchesFilter = switch (_selectedFilter) {
        NotificationFilter.all => true,
        NotificationFilter.unread => !n.isRead,
        NotificationFilter.attendance => n.type == NotificationType.attendance,
        NotificationFilter.warning => n.type == NotificationType.warning,
        NotificationFilter.error => n.type == NotificationType.error,
        NotificationFilter.success => n.type == NotificationType.success,
        NotificationFilter.info => n.type == NotificationType.info,
      };

      return matchesSearch && matchesFilter;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> _refresh() async {
    await _notificationService.init();
    if (!mounted) return;
    setState(() {});
  }

  void _markAllAsRead() {
    _notificationService.markAllAsRead();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Бүх мэдэгдлийг уншсан болголоо')),
    );
  }

  void _markOneAsRead(String id) {
    _notificationService.markAsRead(id);
    setState(() {});
  }

  void _deleteNotification(String id) {
    _notificationService.remove(id);
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Мэдэгдэл устгагдлаа')));
  }

  void _clearAll() {
    _notificationService.clear();
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Бүх мэдэгдлийг цэвэрлэлээ')));
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredNotifications;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _TopSummaryCard(
              unreadCount: _unreadCount,
              totalCount: _notifications.length,
              onMarkAllRead: _notifications.isEmpty || _unreadCount == 0
                  ? null
                  : _markAllAsRead,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Мэдэгдэл хайх',
              leading: const Icon(Icons.search_rounded),
              trailing: _searchText.isNotEmpty
                  ? [
                      IconButton(
                        onPressed: () {
                          _searchController.clear();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ]
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<NotificationFilter>(
                  segments: const [
                    ButtonSegment(
                      value: NotificationFilter.all,
                      label: Text('Бүгд'),
                      icon: Icon(Icons.widgets_outlined),
                    ),
                    ButtonSegment(
                      value: NotificationFilter.unread,
                      label: Text('Unread'),
                      icon: Icon(Icons.mark_email_unread_outlined),
                    ),
                    ButtonSegment(
                      value: NotificationFilter.attendance,
                      label: Text('Ирц'),
                      icon: Icon(Icons.bluetooth_searching_rounded),
                    ),
                    ButtonSegment(
                      value: NotificationFilter.warning,
                      label: Text('Анхааруулга'),
                      icon: Icon(Icons.warning_amber_rounded),
                    ),
                    ButtonSegment(
                      value: NotificationFilter.error,
                      label: Text('Алдаа'),
                      icon: Icon(Icons.error_outline_rounded),
                    ),
                    ButtonSegment(
                      value: NotificationFilter.success,
                      label: Text('Амжилт'),
                      icon: Icon(Icons.check_circle_outline_rounded),
                    ),
                    ButtonSegment(
                      value: NotificationFilter.info,
                      label: Text('Info'),
                      icon: Icon(Icons.info_outline_rounded),
                    ),
                  ],
                  selected: {_selectedFilter},
                  onSelectionChanged: (value) {
                    setState(() {
                      _selectedFilter = value.first;
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? const _EmptyNotificationsView()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return OutlinedButton.icon(
                          onPressed: _notifications.isEmpty ? null : _clearAll,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Бүгдийг цэвэрлэх'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        );
                      }

                      final notification = items[index];
                      return NotificationCard(
                        notification: notification,
                        onTap: () {
                          if (!notification.isRead) {
                            _markOneAsRead(notification.id);
                          }
                        },
                        onMarkRead: notification.isRead
                            ? null
                            : () => _markOneAsRead(notification.id),
                        onDelete: () => _deleteNotification(notification.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopSummaryCard extends StatelessWidget {
  final int unreadCount;
  final int totalCount;
  final VoidCallback? onMarkAllRead;

  const _TopSummaryCard({
    required this.unreadCount,
    required this.totalCount,
    this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Мэдэгдлийн төв',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$unreadCount уншаагүй • $totalCount нийт мэдэгдэл',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                if (unreadCount > 0)
                  Badge(
                    label: Text('$unreadCount'),
                    child: const Icon(Icons.mark_email_unread_rounded),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onMarkAllRead,
                  child: const Text('Бүгдийг уншсан'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onMarkRead;
  final VoidCallback? onDelete;

  const NotificationCard({
    super.key,
    required this.notification,
    this.onTap,
    this.onMarkRead,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = notificationColor(context, notification.type);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(notificationIcon(notification.type), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          notification.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: notification.isRead
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            notificationTypeLabel(notification.type),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDateTime(notification.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'read') {
                              onMarkRead?.call();
                            } else if (value == 'delete') {
                              onDelete?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            if (!notification.isRead)
                              const PopupMenuItem(
                                value: 'read',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.done_rounded),
                                  title: Text('Уншсан болгох'),
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.delete_outline_rounded),
                                title: Text('Устгах'),
                              ),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.more_vert_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Саяхан';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин өмнө';
    if (diff.inHours < 24) return '${diff.inHours} цагийн өмнө';
    if (diff.inDays < 7) return '${diff.inDays} өдрийн өмнө';

    return '${dateTime.year}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.day.toString().padLeft(2, '0')}';
  }
}

class _EmptyNotificationsView extends StatelessWidget {
  const _EmptyNotificationsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 36,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Мэдэгдэл алга',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Одоогоор энэ нөхцөлд харагдах мэдэгдэл байхгүй байна.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
