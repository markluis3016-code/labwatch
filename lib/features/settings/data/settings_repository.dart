import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_settings.dart';
import '../../authentication/data/auth_repository.dart';
import '../../activity/data/activity_repository.dart';

class SettingsRepository {
  SettingsRepository(this._db, this._activity);

  final FirebaseFirestore _db;
  final ActivityRepository _activity;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.doc('config/app');

  Stream<AppSettings> watch() => _ref.snapshots().map(
        (doc) => doc.exists ? AppSettings.fromDoc(doc) : AppSettings.defaults,
      );

  Future<void> save(AppSettings settings) async {
    try {
      await _ref.set(settings.toMap(), SetOptions(merge: true));
      await _activity.log(
        'settings_updated',
        details: 'Energy inactivity threshold '
            '${settings.energyInactivityMinutes} min',
      );
    } catch (error) {
      throw mapFirestoreError(error, fallback: 'Could not save the settings.');
    }
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
  ),
);

final appSettingsProvider = StreamProvider<AppSettings>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(AppSettings.defaults);
  return ref.watch(settingsRepositoryProvider).watch();
});
