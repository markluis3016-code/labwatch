import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_notification.dart';
import '../../authentication/data/auth_repository.dart';
import '../data/notification_repository.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationCategory? _category;
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final items = ref.watch(notificationsProvider);
    final readKeys = ref.watch(notificationReadKeysProvider).valueOrNull ??
        const <String>{};

    final filtered = items.where((item) {
      final matchesCategory = _category == null || item.category == _category;
      final isUnread = !readKeys.contains(item.key);
      return matchesCategory && (!_unreadOnly || isUnread);
    }).toList(growable: false);

    final unreadCount = items.where((item) => !readKeys.contains(item.key)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (user != null && unreadCount > 0)
            TextButton.icon(
              onPressed: () async {
                try {
                  await ref
                      .read(notificationRepositoryProvider)
                      .markAllRead(user.uid, items.map((item) => item.key));
                } on AppFailure catch (failure) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(failure.message),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
            ),
        ],
      ),
      body: PageBody(
        maxWidth: 1000,
        child: ListView(
          children: [
            const PageHeader(
              breadcrumb: 'Activity',
              title: 'In-app notifications',
              subtitle:
                  'Notifications are derived from real alerts, reservations and '
                  'account status. Push delivery requires Firebase Cloud '
                  'Messaging configuration.',
            ),
            const SizedBox(height: 16),
            const InfoBanner(
              text: 'This build includes an in-app notification centre. '
                  'External push notifications are not shown here unless '
                  'Firebase Cloud Messaging and a server sender are configured.',
              icon: Icons.notifications_active_outlined,
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: Text('Unread ($unreadCount)'),
                        selected: _unreadOnly,
                        onSelected: (value) =>
                            setState(() => _unreadOnly = value),
                      ),
                      ChoiceChip(
                        label: const Text('All categories'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      for (final category in NotificationCategory.values)
                        ChoiceChip(
                          label: Text(category.label),
                          selected: _category == category,
                          onSelected: (selected) => setState(
                            () => _category = selected ? category : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (filtered.isEmpty)
              const SectionCard(
                child: EmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: 'No notifications',
                  message:
                      'Active alerts and upcoming reservations will appear here.',
                ),
              )
            else
              for (final item in filtered) ...[
                _NotificationTile(
                  item: item,
                  unread: !readKeys.contains(item.key),
                  onOpen: () async {
                    if (user != null) {
                      await ref
                          .read(notificationRepositoryProvider)
                          .markRead(user.uid, item.key);
                    }
                    if (context.mounted) context.go(item.route);
                  },
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.unread,
    required this.onOpen,
  });

  final AppNotification item;
  final bool unread;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.severity.color;
    return Card(
      child: ListTile(
        onTap: onOpen,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(_icon(item.category), color: color),
            ),
            if (unread)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.royal,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          item.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              [
                item.category.label,
                if (item.createdAt != null)
                  DateFormat.MMMd().add_jm().format(item.createdAt!),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  IconData _icon(NotificationCategory category) => switch (category) {
        NotificationCategory.alerts => Icons.warning_amber_rounded,
        NotificationCategory.energy => Icons.energy_savings_leaf_outlined,
        NotificationCategory.reservations => Icons.event_available_outlined,
        NotificationCategory.equipment => Icons.inventory_2_outlined,
        NotificationCategory.account => Icons.manage_accounts_outlined,
        NotificationCategory.system => Icons.settings_outlined,
      };
}
