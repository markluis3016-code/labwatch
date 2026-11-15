import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only simulation for device control when no physical IoT gateway is
/// available.
///
/// IMPORTANT: This is demonstration/simulation state only.
/// - Do NOT write these values to Firestore telemetry or device command
///   collections.
/// - Do NOT treat simulated state as real gateway/device execution.
/// - Keep this separate from [DeviceControlRepository] so a real IoT gateway can
///   be integrated later by routing real commands through the repository and
///   reflecting confirmed gateway telemetry/status in the UI.
const _kSimStatesKey = 'labwatch_sim_device_states_v1';
const _kSimHistoryKey = 'labwatch_sim_device_history_v1';

enum SimDeviceKind { light, ac }

extension SimDeviceKindX on SimDeviceKind {
  String get label => switch (this) {
        SimDeviceKind.light => 'Lights',
        SimDeviceKind.ac => 'Air conditioning',
      };

  static SimDeviceKind parse(Object? value) => value == 'ac'
      ? SimDeviceKind.ac
      : SimDeviceKind.light;
}

class LabSimDeviceState {
  const LabSimDeviceState({this.lightOn = false, this.acOn = false});

  final bool lightOn;
  final bool acOn;

  bool isOn(SimDeviceKind device) =>
      device == SimDeviceKind.light ? lightOn : acOn;

  LabSimDeviceState copyWith({bool? lightOn, bool? acOn}) => LabSimDeviceState(
        lightOn: lightOn ?? this.lightOn,
        acOn: acOn ?? this.acOn,
      );

  Map<String, dynamic> toJson() => {'lightOn': lightOn, 'acOn': acOn};

  factory LabSimDeviceState.fromJson(Object? value) {
    if (value is! Map) return const LabSimDeviceState();
    final map = Map<String, dynamic>.from(value);
    return LabSimDeviceState(
      lightOn: map['lightOn'] == true,
      acOn: map['acOn'] == true,
    );
  }
}

class SimulatedDeviceActivity {
  const SimulatedDeviceActivity({
    required this.id,
    required this.labId,
    required this.labName,
    required this.device,
    required this.turnedOn,
    required this.at,
    required this.actorUid,
    required this.actorName,
  });

  final String id;
  final String labId;
  final String labName;
  final SimDeviceKind device;
  final bool turnedOn;
  final DateTime at;
  final String actorUid;
  final String actorName;

  String get actionLabel => turnedOn ? 'turned ON' : 'turned OFF';

  Map<String, dynamic> toJson() => {
        'id': id,
        'labId': labId,
        'labName': labName,
        'device': device.name,
        'turnedOn': turnedOn,
        'at': at.toIso8601String(),
        'actorUid': actorUid,
        'actorName': actorName,
      };

  factory SimulatedDeviceActivity.fromJson(Object? value) {
    final map = value is Map ? Map<String, dynamic>.from(value) : const {};
    DateTime at;
    try {
      at = DateTime.parse(map['at'] as String? ?? '');
    } catch (_) {
      at = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return SimulatedDeviceActivity(
      id: (map['id'] as String?) ?? '',
      labId: (map['labId'] as String?) ?? '',
      labName: (map['labName'] as String?) ?? '',
      device: SimDeviceKindX.parse(map['device']),
      turnedOn: map['turnedOn'] == true,
      at: at,
      actorUid: (map['actorUid'] as String?) ?? '',
      actorName: (map['actorName'] as String?) ?? '',
    );
  }
}

class SimulationControlState {
  const SimulationControlState({
    this.statesByLab = const <String, LabSimDeviceState>{},
    this.history = const <SimulatedDeviceActivity>[],
    this.loaded = false,
  });

  final Map<String, LabSimDeviceState> statesByLab;
  final List<SimulatedDeviceActivity> history;
  final bool loaded;

  LabSimDeviceState stateFor(String labId) =>
      statesByLab[labId] ?? const LabSimDeviceState();

  List<SimulatedDeviceActivity> historyFor(String labId) => history
      .where((entry) => entry.labId == labId)
      .toList(growable: false);

  SimulationControlState copyWith({
    Map<String, LabSimDeviceState>? statesByLab,
    List<SimulatedDeviceActivity>? history,
    bool? loaded,
  }) =>
      SimulationControlState(
        statesByLab: statesByLab ?? this.statesByLab,
        history: history ?? this.history,
        loaded: loaded ?? this.loaded,
      );
}

class DeviceSimulationController
    extends StateNotifier<SimulationControlState> {
  DeviceSimulationController() : super(const SimulationControlState()) {
    _load();
  }

  SharedPreferences? _prefs;

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final statesRaw = _prefs!.getString(_kSimStatesKey);
      final historyRaw = _prefs!.getString(_kSimHistoryKey);

      final states = <String, LabSimDeviceState>{};
      if (statesRaw != null && statesRaw.isNotEmpty) {
        final decoded = jsonDecode(statesRaw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            states[entry.key.toString()] =
                LabSimDeviceState.fromJson(entry.value);
          }
        }
      }

      final history = <SimulatedDeviceActivity>[];
      if (historyRaw != null && historyRaw.isNotEmpty) {
        final decoded = jsonDecode(historyRaw);
        if (decoded is List) {
          for (final item in decoded) {
            history.add(SimulatedDeviceActivity.fromJson(item));
          }
        }
      }
      history.sort((a, b) => b.at.compareTo(a.at));

      state = SimulationControlState(
        statesByLab: states,
        history: history,
        loaded: true,
      );
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final statesMap = <String, dynamic>{
        for (final entry in state.statesByLab.entries)
          entry.key: entry.value.toJson(),
      };
      await _prefs!.setString(_kSimStatesKey, jsonEncode(statesMap));
      await _prefs!.setString(
        _kSimHistoryKey,
        jsonEncode(state.history.map((e) => e.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Keep in-memory simulation state even if local persistence fails.
    }
  }

  /// Applies a simulated control action locally (no Firestore/gateway writes).
  /// Returns false when the device is already in the requested state.
  Future<bool> setDevice({
    required String labId,
    required String labName,
    required SimDeviceKind device,
    required bool turnOn,
    required String actorUid,
    required String actorName,
  }) async {
    final current = state.stateFor(labId);
    if (current.isOn(device) == turnOn) return false;

    final updated = device == SimDeviceKind.light
        ? current.copyWith(lightOn: turnOn)
        : current.copyWith(acOn: turnOn);

    final entry = SimulatedDeviceActivity(
      id: '${DateTime.now().microsecondsSinceEpoch}_${labId}_${device.name}',
      labId: labId,
      labName: labName,
      device: device,
      turnedOn: turnOn,
      at: DateTime.now(),
      actorUid: actorUid,
      actorName: actorName,
    );

    final nextStates = Map<String, LabSimDeviceState>.from(state.statesByLab)
      ..[labId] = updated;
    final nextHistory = <SimulatedDeviceActivity>[entry, ...state.history];
    // Keep history bounded locally.
    final bounded = nextHistory.length > 200
        ? nextHistory.sublist(0, 200)
        : nextHistory;

    state = state.copyWith(statesByLab: nextStates, history: bounded);
    await _persist();
    return true;
  }
}

final deviceSimulationProvider =
    StateNotifierProvider<DeviceSimulationController, SimulationControlState>(
  (ref) => DeviceSimulationController(),
);

/// Real IoT integration point (future): when a physical gateway is connected and
/// confirmed, prefer gateway-reported telemetry/status and real command
/// execution via [DeviceControlRepository]/backend over local simulation.
final isSimulationModeProvider = Provider<bool>((ref) => true);
