import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/account_chips.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/inspection.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/lab_alert.dart';
import '../../../shared/models/reservation.dart';
import '../../activity/data/activity_providers.dart';
import '../../admin/data/user_admin_repository.dart';
import '../../alerts/data/alert_repository.dart';
import '../../authentication/data/auth_repository.dart';
import '../../equipment/data/equipment_repository.dart';
import '../../inspections/data/inspection_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../../monitoring/data/telemetry_providers.dart';
import '../../scheduling/data/reservation_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      body: PageBody(
        child: ListView(
          children: [
            const PageHeader(
              breadcrumb: 'Overview',
              title: 'Dashboard',
              subtitle: 'Monitor laboratories, activity, and key operations.',
            ),
            const SizedBox(height: 16),
            if (user != null) ...[
              _Welcome(user: user),
              const SizedBox(height: 16),
            ],
            if (user?.isAdmin == true)
              const _AdminDashboard()
            else if (user?.isStaff == true)
              _StaffDashboard(user: user!)
            else
              _InstructorDashboard(user: user),
            const SizedBox(height: 16),
            const _DemoModeCard(),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user.displayName.isEmpty ? user.email : user.displayName;
    return SectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            child: Text(
              user.initials,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $name',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.role.label} · ${DateFormat.yMMMMEEEEd().format(DateTime.now())}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RoleChip(user.role),
                    AccountStatusChip(user.status),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboard extends ConsumerWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[];
    final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const <LabAlert>[];
    final equipment = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
    final reservations = ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
    final activity = ref.watch(activityFeedProvider).valueOrNull ?? const [];
    final labsById = ref.watch(labsByIdProvider);

    final pendingUsers = users.where((user) => user.isPending).length;
    final openAlerts = alerts.where((alert) => !alert.status.isResolved).length;
    final equipmentIssues = equipment.where((item) => item.condition.isIssue || item.condition == EquipmentCondition.needsRepair).length;
    final availableLabs = labs.where((lab) => lab.status == LabStatus.available).length;
    final occupiedLabs = labs.where((lab) => lab.status == LabStatus.occupied).length;
    final reservedLabs = labs.where((lab) => lab.status == LabStatus.reserved).length;
    final upcoming = reservations
        .where((r) => r.status.isUpcoming && r.endAt.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          maxColumns: 4,
          children: [
            StatTile(
              label: 'Total laboratories',
              value: labs.length.toString(),
              icon: Icons.science_outlined,
              color: AppColors.royal,
              onTap: () => context.go('/labs'),
            ),
            StatTile(
              label: 'Available',
              value: availableLabs.toString(),
              icon: Icons.check_circle_outline,
              color: AppColors.success,
            ),
            StatTile(
              label: 'In use',
              value: occupiedLabs.toString(),
              icon: Icons.sensors,
              color: AppColors.critical,
            ),
            StatTile(
              label: 'Reserved',
              value: reservedLabs.toString(),
              icon: Icons.event_available_outlined,
              color: AppColors.warning,
            ),
            StatTile(
              label: 'Total users',
              value: users.length.toString(),
              icon: Icons.people_outline,
              color: AppColors.royal,
              onTap: () => context.go('/admin/users'),
            ),
            StatTile(
              label: 'Pending approvals',
              value: pendingUsers.toString(),
              icon: Icons.hourglass_top_rounded,
              color: pendingUsers == 0 ? AppColors.success : AppColors.warning,
              caption: pendingUsers == 0 ? 'All clear' : 'Review accounts',
              onTap: () => context.go('/admin/users'),
            ),
            StatTile(
              label: 'Active alerts',
              value: openAlerts.toString(),
              icon: Icons.warning_amber_rounded,
              color: openAlerts == 0 ? AppColors.success : AppColors.critical,
              onTap: () => context.go('/alerts'),
            ),
            StatTile(
              label: 'Equipment issues',
              value: equipmentIssues.toString(),
              icon: Icons.build_outlined,
              color: equipmentIssues == 0 ? AppColors.success : AppColors.critical,
              onTap: () => context.go('/equipment'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _QuickActions(
          items: [
            _Action(Icons.manage_accounts_outlined, 'Manage users', '/admin/users'),
            _Action(Icons.science_outlined, 'Laboratories', '/labs'),
            _Action(Icons.assessment_outlined, 'Reports', '/reports'),
            _Action(Icons.settings_outlined, 'Settings', '/settings'),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final left = Column(
              children: [
                _RecentAlerts(alerts: alerts, labsById: labsById),
                const SizedBox(height: 14),
                _UpcomingReservations(reservations: upcoming, labsById: labsById),
              ],
            );
            final right = Column(
              children: [
                _LabStatusOverview(labs: labs),
                const SizedBox(height: 14),
                _EquipmentSummary(equipment: equipment),
              ],
            );
            if (!wide) return Column(children: [left, const SizedBox(height: 14), right]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 14),
                Expanded(child: right),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _RecentActivitySummary(count: activity.length),
        const SizedBox(height: 14),
        const SectionCard(
          title: 'Energy consumption',
          child: InfoBanner(
            text: 'No metered energy-consumption records are available yet. '
                'Connect power meters and store readings to enable consumption '
                'totals and trends.',
            icon: Icons.energy_savings_leaf_outlined,
          ),
        ),
      ],
    );
  }
}

class _StaffDashboard extends ConsumerWidget {
  const _StaffDashboard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labs = ref.watch(visibleLabsProvider);
    final alerts = ref.watch(openAlertsProvider);
    final equipment = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
    final inspections = ref.watch(recentInspectionsProvider).valueOrNull ?? const <Inspection>[];
    final commandsLabs = ref.watch(controllableLabsProvider);
    final labsById = ref.watch(labsByIdProvider);

    final issues = equipment
        .where((item) =>
            item.condition.isIssue ||
            item.condition == EquipmentCondition.needsRepair)
        .length;
    final myLabs = labs.map((lab) => lab.id).toSet();
    final myAlerts = alerts
        .where((alert) => alert.labId.isEmpty || myLabs.contains(alert.labId))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          maxColumns: 4,
          children: [
            StatTile(label: 'Assigned laboratories', value: labs.length.toString(), icon: Icons.science_outlined, color: AppColors.royal, onTap: () => context.go('/labs')),
            StatTile(label: 'Active alerts', value: myAlerts.length.toString(), icon: Icons.warning_amber_rounded, color: myAlerts.isEmpty ? AppColors.success : AppColors.critical, onTap: () => context.go('/alerts')),
            StatTile(label: 'Equipment issues', value: issues.toString(), icon: Icons.build_outlined, color: issues == 0 ? AppColors.success : AppColors.critical, onTap: () => context.go('/equipment')),
            StatTile(label: 'Pending inspections', value: inspections.where((i) => i.problemCount > 0).length.toString(), icon: Icons.fact_check_outlined, color: AppColors.warning, caption: 'With recorded issues', onTap: () => context.go('/inspections')),
          ],
        ),
        const SizedBox(height: 14),
        _QuickActions(
          items: [
            const _Action(Icons.science_outlined, 'Laboratories', '/labs'),
            const _Action(Icons.warning_amber_rounded, 'Alerts', '/alerts'),
            const _Action(Icons.fact_check_outlined, 'Inspections', '/inspections'),
            if (user.mayControlDevices) const _Action(Icons.power_settings_new, 'Device control', '/control'),
          ],
        ),
        const SizedBox(height: 14),
        _LabStatusOverview(labs: labs),
        const SizedBox(height: 14),
        _RecentAlerts(alerts: myAlerts, labsById: labsById),
        if (commandsLabs.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Device control access',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.mayControlDevices
                      ? 'You can queue commands for ${commandsLabs.length} laboratory record(s). '
                          'Execution depends on each laboratory gateway.'
                      : 'Device control is not granted on your account.',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InstructorDashboard extends ConsumerWidget {
  const _InstructorDashboard({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
    final reservations = ref.watch(myReservationsProvider).valueOrNull ?? const <Reservation>[];
    final equipment = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
    final labsById = ref.watch(labsByIdProvider);
    final now = DateTime.now();

    final upcoming = reservations
        .where((r) => r.status.isUpcoming && r.endAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final availableLabs = labs.where((lab) => lab.status.canBeReserved).length;
    final problems = equipment.where((item) => item.condition.isIssue || item.condition == EquipmentCondition.needsRepair).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          maxColumns: 4,
          children: [
            StatTile(label: 'Available laboratories', value: availableLabs.toString(), icon: Icons.science_outlined, color: AppColors.success, onTap: () => context.go('/labs')),
            StatTile(label: 'Upcoming classes', value: upcoming.length.toString(), icon: Icons.event_available_outlined, color: AppColors.royal, onTap: () => context.go('/schedule')),
            StatTile(label: 'My reservations', value: reservations.length.toString(), icon: Icons.calendar_month_outlined, color: AppColors.info, onTap: () => context.go('/schedule')),
            StatTile(label: 'Equipment to check', value: problems.toString(), icon: Icons.inventory_2_outlined, color: problems == 0 ? AppColors.success : AppColors.warning, caption: 'Reported issues', onTap: () => context.go('/equipment')),
          ],
        ),
        const SizedBox(height: 14),
        const _QuickActions(
          items: [
            _Action(Icons.event_available_outlined, 'Reserve lab', '/schedule'),
            _Action(Icons.fact_check_outlined, 'Before-use check', '/inspections/new?type=before'),
            _Action(Icons.done_all, 'After-use check', '/inspections/new?type=after'),
            _Action(Icons.report_problem_outlined, 'Report equipment', '/equipment'),
          ],
        ),
        const SizedBox(height: 14),
        _UpcomingReservations(reservations: upcoming, labsById: labsById, title: 'My upcoming reservations'),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Equipment checklist',
          subtitle: 'Complete inspections before and after laboratory use',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(onPressed: () => context.go('/inspections/new?type=before'), icon: const Icon(Icons.fact_check_outlined, size: 18), label: const Text('Before-use inspection')),
              OutlinedButton.icon(onPressed: () => context.go('/inspections/new?type=after'), icon: const Icon(Icons.done_all, size: 18), label: const Text('After-use inspection')),
              OutlinedButton.icon(onPressed: () => context.go('/inspections'), icon: const Icon(Icons.history, size: 18), label: const Text('Inspection history')),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.items});

  final List<_Action> items;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Quick actions',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            OutlinedButton.icon(
              onPressed: () => context.go(item.route),
              icon: Icon(item.icon, size: 18),
              label: Text(item.label),
            ),
        ],
      ),
    );
  }
}

class _Action {
  const _Action(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;
}

class _RecentAlerts extends StatelessWidget {
  const _RecentAlerts({required this.alerts, required this.labsById});

  final List<LabAlert> alerts;
  final Map<String, Lab> labsById;

  @override
  Widget build(BuildContext context) {
    final open = alerts.where((alert) => !alert.status.isResolved).toList()..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return SectionCard(
      title: 'Active alerts',
      trailing: TextButton(onPressed: () => context.go('/alerts'), child: const Text('View all')),
      child: open.isEmpty
          ? const EmptyState(icon: Icons.check_circle_outline, title: 'No active alerts', message: 'Everything looks clear right now.')
          : Column(
              children: [
                for (final alert in open.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(alert.category.icon, color: alert.severity.color),
                    title: Text(alert.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (alert.labId.isNotEmpty) labsById[alert.labId]?.displayName ?? alert.labId,
                      if (alert.createdAt != null) DateFormat.MMMd().add_jm().format(alert.createdAt!),
                    ].join(' · ')),
                    trailing: StatusPill(label: alert.severity.label, color: alert.severity.color, dense: true),
                    onTap: () => context.go('/alerts'),
                  ),
              ],
            ),
    );
  }
}

class _UpcomingReservations extends StatelessWidget {
  const _UpcomingReservations({required this.reservations, required this.labsById, this.title = 'Upcoming reservations'});

  final List<Reservation> reservations;
  final Map<String, Lab> labsById;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      trailing: TextButton(onPressed: () => context.go('/schedule'), child: const Text('Open schedule')),
      child: reservations.isEmpty
          ? const EmptyState(icon: Icons.event_available_outlined, title: 'No upcoming reservations')
          : Column(
              children: [
                for (final reservation in reservations.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(reservation.status.icon, color: reservation.status.color),
                    title: Text(reservation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${labsById[reservation.labId]?.displayName ?? reservation.labName} · ${DateFormat.MMMd().add_Hm().format(reservation.startAt)}'),
                    trailing: StatusPill(label: reservation.status.label, color: reservation.status.color, dense: true),
                    onTap: () => context.go('/schedule'),
                  ),
              ],
            ),
    );
  }
}

class _LabStatusOverview extends StatelessWidget {
  const _LabStatusOverview({required this.labs});

  final List<Lab> labs;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Laboratory status overview',
      trailing: TextButton(onPressed: () => context.go('/labs'), child: const Text('Open labs')),
      child: labs.isEmpty
          ? const EmptyState(icon: Icons.science_outlined, title: 'No laboratories recorded', message: 'Administrators can add laboratories to begin monitoring.')
          : Column(
              children: [
                for (final lab in labs.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(lab.status.icon, color: lab.status.color),
                    title: Text(lab.displayName),
                    subtitle: Text([
                      if (lab.building.isNotEmpty) lab.building,
                      if (lab.capacity > 0) '${lab.capacity} seats',
                      lab.gatewayOnline ? 'Gateway online' : 'Gateway offline',
                    ].join(' · ')),
                    trailing: StatusPill(label: lab.status.label, color: lab.status.color, dense: true),
                    onTap: () => context.go('/labs/${lab.id}'),
                  ),
              ],
            ),
    );
  }
}

class _EquipmentSummary extends StatelessWidget {
  const _EquipmentSummary({required this.equipment});

  final List<Equipment> equipment;

  @override
  Widget build(BuildContext context) {
    final issues = equipment.where((item) => !item.condition.isHealthy).toList()
      ..sort((a, b) => b.condition.index.compareTo(a.condition.index));
    return SectionCard(
      title: 'Equipment condition summary',
      trailing: TextButton(onPressed: () => context.go('/equipment'), child: const Text('Open equipment')),
      child: issues.isEmpty
          ? const EmptyState(icon: Icons.verified_outlined, title: 'All equipment in good condition')
          : Column(
              children: [
                for (final item in issues.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.condition.icon, color: item.condition.color),
                    title: Text(item.name),
                    subtitle: Text(item.assetId.isEmpty ? item.labId : '${item.assetId} · Qty ${item.quantity}'),
                    trailing: StatusPill(label: item.condition.label, color: item.condition.color, dense: true),
                  ),
              ],
            ),
    );
  }
}

class _RecentActivitySummary extends StatelessWidget {
  const _RecentActivitySummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Recent activity',
      subtitle: count == 0 ? 'No activity records available yet' : '$count recent entries visible to your account',
      trailing: TextButton(onPressed: () => context.go('/activity'), child: const Text('Open activity')),
      child: const Text(
        'Sign-ins, reservations, inspections, equipment changes and device '
        'commands are recorded in the audit trail when the action succeeds.',
      ),
    );
  }
}

class _DemoModeCard extends ConsumerWidget {
  const _DemoModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    const sampleLabId = 'lab-1';
    final reading = ref.watch(labTelemetryProvider(sampleLabId)).valueOrNull;
    return SectionCard(
      title: 'Live telemetry preview',
      subtitle: demo
          ? 'Demonstration mode is ON — values are SAMPLE DATA'
          : 'Demonstration mode is OFF — values come from sensors or show OFFLINE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reading != null) ...[
            Row(
              children: [
                const Text('Laboratory 1', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                DataOriginBadge(reading.origin),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Demonstration mode'),
            subtitle: const Text(
              'Replaces sensor data with randomised SAMPLE DATA. Sample data '
              'never creates energy alerts and is never shown as live.',
            ),
            value: demo,
            onChanged: (value) => ref.read(demoModeProvider.notifier).state = value,
          ),
        ],
      ),
    );
  }
}
