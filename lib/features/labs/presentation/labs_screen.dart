import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/lab.dart';
import '../../authentication/data/auth_repository.dart';
import '../../equipment/data/equipment_repository.dart';
import '../data/lab_repository.dart';
import 'lab_form.dart';

enum _LabSort { name, status, building }

class LabsScreen extends ConsumerStatefulWidget {
  const LabsScreen({super.key});

  @override
  ConsumerState<LabsScreen> createState() => _LabsScreenState();
}

class _LabsScreenState extends ConsumerState<LabsScreen> {
  final _search = TextEditingController();
  String _query = '';
  LabStatus? _status;
  _LabSort _sort = _LabSort.name;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Lab> _filtered(List<Lab> labs) {
    final query = _query.trim().toLowerCase();
    final result = labs.where((lab) {
      final matchesQuery = query.isEmpty ||
          lab.name.toLowerCase().contains(query) ||
          lab.number.toLowerCase().contains(query) ||
          lab.building.toLowerCase().contains(query) ||
          lab.location.toLowerCase().contains(query);
      final matchesStatus = _status == null || lab.status == _status;
      return matchesQuery && matchesStatus;
    }).toList();

    switch (_sort) {
      case _LabSort.name:
        result.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _LabSort.status:
        result.sort((a, b) {
          final byStatus = a.status.index.compareTo(b.status.index);
          return byStatus != 0
              ? byStatus
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case _LabSort.building:
        result.sort((a, b) {
          final byBuilding =
              a.building.toLowerCase().compareTo(b.building.toLowerCase());
          return byBuilding != 0
              ? byBuilding
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final labsAsync = ref.watch(labsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laboratories'),
        actions: [
          if (user?.isAdmin == true)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => showLabForm(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add lab'),
              ),
            ),
        ],
      ),
      body: labsAsync.when(
        loading: () => const LoadingState(label: 'Loading laboratories…'),
        error: (_, __) => ErrorState(
          title: 'Could not load laboratories',
          message: 'Check your connection and your account permissions.',
          onRetry: () => ref.invalidate(labsProvider),
        ),
        data: (labs) {
          final filtered = _filtered(labs);
          return SingleChildScrollView(
            child: PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: 'Laboratory overview',
                    subtitle:
                        '${labs.length} laboratory record(s). Live occupancy '
                        'appears on each laboratory page when sensors report.',
                    breadcrumb: 'Monitoring',
                  ),
                  const SizedBox(height: 16),
                  _filters(labs),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    const SectionCard(
                      child: EmptyState(
                        icon: Icons.science_outlined,
                        title: 'No laboratories match',
                        message:
                            'Try a different search or status filter. '
                            'Administrators can add laboratories from this page.',
                      ),
                    )
                  else
                    _grid(context, filtered, user),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filters(List<Lab> labs) {
    final counts = <LabStatus, int>{};
    for (final lab in labs) {
      counts[lab.status] = (counts[lab.status] ?? 0) + 1;
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              final search = TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by name, number or building',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              );
              final sort = DropdownButtonFormField<_LabSort>(
                initialValue: _sort,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items: const [
                  DropdownMenuItem(value: _LabSort.name, child: Text('Name')),
                  DropdownMenuItem(value: _LabSort.status, child: Text('Status')),
                  DropdownMenuItem(
                    value: _LabSort.building,
                    child: Text('Building'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sort = value);
                },
              );
              if (!wide) {
                return Column(
                  children: [search, const SizedBox(height: 10), sort],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: sort),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('All ${labs.length}'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              for (final status in LabStatus.values)
                if ((counts[status] ?? 0) > 0)
                  ChoiceChip(
                    avatar: Icon(status.icon, size: 15, color: status.color),
                    label: Text('${status.label} ${counts[status]}'),
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

  Widget _grid(BuildContext context, List<Lab> labs, AppUser? user) {
    final equipment = ref.watch(equipmentProvider).valueOrNull ??
        const <Equipment>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 640
                ? 2
                : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final lab in labs)
              SizedBox(
                width: width,
                child: _LabCard(
                  lab: lab,
                  equipmentCount:
                      equipment.where((item) => item.labId == lab.id).length,
                  issueCount: equipment
                      .where(
                        (item) =>
                            item.labId == lab.id && item.condition.isIssue,
                      )
                      .length,
                  canEdit: user?.isAdmin == true,
                  onOpen: () => context.go('/labs/${lab.id}'),
                  onEdit: () => showLabForm(context, ref, lab: lab),
                ),
              ),
          ],
        );
      },
    );
  }

}

class _LabCard extends StatelessWidget {
  const _LabCard({
    required this.lab,
    required this.equipmentCount,
    required this.issueCount,
    required this.canEdit,
    required this.onOpen,
    required this.onEdit,
  });

  final Lab lab;
  final int equipmentCount;
  final int issueCount;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: lab.status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(lab.status.icon, color: lab.status.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                lab.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              flex: 0,
                              child: StatusPill(
                                label: lab.status.label,
                                color: lab.status.color,
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                        if (lab.number.isNotEmpty || lab.where.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            [lab.number, lab.where]
                                .where((part) => part.trim().isNotEmpty)
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _Meta(
                    icon: Icons.groups_outlined,
                    text: lab.capacity > 0 ? '${lab.capacity} seats' : 'Capacity not set',
                  ),
                  _Meta(
                    icon: Icons.inventory_2_outlined,
                    text: '$equipmentCount item(s)',
                    color: issueCount > 0 ? AppColors.critical : null,
                  ),
                  _Meta(
                    icon: lab.gatewayOnline ? Icons.sensors : Icons.sensors_off,
                    text: lab.gatewayOnline ? 'Gateway online' : 'Gateway offline',
                    color: lab.gatewayOnline
                        ? AppColors.success
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Open'),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Edit laboratory',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: resolvedColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: resolvedColor),
          ),
        ),
      ],
    );
  }
}
