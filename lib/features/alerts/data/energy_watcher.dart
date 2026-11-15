import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_settings.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/lab_alert.dart';
import '../../../shared/models/reservation.dart';
import '../../authentication/data/auth_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../../monitoring/data/telemetry_providers.dart';
import '../../monitoring/data/telemetry_source.dart';
import '../../monitoring/domain/telemetry.dart';
import '../../scheduling/data/reservation_repository.dart';
import '../../settings/data/settings_repository.dart';
import 'alert_repository.dart';

/// Evaluates the energy-saving rule for laboratories with LIVE telemetry:
/// empty room + lights or AC on + no class in progress, sustained for the
/// configured duration. It never uses SAMPLE data and never fabricates values.
///
/// This client-side monitor only runs while an administrator or staff member
/// has LabWatch open. A scheduled Cloud Function is the recommended production
/// implementation; see docs/ARCHITECTURE.md.
class EnergyWatcher {
  EnergyWatcher(this._reader, this._alerts);

  final TelemetryReader _reader;
  final AlertRepository _alerts;
  final Map<String, DateTime> _emptySince = {};
  final Set<String> _raised = {};

  Future<void> evaluate({
    required List<Lab> labs,
    required List<Reservation> reservations,
    required AppSettings settings,
    required String actorId,
    required DateTime now,
  }) async {
    if (!settings.energyAlertsEnabled) return;
    final threshold = Duration(minutes: settings.energyInactivityMinutes);

    for (final lab in labs) {
      final reading = await _reader.latest(lab.id);
      final classInProgress = reservations.any(
        (reservation) =>
            reservation.labId == lab.id &&
            reservation.status.blocksSlot &&
            !reservation.startAt.isAfter(now) &&
            reservation.endAt.isAfter(now),
      );
      final devicesOn = reading.light == PowerState.on ||
          reading.ac == PowerState.on;
      final idle = reading.origin == DataOrigin.live &&
          reading.occupied == false &&
          devicesOn &&
          !classInProgress;

      if (!idle) {
        _emptySince.remove(lab.id);
        _raised.remove(lab.id);
        continue;
      }

      final since = _emptySince.putIfAbsent(lab.id, () => now);
      if (now.difference(since) < threshold) continue;
      if (!_raised.add(lab.id)) continue;

      final devices = [
        if (reading.light == PowerState.on) 'lights',
        if (reading.ac == PowerState.on) 'air conditioning',
      ].join(' and ');

      await _alerts.raise(
        category: AlertCategory.energy,
        severity: AlertSeverity.warning,
        title: '$devices left on in ${lab.displayName}',
        message:
            '${lab.displayName} has been empty for at least '
            '${settings.energyInactivityMinutes} minutes with $devices on, '
            'and no reservation is active. Check the room and switch devices '
            'off if safe.',
        labId: lab.id,
        sourceKey: since.toUtc().toIso8601String(),
        createdBy: actorId,
      );
    }
  }
}

final energyWatcherProvider = Provider<EnergyWatcher>(
  (ref) => EnergyWatcher(
    TelemetryReader(ref.watch(monitoringDbProvider)),
    ref.watch(alertRepositoryProvider),
  ),
);

/// Runs the energy rule while an admin/staff account has the app open and
/// rebuilds nothing; it only writes an alert when the condition is confirmed.
class EnergyWatchRunner extends ConsumerStatefulWidget {
  const EnergyWatchRunner({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<EnergyWatchRunner> createState() => _EnergyWatchRunnerState();
}

class _EnergyWatchRunnerState extends ConsumerState<EnergyWatchRunner> {
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_running) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || !user.isActive || (!user.isAdmin && !user.isStaff)) {
      return;
    }
    final labs = ref.read(visibleLabsProvider);
    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (labs.isEmpty || settings == null || !settings.energyAlertsEnabled) {
      return;
    }
    _running = true;
    try {
      await ref.read(energyWatcherProvider).evaluate(
            labs: labs,
            reservations: ref.read(reservationsProvider).valueOrNull ??
                const <Reservation>[],
            settings: settings,
            actorId: user.uid,
            now: DateTime.now(),
          );
    } catch (_) {
      // Detection is best-effort; a Firestore rule or network failure must
      // never interrupt the UI.
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
