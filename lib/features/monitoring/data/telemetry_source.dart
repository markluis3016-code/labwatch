import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/telemetry.dart';

/// Abstraction over where sensor data comes from. Swap implementations
/// (Firestore written by a gateway, MQTT, REST) without touching the UI.
abstract class TelemetrySource {
  Stream<LabTelemetry> watch(String labId);
}

/// DEMO ONLY. Emits randomised readings, always tagged [DataOrigin.sample].
class SampleTelemetrySource implements TelemetrySource {
  final _rng = Random();

  @override
  Stream<LabTelemetry> watch(String labId) async* {
    var occupied = true;
    var light = PowerState.on;
    var ac = PowerState.on;
    while (true) {
      if (_rng.nextInt(6) == 0) occupied = !occupied;
      if (!occupied && _rng.nextBool()) {
        // Demonstrates the "left ON in an empty room" condition.
        light = PowerState.on;
        ac = PowerState.on;
      }
      yield LabTelemetry(
        labId: labId,
        origin: DataOrigin.sample,
        occupied: occupied,
        light: light,
        ac: ac,
        sensorTimestamp: DateTime.now(),
        receivedAt: DateTime.now(),
      );
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
}

/// Reads `labs/{labId}/telemetry/latest`, written by your IoT gateway or a
/// Cloud Function with admin credentials. Clients cannot write this document
/// (see firestore.rules), so the app never fabricates "live" readings.
///
/// Re-validates every second so a silent sensor flips to OFFLINE even when no
/// new Firestore event arrives.
class FirestoreTelemetrySource implements TelemetrySource {
  FirestoreTelemetrySource(this._db, {TelemetryValidator? validator})
      : _validator = validator ?? TelemetryValidator();

  final FirebaseFirestore _db;
  final TelemetryValidator _validator;

  @override
  Stream<LabTelemetry> watch(String labId) {
    final controller = StreamController<LabTelemetry>();
    LabTelemetry latest = LabTelemetry.offline(labId);
    StreamSubscription? sub;
    Timer? ticker;

    void emit() {
      if (!controller.isClosed) {
        controller.add(_validator.validate(latest, DateTime.now()));
      }
    }

    controller.onListen = () {
      sub = _db.doc('labs/$labId/telemetry/latest').snapshots().listen(
        (snap) {
          final d = snap.data();
          latest = d == null ? LabTelemetry.offline(labId) : _parse(labId, d);
          emit();
        },
        onError: (_) {
          latest = LabTelemetry.offline(labId); // never expose raw errors
          emit();
        },
      );
      ticker = Timer.periodic(const Duration(seconds: 1), (_) => emit());
    };
    controller.onCancel = () async {
      ticker?.cancel();
      await sub?.cancel();
    };
    return controller.stream;
  }

  LabTelemetry _parse(String labId, Map<String, dynamic> d) =>
      parseTelemetry(labId, d);
}

/// Parses a raw `telemetry/latest` document. Shared with the energy watch so
/// both paths classify readings identically.
LabTelemetry parseTelemetry(String labId, Map<String, dynamic> d) {
  PowerState p(dynamic v) => switch (v) {
        'on' => PowerState.on,
        'off' => PowerState.off,
        _ => PowerState.unknown,
      };
  return LabTelemetry(
    labId: labId,
    origin: DataOrigin.live,
    occupied: d['occupied'] is bool ? d['occupied'] as bool : null,
    light: p(d['light']),
    ac: p(d['ac']),
    sensorTimestamp: (d['sensorTimestamp'] as Timestamp?)?.toDate(),
    receivedAt: (d['receivedAt'] as Timestamp?)?.toDate(),
  );
}

/// One-shot read of the latest reading, used by the energy monitor. The
/// reading is validated so a stale document becomes OFFLINE, not LIVE.
class TelemetryReader {
  TelemetryReader(this._db, {TelemetryValidator? validator})
      : _validator = validator ?? TelemetryValidator();

  final FirebaseFirestore _db;
  final TelemetryValidator _validator;

  Future<LabTelemetry> latest(String labId) async {
    try {
      final snapshot =
          await _db.doc('labs/$labId/telemetry/latest').get();
      final data = snapshot.data();
      if (data == null) return LabTelemetry.offline(labId);
      return _validator.validate(parseTelemetry(labId, data), DateTime.now());
    } catch (_) {
      return LabTelemetry.offline(labId);
    }
  }
}
