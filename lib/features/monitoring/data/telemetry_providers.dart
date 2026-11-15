import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/telemetry.dart';
import 'telemetry_source.dart';

/// Shared Firestore handle for monitoring and the energy watcher.
final monitoringDbProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

/// Demo mode toggle. Defaults to OFF so the app never shows sample data
/// unless someone explicitly turns it on (and it is then labelled SAMPLE).
final demoModeProvider = StateProvider<bool>((_) => false);

final telemetrySourceProvider = Provider<TelemetrySource>((ref) {
  return ref.watch(demoModeProvider)
      ? SampleTelemetrySource()
      : FirestoreTelemetrySource(ref.watch(monitoringDbProvider));
});

final labTelemetryProvider =
    StreamProvider.family<LabTelemetry, String>((ref, labId) {
  return ref.watch(telemetrySourceProvider).watch(labId);
});
