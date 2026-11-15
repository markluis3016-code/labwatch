import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/inspection.dart';
import '../../../shared/models/lab.dart';
import '../../authentication/data/auth_repository.dart';
import '../../equipment/data/equipment_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../data/inspection_repository.dart';

class InspectionsScreen extends ConsumerWidget {
  const InspectionsScreen({this.labFilter, super.key});

  final String? labFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final inspectionsAsync = user?.isAdmin == true
        ? ref.watch(recentInspectionsProvider)
        : ref.watch(myInspectionsProvider);
    final labsById = ref.watch(labsByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspections'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => context.go(
                '/inspections/new${labFilter == null ? '' : '?lab=$labFilter'}',
              ),
              icon: const Icon(Icons.add_task, size: 18),
              label: const Text('New check'),
            ),
          ),
        ],
      ),
      body: inspectionsAsync.when(
        loading: () => const LoadingState(label: 'Loading inspections…'),
        error: (_, __) => ErrorState(
          message: 'Check your connection and permissions.',
          onRetry: () => ref.invalidate(
            user?.isAdmin == true
                ? recentInspectionsProvider
                : myInspectionsProvider,
          ),
        ),
        data: (inspections) {
          final filtered = labFilter == null
              ? inspections
              : inspections
                  .where((inspection) => inspection.labId == labFilter)
                  .toList(growable: false);
          return PageBody(
            maxWidth: 1100,
            child: ListView(
              children: [
                const PageHeader(
                  breadcrumb: 'Operations',
                  title: 'Before-use and after-use checks',
                  subtitle:
                      'Checklist records are kept for future reference. '
                      'Changes from Good to Damaged or Missing create '
                      'equipment alerts automatically.',
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  SectionCard(
                    child: EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'No inspections yet',
                      message:
                          'Complete a before-use checklist at the start of a '
                          'session and an after-use checklist when finished.',
                      action: FilledButton.icon(
                        onPressed: () => context.go('/inspections/new'),
                        icon: const Icon(Icons.add_task, size: 18),
                        label: const Text('Start inspection'),
                      ),
                    ),
                  )
                else
                  for (final inspection in filtered) ...[
                    _InspectionCard(
                      inspection: inspection,
                      labName: labsById[inspection.labId]?.displayName ??
                          inspection.labName,
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.inspection, required this.labName});

  final Inspection inspection;
  final String labName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problems = inspection.problemCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  inspection.type == InspectionType.before
                      ? Icons.fact_check_outlined
                      : Icons.done_all,
                  color: problems == 0 ? AppColors.success : AppColors.critical,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${inspection.type.label} inspection · $labName',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          if (inspection.createdAt != null)
                            DateFormat.yMMMd()
                                .add_jm()
                                .format(inspection.createdAt!),
                          inspection.inspectorName,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: problems == 0 ? 'No issues' : '$problems issue(s)',
                  color: problems == 0 ? AppColors.success : AppColors.critical,
                  dense: true,
                ),
              ],
            ),
            if (inspection.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(inspection.notes, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in inspection.items.take(6))
                  StatusPill(
                    label: '${item.name}: ${item.condition.label}',
                    color: item.condition.color,
                    dense: true,
                  ),
                if (inspection.items.length > 6)
                  StatusPill(
                    label: '+${inspection.items.length - 6} more',
                    color: theme.colorScheme.onSurfaceVariant,
                    dense: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone form screen so inspections can be linked from labs/schedule.
class InspectionFormScreen extends ConsumerStatefulWidget {
  const InspectionFormScreen({
    this.initialLabId,
    this.initialType,
    this.reservationId,
    super.key,
  });

  final String? initialLabId;
  final InspectionType? initialType;
  final String? reservationId;

  @override
  ConsumerState<InspectionFormScreen> createState() =>
      _InspectionFormScreenState();
}

class _InspectionFormScreenState extends ConsumerState<InspectionFormScreen> {
  final _notes = TextEditingController();
  String? _labId;
  InspectionType _type = InspectionType.before;
  final Map<String, _ItemState> _items = {};
  bool _saving = false;
  String? _error;
  bool _loadedEquipment = false;

  @override
  void initState() {
    super.initState();
    _labId = widget.initialLabId;
    _type = widget.initialType ?? InspectionType.before;
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final item in _items.values) {
      item.dispose();
    }
    super.dispose();
  }

  void _ensureItems(List<Equipment> equipment) {
    if (_loadedEquipment) return;
    _loadedEquipment = true;
    for (final eq in equipment) {
      _items[eq.id] = _ItemState.fromEquipment(eq);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
    final equipment = _labId == null
        ? const <Equipment>[]
        : (ref.watch(labEquipmentProvider(_labId!)).valueOrNull ??
            const <Equipment>[]);

    if (_labId != null && equipment.isNotEmpty) _ensureItems(equipment);

    return Scaffold(
      appBar: AppBar(title: const Text('New inspection')),
      body: PageBody(
        maxWidth: 860,
        child: ListView(
          children: [
            SectionCard(
              title: 'Inspection details',
              subtitle:
                  'Before use: verify equipment condition and quantity. '
                  'After use: record any changes and report damage.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _labId,
                    decoration: const InputDecoration(
                      labelText: 'Laboratory *',
                      prefixIcon: Icon(Icons.science_outlined),
                    ),
                    items: [
                      for (final lab in labs)
                        DropdownMenuItem(
                          value: lab.id,
                          child: Text(lab.displayName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      for (final item in _items.values) {
                        item.dispose();
                      }
                      setState(() {
                        _labId = value;
                        _items.clear();
                        _loadedEquipment = false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<InspectionType>(
                    segments: const [
                      ButtonSegment(
                        value: InspectionType.before,
                        label: Text('Before use'),
                        icon: Icon(Icons.fact_check_outlined),
                      ),
                      ButtonSegment(
                        value: InspectionType.after,
                        label: Text('After use'),
                        icon: Icon(Icons.done_all),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) =>
                        setState(() => _type = value.first),
                  ),
                  if (widget.reservationId != null) ...[
                    const SizedBox(height: 10),
                    InfoBanner(
                      text: 'Linked to reservation ${widget.reservationId}.',
                      icon: Icons.link,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_labId == null)
              const SectionCard(
                child: EmptyState(
                  icon: Icons.science_outlined,
                  title: 'Choose a laboratory',
                  message: 'Select a laboratory to load its equipment checklist.',
                ),
              )
            else if (equipment.isEmpty)
              const SectionCard(
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No equipment to inspect',
                  message:
                      'Administrators or staff can add equipment for this '
                      'laboratory. You can still submit a general inspection '
                      'note below if needed.',
                ),
              )
            else
              SectionCard(
                title: 'Equipment checklist',
                subtitle:
                    '${equipment.length} item(s). Mark condition and verify quantity.',
                child: Column(
                  children: [
                    for (final eq in equipment)
                      _ChecklistRow(
                        equipment: eq,
                        state: _items.putIfAbsent(
                          eq.id,
                          () => _ItemState.fromEquipment(eq),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Notes',
              child: TextField(
                controller: _notes,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Inspection notes (optional)',
                  hintText:
                      'Mention damage, missing items, or anything unusual.',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              InfoBanner(
                text: _error!,
                color: AppColors.critical,
                icon: Icons.error_outline,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : () => _submit(user),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save inspection'),
            ),
            const SizedBox(height: 12),
            const InfoBanner(
              text: 'Saving an inspection creates a permanent record. '
                  'Problem items raise equipment alerts. Photo attachments '
                  'require Firebase Storage configuration and a supported '
                  'client flow.',
              icon: Icons.info_outline,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(AppUser? user) async {
    if (user == null || _labId == null) {
      setState(() => _error = 'Choose a laboratory first.');
      return;
    }
    final labs = ref.read(labsByIdProvider);
    final lab = labs[_labId!];
    final labName = lab?.displayName ?? _labId!;

    final items = _items.values
        .map(
          (state) => InspectionItem(
            equipmentId: state.equipmentId,
            name: state.name,
            condition: state.condition,
            quantityExpected: state.expected,
            quantityFound: state.found,
            notes: state.notes.text,
          ),
        )
        .toList(growable: false);

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      Inspection? before;
      if (_type == InspectionType.after) {
        final snap = await ref.read(
          latestInspectionProvider(
            (labId: _labId!, type: InspectionType.before),
          ).future,
        );
        before = snap;
      }

      await ref.read(inspectionRepositoryProvider).create(
            Inspection(
              id: '',
              labId: _labId!,
              labName: labName,
              type: _type,
              inspectorId: user.uid,
              inspectorName:
                  user.displayName.isEmpty ? user.email : user.displayName,
              items: items,
              reservationId: widget.reservationId ?? '',
              notes: _notes.text,
            ),
            actor: user,
            before: before,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Inspection saved. Problem items were reported as alerts.',
          ),
        ),
      );
      context.go('/inspections${_labId == null ? '' : '?lab=$_labId'}');
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the inspection. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ItemState {
  _ItemState({
    required this.equipmentId,
    required this.name,
    required this.expected,
    required this.condition,
    required this.found,
  }) : notes = TextEditingController();

  factory _ItemState.fromEquipment(Equipment equipment) => _ItemState(
        equipmentId: equipment.id,
        name: equipment.name,
        expected: equipment.quantity,
        condition: equipment.condition == EquipmentCondition.unknown
            ? EquipmentCondition.good
            : equipment.condition,
        found: equipment.quantity,
      );

  final String equipmentId;
  final String name;
  final int expected;
  EquipmentCondition condition;
  int found;
  final TextEditingController notes;

  void dispose() => notes.dispose();
}

class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({required this.equipment, required this.state});

  final Equipment equipment;
  final _ItemState state;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final TextEditingController _found;

  @override
  void initState() {
    super.initState();
    _found = TextEditingController(text: widget.state.found.toString());
  }

  @override
  void dispose() {
    _found.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.equipment.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusPill(
                  label: state.condition.label,
                  color: state.condition.color,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final condition = DropdownButtonFormField<EquipmentCondition>(
                  initialValue: state.condition,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: [
                    for (final condition in [
                      EquipmentCondition.good,
                      EquipmentCondition.needsRepair,
                      EquipmentCondition.damaged,
                      EquipmentCondition.missing,
                    ])
                      DropdownMenuItem(
                        value: condition,
                        child: Text(condition.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => state.condition = value);
                  },
                );
                final qty = TextFormField(
                  controller: _found,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Qty found (expected ${state.expected})',
                  ),
                  onChanged: (value) {
                    state.found = int.tryParse(value) ?? state.expected;
                  },
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [condition, const SizedBox(height: 8), qty],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: condition),
                    const SizedBox(width: 10),
                    SizedBox(width: 170, child: qty),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: state.notes,
              decoration: const InputDecoration(
                labelText: 'Item note (optional)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
