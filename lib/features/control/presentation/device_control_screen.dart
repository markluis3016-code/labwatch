import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/models/lab.dart';
import '../../authentication/data/auth_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../data/device_control_repository.dart';
import '../data/device_simulation_repository.dart';

class DeviceControlScreen extends ConsumerStatefulWidget {
  const DeviceControlScreen({this.initialLabId, super.key});

  final String? initialLabId;

  @override
  ConsumerState<DeviceControlScreen> createState() =>
      _DeviceControlScreenState();
}

class _DeviceControlScreenState extends ConsumerState<DeviceControlScreen> {
  String? _labId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _labId ??= widget.initialLabId;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final labs = ref.watch(controllableLabsProvider);
    final selected = _resolveSelected(labs);

    return Scaffold(
      appBar: AppBar(title: const Text('Device control')),
      body: PageBody(
        child: ListView(
          children: [
            const PageHeader(
              breadcrumb: 'Operations',
              title: 'Laboratory device control',
              subtitle:
                  'Manage laboratory lights and air conditioning. Actual gateway '
                  'connectivity is shown separately for each laboratory.',
            ),
            const SizedBox(height: 16),
            if (user == null || !user.mayControlDevices)
              const SectionCard(
                child: EmptyState(
                  icon: Icons.lock_outline,
                  title: 'Not authorised',
                  message:
                      'Device control requires an active administrator account, '
                      'or a staff account with the device-control grant and at '
                      'least one assigned laboratory.',
                ),
              )
            else if (labs.isEmpty)
              const SectionCard(
                child: EmptyState(
                  icon: Icons.science_outlined,
                  title: 'No controllable laboratories',
                  message:
                      'Ask an administrator to assign laboratories to your '
                      'account.',
                ),
              )
            else ...[
              SectionCard(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(selected?.id),
                  initialValue: selected?.id,
                  decoration: const InputDecoration(
                    labelText: 'Laboratory',
                    prefixIcon: Icon(Icons.science_outlined),
                  ),
                  items: [
                    for (final lab in labs)
                      DropdownMenuItem(
                        value: lab.id,
                        child: Text(lab.displayName),
                      ),
                  ],
                  onChanged: (value) => setState(() => _labId = value),
                ),
              ),
              const SizedBox(height: 14),
              if (selected != null) _LabSimulationControl(lab: selected),
            ],
          ],
        ),
      ),
    );
  }

  Lab? _resolveSelected(List<Lab> labs) {
    if (labs.isEmpty) return null;
    if (_labId != null) {
      for (final lab in labs) {
        if (lab.id == _labId) return lab;
      }
    }
    return labs.first;
  }
}

class _LabSimulationControl extends ConsumerWidget {
  const _LabSimulationControl({required this.lab});

  final Lab lab;

  Future<void> _setDevice(
    BuildContext context,
    WidgetRef ref, {
    required SimDeviceKind device,
    required bool turnOn,
  }) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // Preserve existing permission intent: admin, or staff with device-control
    // grant and assignment to this laboratory (mayControlDevices + assignment).
    final allowed = user.isAdmin || user.assignedLabIds.contains(lab.id);
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You are not permitted to control this laboratory.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // SIMULATION ONLY: updates local state/history and does not send real IoT
    // commands or write to Firestore telemetry/command collections.
    final changed = await ref.read(deviceSimulationProvider.notifier).setDevice(
          labId: lab.id,
          labName: lab.displayName,
          device: device,
          turnOn: turnOn,
          actorUid: user.uid,
          actorName: user.displayName.isNotEmpty ? user.displayName : user.email,
        );

    if (!context.mounted) return;
    if (!changed) return;

    final deviceLabel = device.label;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$deviceLabel turned ${turnOn ? 'ON' : 'OFF'}.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sim = ref.watch(deviceSimulationProvider);
    final state = sim.stateFor(lab.id);
    final history = sim.historyFor(lab.id);
    // Real gateway command history remains separate (no simulated records here).
    final realCommands = ref.watch(labCommandsProvider(lab.id)).valueOrNull ??
        const <DeviceCommand>[];
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: lab.displayName,
          subtitle: 'Current device status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(
                    label:
                        lab.gatewayOnline ? 'Gateway: Online' : 'Gateway: Offline',
                    color: lab.gatewayOnline
                        ? AppColors.success
                        : AppColors.lightMuted,
                    icon: lab.gatewayOnline
                        ? Icons.wifi_tethering
                        : Icons.wifi_tethering_off,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 520;
                  final lights = _SimDeviceCard(
                    title: 'Lights',
                    icon: Icons.lightbulb_outline,
                    isOn: state.lightOn,
                    onTurnOn: () => _setDevice(
                      context,
                      ref,
                      device: SimDeviceKind.light,
                      turnOn: true,
                    ),
                    onTurnOff: () => _setDevice(
                      context,
                      ref,
                      device: SimDeviceKind.light,
                      turnOn: false,
                    ),
                  );
                  final ac = _SimDeviceCard(
                    title: 'Air conditioning',
                    icon: Icons.ac_unit,
                    isOn: state.acOn,
                    onTurnOn: () => _setDevice(
                      context,
                      ref,
                      device: SimDeviceKind.ac,
                      turnOn: true,
                    ),
                    onTurnOff: () => _setDevice(
                      context,
                      ref,
                      device: SimDeviceKind.ac,
                      turnOn: false,
                    ),
                  );
                  if (!wide) {
                    return Column(
                      children: [lights, const SizedBox(height: 12), ac],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: lights),
                      const SizedBox(width: 12),
                      Expanded(child: ac),
                    ],
                  );
                },
              ),
              if (!sim.loaded)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Loading saved device state…',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Recent device activity',
          subtitle: 'Actions performed from this device control panel.',
          child: history.isEmpty
              ? const EmptyState(
                  icon: Icons.history_toggle_off,
                  title: 'No activity yet',
                  message:
                      'Turn lights or air conditioning on/off to record an '
                      'action for this laboratory.',
                )
              : Column(
                  children: [
                    for (final entry in history.take(30))
                      _SimActivityTile(entry: entry),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Gateway command history',
          subtitle:
              'Queued and executed commands reported by a connected gateway.',
          trailing: TextButton.icon(
            onPressed: () => context.go('/activity'),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Activity'),
          ),
          child: realCommands.isEmpty
              ? const EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'No gateway commands',
                  message:
                      'Gateway commands appear here when a connected gateway '
                      'reports execution status.',
                )
              : Column(
                  children: [
                    for (final command in realCommands.take(20))
                      _RealCommandTile(command: command),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SimDeviceCard extends StatelessWidget {
  const _SimDeviceCard({
    required this.title,
    required this.icon,
    required this.isOn,
    required this.onTurnOn,
    required this.onTurnOff,
  });

  final String title;
  final IconData icon;
  final bool isOn;
  final VoidCallback onTurnOn;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLabel = isOn ? 'ON' : 'OFF';
    final statusColor = isOn ? AppColors.success : scheme.onSurfaceVariant;
    final statusIcon = isOn ? Icons.check_circle : Icons.cancel_outlined;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              StatusPill(
                label: statusLabel,
                color: statusColor,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 6),
              Text(
                'Status: $statusLabel',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: isOn
                    ? FilledButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.power, size: 18),
                        label: const Text('Turn on'),
                      )
                    : FilledButton.icon(
                        onPressed: onTurnOn,
                        icon: const Icon(Icons.power, size: 18),
                        label: const Text('Turn on'),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: isOn
                    ? OutlinedButton.icon(
                        onPressed: onTurnOff,
                        icon: const Icon(Icons.power_off, size: 18),
                        label: const Text('Turn off'),
                      )
                    : OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.power_off, size: 18),
                        label: const Text('Turn off'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SimActivityTile extends StatelessWidget {
  const _SimActivityTile({required this.entry});

  final SimulatedDeviceActivity entry;

  @override
  Widget build(BuildContext context) {
    final on = entry.turnedOn;
    final color = on ? AppColors.success : AppColors.lightMuted;
    final who = entry.actorName.isNotEmpty ? entry.actorName : 'A user';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        on ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
        color: color,
      ),
      title: Text(
        '$who ${entry.actionLabel} ${entry.labName} ${entry.device.label}',
      ),
      subtitle: Text(DateFormat.yMMMd().add_jm().format(entry.at)),
      trailing: StatusPill(
        label: on ? 'ON' : 'OFF',
        color: color,
        dense: true,
      ),
    );
  }
}

class _RealCommandTile extends StatelessWidget {
  const _RealCommandTile({required this.command});

  final DeviceCommand command;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (command.state) {
      CommandState.pending => (AppColors.warning, Icons.hourglass_top_rounded),
      CommandState.processing => (AppColors.info, Icons.sync),
      CommandState.succeeded => (AppColors.success, Icons.check_circle_outline),
      CommandState.failed => (AppColors.critical, Icons.error_outline),
      CommandState.offline => (AppColors.lightMuted, Icons.power_off),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        '${command.device == CommandDevice.light ? 'Lights' : 'Air conditioning'} '
        '${command.action.toUpperCase()}',
      ),
      subtitle: Text(
        [
          if (command.createdAt != null)
            DateFormat.yMMMd().add_jm().format(command.createdAt!),
          if (command.error != null && command.error!.isNotEmpty) command.error!,
        ].join(' · '),
      ),
      trailing: StatusPill(
        label: command.state.label,
        color: color,
        dense: true,
      ),
    );
  }
}
