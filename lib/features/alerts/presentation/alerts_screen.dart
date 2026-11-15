import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/lab_alert.dart';
import '../../authentication/data/auth_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../data/alert_repository.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  AlertCategory? _category;
  AlertStatus? _status;

  List<LabAlert> _filtered(List<LabAlert> alerts) {
    return alerts.where((alert) {
      final matchesCategory = _category == null || alert.category == _category;
      final matchesStatus = _status == null || alert.status == _status;
      return matchesCategory && matchesStatus;
    }).toList(growable: false);
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not update the alert. Try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(alertsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final canManage = user != null && (user.isAdmin || user.isStaff);
    final labs = ref.watch(labsByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.go('/notifications'),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: alertsAsync.when(
        loading: () => const LoadingState(label: 'Loading alerts…'),
        error: (error, _) {
          final view = describeFirestoreLoadError(error, resource: 'alerts');
          return Center(
            child: ErrorState(
              title: view.title,
              message: view.message,
              onRetry: () => ref.invalidate(alertsProvider),
            ),
          );
        },
        data: (alerts) {
          final filtered = _filtered(alerts);
          final open = alerts.where((alert) => alert.status.isOpen).length;
          final resolved =
              alerts.where((alert) => alert.status.isResolved).length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(alertsProvider),
            child: PageBody(
              maxWidth: 1100,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const PageHeader(
                    breadcrumb: 'Monitoring',
                    title: 'Alert centre',
                    subtitle:
                        'Laboratory conditions, energy-saving checks and '
                        'equipment reports.',
                  ),
                  const SizedBox(height: 16),
                  StatGrid(
                    children: [
                      StatTile(
                        label: 'Open',
                        value: open.toString(),
                        icon: Icons.warning_amber_rounded,
                        color: open == 0 ? AppColors.success : AppColors.critical,
                      ),
                      StatTile(
                        label: 'Total shown',
                        value: alerts.length.toString(),
                        icon: Icons.notifications_active_outlined,
                        color: AppColors.royal,
                      ),
                      StatTile(
                        label: 'Resolved',
                        value: resolved.toString(),
                        icon: Icons.task_alt,
                        color: AppColors.success,
                      ),
                      StatTile(
                        label: 'Energy alerts',
                        value: alerts
                            .where((alert) =>
                                alert.category == AlertCategory.energy &&
                                !alert.status.isResolved)
                            .length
                            .toString(),
                        icon: Icons.energy_savings_leaf_outlined,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const InfoBanner(
                    text: 'Energy-saving alerts are evaluated by the in-app '
                        'monitor while an administrator or staff member has '
                        'LabWatch open. A scheduled Cloud Function is recommended '
                        'for continuous monitoring. No alert is raised from '
                        'SAMPLE data.',
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: 14),
                  _filters(alerts),
                  const SizedBox(height: 14),
                  if (filtered.isEmpty)
                    SectionCard(
                      child: EmptyState(
                        icon: Icons.notifications_off_outlined,
                        title: alerts.isEmpty
                            ? 'No alerts found'
                            : 'No alerts match',
                        message: alerts.isEmpty
                            ? 'There are no alert records yet. New alerts will '
                                'appear here when conditions are detected or '
                                'reported.'
                            : 'Try clearing the filters. New alerts appear here '
                                'in real time.',
                      ),
                    )
                  else
                    for (final alert in filtered) ...[
                      _AlertCard(
                        alert: alert,
                        labName: alertLabLabel(alert, labs),
                        canManage: canManage,
                        onOpen: () => _showDetail(alert, labs, canManage),
                        onAcknowledge: alert.status.isOpen && canManage
                            ? () => _run(
                                  () => ref
                                      .read(alertRepositoryProvider)
                                      .acknowledge(alert, user),
                                  success: 'Alert acknowledged.',
                                )
                            : null,
                        onResolve: canManage && !alert.status.isResolved
                            ? () => _run(
                                  () => ref
                                      .read(alertRepositoryProvider)
                                      .resolve(alert, user),
                                  success: 'Alert resolved.',
                                )
                            : null,
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filters(List<LabAlert> alerts) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Category', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _category == null,
                onSelected: (_) => setState(() => _category = null),
              ),
              for (final category in AlertCategory.values)
                ChoiceChip(
                  avatar: Icon(category.icon, size: 15),
                  label: Text(category.label),
                  selected: _category == category,
                  onSelected: (selected) =>
                      setState(() => _category = selected ? category : null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Status', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Any'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              for (final status in AlertStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: _status == status,
                  onSelected: (selected) =>
                      setState(() => _status = selected ? status : null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetail(LabAlert alert, Map<String, Lab> labs, bool canManage) {
    final user = ref.read(currentUserProvider).valueOrNull;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(alert.category.icon, color: alert.severity.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.title,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.message),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: alert.severity.label,
                  color: alert.severity.color,
                  icon: alert.severity.icon,
                ),
                StatusPill(
                  label: alert.status.label,
                  color: alert.status.isResolved
                      ? AppColors.success
                      : AppColors.warning,
                ),
                if (alert.labId.isNotEmpty)
                  StatusPill(
                    label: alertLabLabel(alert, labs),
                    color: AppColors.royal,
                    icon: Icons.science_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              [
                if (alert.createdAt != null)
                  'Raised ${DateFormat.yMMMd().add_jm().format(alert.createdAt!)}',
                if (alert.acknowledgedAt != null)
                  'Acknowledged ${DateFormat.yMMMd().add_jm().format(alert.acknowledgedAt!)}',
                if (alert.resolvedAt != null)
                  'Resolved ${DateFormat.yMMMd().add_jm().format(alert.resolvedAt!)}',
              ].join(' · '),
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (canManage && !alert.status.isResolved) ...[
                  if (alert.status.isOpen)
                    OutlinedButton.icon(
                      onPressed: user == null
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              _run(
                                () => ref
                                    .read(alertRepositoryProvider)
                                    .acknowledge(alert, user),
                                success: 'Alert acknowledged.',
                              );
                            },
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Acknowledge'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: user == null
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            _run(
                              () => ref
                                  .read(alertRepositoryProvider)
                                  .resolve(alert, user),
                              success: 'Alert resolved.',
                            );
                          },
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Resolve'),
                  ),
                ],
                if (alert.labId.isNotEmpty) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      context.go('/labs/${alert.labId}');
                    },
                    child: const Text('Open laboratory'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.labName,
    required this.canManage,
    required this.onOpen,
    this.onAcknowledge,
    this.onResolve,
  });

  final LabAlert alert;
  final String labName;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = alert.severity.color;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(alert.category.icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          alert.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        StatusPill(
                          label: alert.status.label,
                          color: alert.status.isResolved
                              ? AppColors.success
                              : alert.status == AlertStatus.acknowledged
                                  ? AppColors.info
                                  : AppColors.warning,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        alert.category.label,
                        if (labName.isNotEmpty) labName,
                        if (alert.createdAt != null)
                          DateFormat.MMMd().add_jm().format(alert.createdAt!),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (canManage) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        children: [
                          if (onAcknowledge != null)
                            TextButton(
                              onPressed: onAcknowledge,
                              child: const Text('Acknowledge'),
                            ),
                          if (onResolve != null)
                            TextButton(
                              onPressed: onResolve,
                              child: const Text('Resolve'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
