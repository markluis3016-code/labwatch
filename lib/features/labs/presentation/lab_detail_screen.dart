import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/inspection.dart';
import '../../../shared/models/lab.dart';
import '../../authentication/data/auth_repository.dart';
import '../../equipment/data/equipment_repository.dart';
import '../../inspections/data/inspection_repository.dart';
import '../../monitoring/data/telemetry_providers.dart';
import '../../monitoring/domain/telemetry.dart';
import '../../scheduling/data/reservation_repository.dart';
import '../data/lab_repository.dart';
import 'lab_form.dart';

class LabDetailScreen extends ConsumerWidget {
  const LabDetailScreen({required this.labId, super.key});

  final String labId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labAsync = ref.watch(labProvider(labId));
    final user = ref.watch(currentUserProvider).valueOrNull;
    final demo = ref.watch(demoModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(labAsync.valueOrNull?.displayName ?? 'Laboratory'),
        leading: IconButton(
          tooltip: 'Back to laboratories',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/labs'),
        ),
        actions: [
          if (user?.isAdmin == true && labAsync.valueOrNull != null)
            IconButton(
              tooltip: 'Edit laboratory',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  showLabForm(context, ref, lab: labAsync.valueOrNull),
            ),
        ],
      ),
      body: labAsync.when(
        loading: () => const LoadingState(label: 'Loading laboratory…'),
        error: (_, __) => ErrorState(
          title: 'Could not load the laboratory',
          message: 'The record may have been removed, or access was denied.',
          onRetry: () => ref.invalidate(labProvider(labId)),
        ),
        data: (lab) {
          if (lab == null) {
            return PageBody(
              child: SectionCard(
                child: EmptyState(
                  icon: Icons.search_off,
                  title: 'Laboratory not found',
                  message: 'It may have been removed by an administrator.',
                  action: FilledButton(
                    onPressed: () => context.go('/labs'),
                    child: const Text('Back to laboratories'),
                  ),
                ),
              ),
            );
          }
          return PageBody(
            child: _content(context, ref, lab, user, demo),
          );
        },
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    Lab lab,
    AppUser? user,
    bool demo,
  ) {
    final telemetry = ref.watch(labTelemetryProvider(lab.id));
    final equipment = ref.watch(labEquipmentProvider(lab.id)).valueOrNull ??
        const <Equipment>[];
    final inspections = ref.watch(labInspectionsProvider(lab.id)).valueOrNull ??
        const <Inspection>[];
    final reservations = ref.watch(visibleReservationsProvider);
    final upcoming = reservations
        .where((reservation) =>
            reservation.labId == lab.id &&
            reservation.status.isUpcoming &&
            reservation.endAt.isAfter(DateTime.now()))
        .toList(growable: false)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final issues =
        equipment.where((item) => item.condition.isIssue).toList(growable: false);
    final mayControl = user?.mayControlDevices ?? false;

    return ListView(
      children: [
        PageHeader(
          breadcrumb: 'Monitoring · Laboratories',
          title: lab.displayName,
          subtitle: [
            if (lab.number.trim().isNotEmpty) 'Lab ${lab.number}',
            if (lab.where.trim().isNotEmpty) lab.where,
            if (lab.capacity > 0) '${lab.capacity} seats',
          ].join(' · '),
          actions: [
            StatusPill(
              label: lab.status.label,
              color: lab.status.color,
              icon: lab.status.icon,
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/schedule?lab=${lab.id}'),
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('Reserve'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _LiveCard(lab: lab, telemetry: telemetry, demo: demo),
        const SizedBox(height: 14),
        _QuickActions(lab: lab, mayControl: mayControl),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Laboratory details',
          trailing: lab.gatewayOnline
              ? const StatusPill(
                  label: 'Gateway online',
                  color: AppColors.success,
                  dense: true,
                  icon: Icons.sensors,
                )
              : const StatusPill(
                  label: 'Gateway offline',
                  color: AppColors.lightMuted,
                  dense: true,
                  icon: Icons.sensors_off,
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Fact(
                    icon: Icons.science_outlined,
                    label: 'Laboratory',
                    value: lab.displayName,
                  ),
                  _Fact(
                    icon: Icons.tag,
                    label: 'Number',
                    value: lab.number.trim().isEmpty ? 'Not set' : lab.number,
                  ),
                  _Fact(
                    icon: Icons.apartment_outlined,
                    label: 'Building',
                    value: lab.building.trim().isEmpty ? 'Not set' : lab.building,
                  ),
                  _Fact(
                    icon: Icons.place_outlined,
                    label: 'Location',
                    value: lab.location.trim().isEmpty ? 'Not set' : lab.location,
                  ),
                  _Fact(
                    icon: Icons.groups_outlined,
                    label: 'Capacity',
                    value: lab.capacity > 0 ? '${lab.capacity} seats' : 'Not set',
                  ),
                  _Fact(
                    icon: Icons.inventory_2_outlined,
                    label: 'Equipment',
                    value: '${equipment.length} item(s)',
                  ),
                ],
              ),
              if (lab.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(lab.notes, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Equipment',
          subtitle: issues.isEmpty
              ? 'No equipment issues recorded'
              : '${issues.length} item(s) need attention',
          trailing: TextButton(
            onPressed: () => context.go('/equipment?lab=${lab.id}'),
            child: const Text('View all'),
          ),
          child: equipment.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No equipment recorded',
                  message:
                      'Administrators can add equipment from the Equipment page.',
                )
              : Column(
                  children: [
                    for (final item in equipment.take(6))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.condition.icon,
                          color: item.condition.color,
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.assetId.isEmpty ? 'No asset ID' : item.assetId}'
                          ' · Qty ${item.quantity}',
                        ),
                        trailing: StatusPill(
                          label: item.condition.label,
                          color: item.condition.color,
                          dense: true,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Upcoming reservations',
          subtitle: upcoming.isEmpty
              ? 'No upcoming bookings for this laboratory'
              : '${upcoming.length} upcoming',
          child: upcoming.isEmpty
              ? const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No reservations',
                  message: 'Use Reserve to book this laboratory.',
                )
              : Column(
                  children: [
                    for (final reservation in upcoming.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          reservation.status.icon,
                          color: reservation.status.color,
                        ),
                        title: Text(reservation.title),
                        subtitle: Text(
                          '${DateFormat.MMMd().add_Hm().format(reservation.startAt)}'
                          ' – ${DateFormat.Hm().format(reservation.endAt)}'
                          ' · ${reservation.instructorName}',
                        ),
                        trailing: StatusPill(
                          label: reservation.status.label,
                          color: reservation.status.color,
                          dense: true,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Recent inspections',
          trailing: TextButton(
            onPressed: () =>
                context.go('/inspections?lab=${lab.id}'),
            child: const Text('History'),
          ),
          child: inspections.isEmpty
              ? const EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No inspections yet',
                  message: 'Before-use and after-use checklists appear here.',
                )
              : Column(
                  children: [
                    for (final inspection in inspections.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          inspection.problemCount > 0
                              ? Icons.report_problem_outlined
                              : Icons.fact_check_outlined,
                          color: inspection.problemCount > 0
                              ? AppColors.critical
                              : AppColors.success,
                        ),
                        title: Text(
                          '${inspection.type.label} · '
                          '${inspection.checkedCount} item(s)',
                        ),
                        subtitle: Text(
                          [
                            if (inspection.createdAt != null)
                              DateFormat.yMMMd()
                                  .add_jm()
                                  .format(inspection.createdAt!),
                            inspection.inspectorName,
                          ].join(' · '),
                        ),
                        trailing: inspection.problemCount == 0
                            ? const StatusPill(
                                label: 'No issues',
                                color: AppColors.success,
                                dense: true,
                              )
                            : StatusPill(
                                label:
                                    '${inspection.problemCount} issue(s)',
                                color: AppColors.critical,
                                dense: true,
                              ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.lab,
    required this.telemetry,
    required this.demo,
  });

  final Lab lab;
  final AsyncValue<LabTelemetry> telemetry;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final reading = telemetry.valueOrNull ?? LabTelemetry.offline(lab.id);
    final offline = reading.origin == DataOrigin.offline;
    final theme = Theme.of(context);

    String power(PowerState state) => switch (state) {
          PowerState.on => 'ON',
          PowerState.off => 'OFF',
          PowerState.unknown => 'Unknown',
        };

    return SectionCard(
      title: 'Live conditions',
      subtitle: offline
          ? 'No current device connection — values cannot be verified'
          : demo
              ? 'SAMPLE DATA — randomised demonstration readings'
              : 'LIVE DATA from the laboratory gateway',
      trailing: DataOriginBadge(reading.origin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offline)
            const InfoBanner(
              text: 'Sensors are offline or the last reading is stale. '
                  'Occupancy and device states are unknown.',
              color: AppColors.critical,
              icon: Icons.sensors_off,
            ),
          const SizedBox(height: 12),
          StatGrid(
            maxColumns: 4,
            minTileWidth: 150,
            children: [
              _Metric(
                label: 'Occupancy',
                value: reading.occupied == null
                    ? 'Unknown'
                    : reading.occupied!
                        ? 'Occupied'
                        : 'Empty',
                icon: Icons.people_alt_outlined,
                color: reading.occupied == null
                    ? theme.colorScheme.onSurfaceVariant
                    : AppColors.royal,
              ),
              _Metric(
                label: 'Lights',
                value: power(reading.light),
                icon: Icons.lightbulb_outline,
                color: reading.light == PowerState.on
                    ? AppColors.warning
                    : AppColors.success,
              ),
              _Metric(
                label: 'Air conditioning',
                value: power(reading.ac),
                icon: Icons.ac_unit,
                color: reading.ac == PowerState.on
                    ? AppColors.warning
                    : AppColors.success,
              ),
              _Metric(
                label: 'Last reading',
                value: reading.sensorTimestamp == null
                    ? 'Never'
                    : DateFormat.Hms().format(reading.sensorTimestamp!),
                icon: Icons.schedule,
                color: AppColors.info,
              ),
            ],
          ),
          if (reading.origin == DataOrigin.sample)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: InfoBanner(
                text: 'Demonstration mode is on. Sample readings never create '
                    'energy alerts and are never presented as live data.',
                color: AppColors.warning,
                icon: Icons.science_outlined,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.lab, required this.mayControl});

  final Lab lab;
  final bool mayControl;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Actions',
      subtitle: 'Permissions are applied to each action',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go('/schedule?lab=${lab.id}'),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('Reserve laboratory'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                context.go('/inspections/new?lab=${lab.id}&type=before'),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Before-use inspection'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                context.go('/inspections/new?lab=${lab.id}&type=after'),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('After-use inspection'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go('/equipment?lab=${lab.id}'),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Equipment'),
          ),
          if (mayControl)
            FilledButton.icon(
              onPressed: () => context.go('/control?lab=${lab.id}'),
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: const Text('Device control'),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
