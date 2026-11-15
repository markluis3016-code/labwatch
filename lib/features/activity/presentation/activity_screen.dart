import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../authentication/data/auth_repository.dart';
import '../data/activity_providers.dart';
import '../domain/activity_entry.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final feed = ref.watch(activityFeedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              user?.isAdmin == true
                  ? 'All users · newest first'
                  : 'Your activity · newest first',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _error(context, ref),
        data: (entries) {
          if (entries.isEmpty) return _empty(context);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(activityFeedProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _ActivityCard(entry: entries[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 44),
            const SizedBox(height: 10),
            Text(
              'No activity yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Sign-ins, profile changes and administrator actions appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 10),
            Text(
              'Could not load activity.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your connection. If this is a new deployment, the '
              'composite Firestore index may still be building.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(activityFeedProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _visual(entry.action);
    final timestamp = entry.timestamp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(entry.action),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (entry.details != null) ...[
                    const SizedBox(height: 3),
                    Text(entry.details!, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (timestamp != null)
                        DateFormat.yMMMd().add_jms().format(timestamp),
                      if (entry.labId != null) entry.labId!,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(String action) => switch (action) {
        'login' => 'Signed in',
        'logout' => 'Signed out',
        'profile_updated' => 'Profile updated',
        'user_approved' => 'User approved',
        'user_rejected' => 'Registration rejected',
        'user_updated' => 'User account updated',
        'command_queued' => 'Device command queued',
        'schedule_created' => 'Schedule created',
        'schedule_updated' => 'Schedule updated',
        'equipment_created' => 'Equipment added',
        'equipment_updated' => 'Equipment updated',
        'inspection_completed' => 'Inspection completed',
        'report_exported' => 'Report exported',
        _ => action,
      };

  static (IconData, Color) _visual(String action) => switch (action) {
        'login' => (Icons.login, AppColors.success),
        'logout' => (Icons.logout, AppColors.royal),
        'profile_updated' => (Icons.person_outline, AppColors.royal),
        'user_approved' => (Icons.verified_user_outlined, AppColors.success),
        'user_rejected' => (Icons.block_outlined, AppColors.critical),
        'user_updated' => (Icons.manage_accounts_outlined, AppColors.warning),
        'command_queued' => (Icons.lightbulb_outline, AppColors.warning),
        _ => (Icons.history, AppColors.royal),
      };
}
