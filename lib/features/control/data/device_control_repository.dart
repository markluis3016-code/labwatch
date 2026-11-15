import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/lab.dart';
import '../../activity/data/activity_repository.dart';
import '../../authentication/data/auth_repository.dart';
import '../../labs/data/lab_repository.dart';

enum CommandDevice { light, ac }

enum CommandState {
  pending,
  processing,
  succeeded,
  failed,
  offline;

  static CommandState parse(Object? value) {
    final name = value is String ? value.trim() : '';
    for (final state in CommandState.values) {
      if (state.name == name) return state;
    }
    return CommandState.pending;
  }

  String get label => switch (this) {
        CommandState.pending => 'Pending',
        CommandState.processing => 'Processing',
        CommandState.succeeded => 'Succeeded',
        CommandState.failed => 'Failed',
        CommandState.offline => 'Offline',
      };
}

class DeviceCommand {
  const DeviceCommand({
    required this.id,
    required this.device,
    required this.actionIsOn,
    required this.state,
    required this.requestedBy,
    this.createdAt,
    this.error,
  });

  final String id;
  final CommandDevice device;
  final bool actionIsOn;
  final CommandState state;
  final String requestedBy;
  final DateTime? createdAt;
  final String? error;

  String get action => actionIsOn ? 'on' : 'off';

  factory DeviceCommand.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return DeviceCommand(
      id: doc.id,
      device: data['device'] == 'ac' ? CommandDevice.ac : CommandDevice.light,
      actionIsOn: data['action'] == 'on',
      state: CommandState.parse(data['status']),
      requestedBy:
          data['requestedBy'] is String ? data['requestedBy'] as String : '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      error: data['error'] is String ? data['error'] as String : null,
    );
  }
}

/// Queues device commands in `labs/{labId}/commands`. The app never marks a
/// command as successful: only the gateway/backend may do that, so the UI can
/// honestly distinguish queued from executed.
///
/// FUTURE IoT INTEGRATION: real hardware control should flow through this
/// repository/backend (gateway-verified command execution and telemetry). Keep
/// any UI-only simulation logic separate and never write simulated state as real
/// commands or telemetry.
class DeviceControlRepository {
  DeviceControlRepository(this._db, this._activity);

  final FirebaseFirestore _db;
  final ActivityRepository _activity;

  Stream<List<DeviceCommand>> watchCommands(String labId, {int limit = 50}) =>
      _db
          .collection('labs')
          .doc(labId)
          .collection('commands')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map(DeviceCommand.fromDoc)
              .toList(growable: false));

  Future<void> queue({
    required Lab lab,
    required CommandDevice device,
    required bool turnOn,
    required AppUser actor,
  }) async {
    if (!lab.gatewayOnline) {
      throw const AppFailure(
        'No IoT gateway is connected to this laboratory, so commands cannot be '
        'executed. Ask an administrator to configure the gateway.',
      );
    }
    final allowed =
        actor.isAdmin || actor.assignedLabIds.contains(lab.id);
    if (!allowed) {
      throw const AppFailure(
        'You are not assigned to this laboratory.',
      );
    }

    try {
      await _db
          .collection('labs')
          .doc(lab.id)
          .collection('commands')
          .add(<String, dynamic>{
        'device': device.name,
        'action': turnOn ? 'on' : 'off',
        'requestedBy': actor.uid,
        'status': CommandState.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _activity.log(
        'command_queued',
        labId: lab.id,
        details: '${device == CommandDevice.light ? 'Lights' : 'Air conditioning'} '
            '${turnOn ? 'ON' : 'OFF'} requested',
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not queue the device command.',
      );
    }
  }
}

final deviceControlRepositoryProvider = Provider<DeviceControlRepository>(
  (ref) => DeviceControlRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
  ),
);

final labCommandsProvider =
    StreamProvider.family<List<DeviceCommand>, String>((ref, labId) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || !user.mayControlDevices) {
    return Stream.value(const <DeviceCommand>[]);
  }
  return ref.watch(deviceControlRepositoryProvider).watchCommands(labId);
});

/// True when at least one controllable lab reports a connected gateway.
final gatewayAvailableProvider = Provider<bool>((ref) {
  final labs = ref.watch(controllableLabsProvider);
  return labs.any((lab) => lab.gatewayOnline);
});
