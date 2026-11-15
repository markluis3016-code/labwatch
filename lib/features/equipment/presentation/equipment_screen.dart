import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/lab.dart';
import '../../authentication/data/auth_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../data/equipment_repository.dart';

enum _EquipmentFilter { all, attention, available }

class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({this.labFilter, super.key});

  final String? labFilter;

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _labId;
  EquipmentCondition? _condition;
  _EquipmentFilter _filter = _EquipmentFilter.all;

  @override
  void initState() {
    super.initState();
    _labId = widget.labFilter;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Equipment> _filtered(List<Equipment> items) {
    final query = _query.trim().toLowerCase();
    return items.where((item) {
      final matchesQuery = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.assetId.toLowerCase().contains(query) ||
          item.notes.toLowerCase().contains(query);
      final matchesLab = _labId == null || item.labId == _labId;
      final matchesCondition =
          _condition == null || item.condition == _condition;
      final matchesFilter = switch (_filter) {
        _EquipmentFilter.all => true,
        _EquipmentFilter.attention => item.condition != EquipmentCondition.good,
        _EquipmentFilter.available => item.isServiceable,
      };
      return matchesQuery &&
          matchesLab &&
          matchesCondition &&
          matchesFilter;
    }).toList(growable: false);
  }

  void _notify(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      _notify(success);
    } on AppFailure catch (failure) {
      _notify(failure.message, error: true);
    } catch (_) {
      _notify('Could not complete the request. Try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(equipmentProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
    final labsById = ref.watch(labsByIdProvider);
    final canEdit = user != null && (user.isAdmin || user.isStaff);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment'),
        actions: [
          if (canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => _openEditor(labs: labs),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add item'),
              ),
            ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const LoadingState(label: 'Loading equipment…'),
        error: (error, _) {
          final view = describeFirestoreLoadError(
            error,
            resource: 'equipment records',
          );
          return Center(
            child: ErrorState(
              title: view.title,
              message: view.message,
              onRetry: () => ref.invalidate(equipmentProvider),
            ),
          );
        },
        data: (items) {
          final filtered = _filtered(items);
          final issues = items
              .where((item) =>
                  item.condition == EquipmentCondition.damaged ||
                  item.condition == EquipmentCondition.missing)
              .length;
          final repairs = items
              .where((item) => item.condition == EquipmentCondition.needsRepair)
              .length;
          final available = items.where((item) => item.isServiceable).length;

          return PageBody(
            child: ListView(
              children: [
                PageHeader(
                  breadcrumb: 'Inventory',
                  title: 'Equipment management',
                  subtitle:
                      '${items.length} item(s) across ${labs.length} laboratory record(s).',
                ),
                const SizedBox(height: 16),
                StatGrid(
                  children: [
                    StatTile(
                      label: 'Serviceable',
                      value: available.toString(),
                      icon: Icons.verified_outlined,
                      color: AppColors.success,
                    ),
                    StatTile(
                      label: 'Needs repair',
                      value: repairs.toString(),
                      icon: Icons.build_outlined,
                      color: AppColors.warning,
                    ),
                    StatTile(
                      label: 'Damaged / missing',
                      value: issues.toString(),
                      icon: Icons.report_problem_outlined,
                      color: AppColors.critical,
                    ),
                    StatTile(
                      label: 'Total items',
                      value: items.length.toString(),
                      icon: Icons.inventory_2_outlined,
                      color: AppColors.royal,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _filters(labs),
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  SectionCard(
                    child: EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: items.isEmpty
                          ? 'No equipment records found'
                          : 'No equipment matches',
                      message: items.isEmpty
                          ? (canEdit
                              ? 'Add equipment to start tracking laboratory inventory.'
                              : 'No equipment has been recorded yet.')
                          : 'Clear the filters to see all equipment.',
                      action: items.isEmpty && canEdit
                          ? FilledButton.icon(
                              onPressed: () => _openEditor(labs: labs),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add equipment'),
                            )
                          : null,
                    ),
                  )
                else
                  _grid(filtered, labsById, user, canEdit),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filters(List<Lab> labs) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search equipment or asset ID',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              );
              final lab = InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Laboratory',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _labId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All laboratories'),
                      ),
                      for (final lab in labs)
                        DropdownMenuItem<String?>(
                          value: lab.id,
                          child: Text(lab.displayName, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) => setState(() => _labId = value),
                  ),
                ),
              );
              if (constraints.maxWidth < 640) {
                return Column(
                  children: [search, const SizedBox(height: 10), lab],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 2, child: search),
                  const SizedBox(width: 12),
                  Expanded(child: lab),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _EquipmentFilter.values)
                ChoiceChip(
                  label: Text(switch (filter) {
                    _EquipmentFilter.all => 'All',
                    _EquipmentFilter.attention => 'Needs attention',
                    _EquipmentFilter.available => 'Serviceable',
                  }),
                  selected: _filter == filter,
                  onSelected: (selected) =>
                      setState(() => _filter = selected ? filter : _EquipmentFilter.all),
                ),
              for (final condition in [
                EquipmentCondition.good,
                EquipmentCondition.needsRepair,
                EquipmentCondition.damaged,
                EquipmentCondition.missing,
              ])
                FilterChip(
                  label: Text(condition.label),
                  selected: _condition == condition,
                  onSelected: (selected) => setState(
                    () => _condition = selected ? condition : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grid(
    List<Equipment> items,
    Map<String, Lab> labs,
    AppUser? user,
    bool canEdit,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
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
            for (final item in items)
              SizedBox(
                width: width,
                child: _EquipmentCard(
                  item: item,
                  labName: labs[item.labId]?.displayName ?? item.labId,
                  canEdit: canEdit,
                  onOpen: () => _showDetail(item, labs, user, canEdit),
                  onReport: () => _reportProblem(item),
                  onEdit: canEdit
                      ? () => _openEditor(
                            labs: ref.read(labsProvider).valueOrNull ??
                                const <Lab>[],
                            item: item,
                          )
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor({required List<Lab> labs, Equipment? item}) async {
    if (labs.isEmpty) {
      _notify('Add a laboratory before adding equipment.', error: true);
      return;
    }
    final edited = await showDialog<Equipment>(
      context: context,
      builder: (_) => _EquipmentDialog(item: item, labs: labs),
    );
    if (edited == null || !mounted) return;
    await _run(
      () => ref.read(equipmentRepositoryProvider).save(
            edited,
            isNew: item == null,
            actor: ref.read(currentUserProvider).valueOrNull!,
          ),
      item == null ? 'Equipment added.' : 'Equipment updated.',
    );
  }

  Future<void> _reportProblem(Equipment item) async {
    final controller = TextEditingController();
    final report = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Report problem · ${item.name}'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'What is wrong? *',
            hintText: 'Describe the damage or missing item.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (report == null || !mounted) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    await _run(
      () => ref
          .read(equipmentRepositoryProvider)
          .reportProblem(item, description: report, reporter: user),
      'Problem reported. Staff and administrators can see it in Alerts.',
    );
  }

  void _showDetail(
    Equipment item,
    Map<String, Lab> labs,
    AppUser? user,
    bool canEdit,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(item.condition.icon, color: item.condition.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                StatusPill(
                  label: item.condition.label,
                  color: item.condition.color,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _Info(label: 'Laboratory', value: labs[item.labId]?.displayName ?? item.labId),
                _Info(label: 'Asset ID', value: item.assetId.isEmpty ? 'Not set' : item.assetId),
                _Info(label: 'Quantity', value: item.quantity.toString()),
                _Info(label: 'Availability', value: item.available ? 'Available' : 'Unavailable'),
                _Info(
                  label: 'Last inspected',
                  value: item.lastInspectedAt == null
                      ? 'Never'
                      : DateFormat.yMMMd().format(item.lastInspectedAt!),
                ),
              ],
            ),
            if (item.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(item.notes),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _reportProblem(item);
                  },
                  icon: const Icon(Icons.report_problem_outlined, size: 18),
                  label: const Text('Report problem'),
                ),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openEditor(
                        labs: ref.read(labsProvider).valueOrNull ??
                            const <Lab>[],
                        item: item,
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.go('/labs/${item.labId}');
                  },
                  child: const Text('Open laboratory'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({
    required this.item,
    required this.labName,
    required this.canEdit,
    required this.onOpen,
    required this.onReport,
    this.onEdit,
  });

  final Equipment item;
  final String labName;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onReport;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: item.condition.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.condition.icon, color: item.condition.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: item.condition.label,
                    color: item.condition.color,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(labName, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                [
                  if (item.assetId.isNotEmpty) item.assetId,
                  'Qty ${item.quantity}',
                  if (!item.available) 'Unavailable',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.info_outline, size: 17),
                    label: const Text('Details'),
                  ),
                  TextButton.icon(
                    onPressed: onReport,
                    icon: const Icon(Icons.report_problem_outlined, size: 17),
                    label: const Text('Report'),
                  ),
                  if (canEdit && onEdit != null)
                    IconButton(
                      tooltip: 'Edit equipment',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 20),
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

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _EquipmentDialog extends StatefulWidget {
  const _EquipmentDialog({required this.labs, this.item});

  final List<Lab> labs;
  final Equipment? item;

  @override
  State<_EquipmentDialog> createState() => _EquipmentDialogState();
}

class _EquipmentDialogState extends State<_EquipmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _assetId;
  late final TextEditingController _quantity;
  late final TextEditingController _notes;
  late String _labId;
  late EquipmentCondition _condition;
  late bool _available;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _assetId = TextEditingController(text: item?.assetId ?? '');
    _quantity = TextEditingController(text: item == null ? '1' : '${item.quantity}');
    _notes = TextEditingController(text: item?.notes ?? '');
    _labId = item?.labId ??
        (widget.labs.isNotEmpty ? widget.labs.first.id : '');
    _condition = item?.condition ?? EquipmentCondition.good;
    _available = item?.available ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _assetId.dispose();
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final item = widget.item;
    Navigator.of(context).pop(
      Equipment(
        id: item?.id ?? '',
        name: _name.text.trim(),
        labId: _labId,
        assetId: _assetId.text.trim(),
        quantity: int.tryParse(_quantity.text.trim()) ?? 0,
        condition: _condition,
        available: _available,
        notes: _notes.text.trim(),
        lastInspectedAt: item?.lastInspectedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Add equipment' : 'Edit equipment'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Equipment name *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: EquipmentValidator.name,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _labId.isEmpty ? null : _labId,
                  decoration: const InputDecoration(labelText: 'Laboratory *'),
                  items: [
                    for (final lab in widget.labs)
                      DropdownMenuItem(
                        value: lab.id,
                        child: Text(lab.displayName, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  validator: (value) =>
                      (value ?? '').isEmpty ? 'Choose a laboratory.' : null,
                  onChanged: (value) {
                    if (value != null) setState(() => _labId = value);
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final asset = TextFormField(
                      controller: _assetId,
                      decoration: const InputDecoration(labelText: 'Asset ID'),
                      validator: EquipmentValidator.assetId,
                    );
                    final quantity = TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity *'),
                      validator: EquipmentValidator.quantity,
                    );
                    if (constraints.maxWidth < 420) {
                      return Column(
                        children: [asset, const SizedBox(height: 12), quantity],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: asset),
                        const SizedBox(width: 12),
                        Expanded(child: quantity),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EquipmentCondition>(
                  initialValue: _condition,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: [
                    for (final condition in EquipmentCondition.values)
                      if (condition != EquipmentCondition.unknown)
                        DropdownMenuItem(
                          value: condition,
                          child: Text(condition.label),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _condition = value);
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available for use'),
                  value: _available,
                  onChanged: (value) => setState(() => _available = value),
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  validator: EquipmentValidator.notes,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.item == null ? 'Add equipment' : 'Save changes'),
        ),
      ],
    );
  }
}
