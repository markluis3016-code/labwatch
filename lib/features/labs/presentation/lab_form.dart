import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/lab.dart';
import '../data/lab_repository.dart';

/// Admin-only laboratory editor. Returns true when the record was saved.
Future<bool> showLabForm(
  BuildContext context,
  WidgetRef ref, {
  Lab? lab,
}) async {
  final edited = await showDialog<Lab>(
    context: context,
    builder: (_) => LabFormDialog(lab: lab),
  );
  if (edited == null) return false;

  try {
    await ref.read(labRepositoryProvider).saveLab(edited, isNew: lab == null);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lab == null ? 'Laboratory added.' : 'Laboratory updated.'),
      ),
    );
    return true;
  } on AppFailure catch (failure) {
    if (context.mounted) _showError(context, failure.message);
  } catch (_) {
    if (context.mounted) {
      _showError(context, 'Could not save the laboratory. Try again.');
    }
  }
  return false;
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

class LabFormDialog extends StatefulWidget {
  const LabFormDialog({this.lab, super.key});

  final Lab? lab;

  @override
  State<LabFormDialog> createState() => _LabFormDialogState();
}

class _LabFormDialogState extends State<LabFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _number;
  late final TextEditingController _building;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  late LabStatus _status;

  @override
  void initState() {
    super.initState();
    final lab = widget.lab;
    _name = TextEditingController(text: lab?.name ?? '');
    _number = TextEditingController(text: lab?.number ?? '');
    _building = TextEditingController(text: lab?.building ?? '');
    _location = TextEditingController(text: lab?.location ?? '');
    _capacity =
        TextEditingController(text: lab == null ? '' : lab.capacity.toString());
    _notes = TextEditingController(text: lab?.notes ?? '');
    _status = lab?.status ?? LabStatus.available;
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _building.dispose();
    _location.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final lab = widget.lab;
    Navigator.of(context).pop(
      Lab(
        id: lab?.id ?? '',
        name: _name.text.trim(),
        number: _number.text.trim(),
        building: _building.text.trim(),
        location: _location.text.trim(),
        capacity: int.tryParse(_capacity.text.trim()) ?? 0,
        status: _status,
        notes: _notes.text.trim(),
        assignedStaffIds: lab?.assignedStaffIds ?? const [],
        gatewayOnline: lab?.gatewayOnline ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.lab == null ? 'Add laboratory' : 'Edit laboratory'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Laboratory name *',
                    prefixIcon: Icon(Icons.science_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.length < 2) return 'Enter a laboratory name.';
                    if (text.length > 80) {
                      return 'Keep the name under 80 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      TextFormField(
                        controller: _number,
                        decoration:
                            const InputDecoration(labelText: 'Lab number'),
                      ),
                      TextFormField(
                        controller: _building,
                        decoration:
                            const InputDecoration(labelText: 'Building'),
                      ),
                    ];
                    if (constraints.maxWidth < 420) {
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 12),
                          fields[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(
                    labelText: 'Room / floor / location',
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final capacity = TextFormField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Capacity'),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return null;
                        final parsed = int.tryParse(text);
                        if (parsed == null || parsed < 0) {
                          return 'Enter a whole number.';
                        }
                        return null;
                      },
                    );
                    final status = DropdownButtonFormField<LabStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final status in LabStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _status = value);
                      },
                    );
                    if (constraints.maxWidth < 420) {
                      return Column(
                        children: [
                          capacity,
                          const SizedBox(height: 12),
                          status,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: capacity),
                        const SizedBox(width: 12),
                        Expanded(child: status),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const InfoBanner(
                  text: 'Gateway status and live sensor readings are written by '
                      'the IoT backend, not by this form.',
                  icon: Icons.sensors_outlined,
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
          child: Text(widget.lab == null ? 'Add laboratory' : 'Save changes'),
        ),
      ],
    );
  }
}
