import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/lab_alert.dart';
import '../../activity/data/activity_repository.dart';


class AlertRepository {
  AlertRepository(this._db, this._activity);

  final FirebaseFirestore _db;
  final ActivityRepository _activity;

  CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection('alerts');

  Stream<List<LabAlert>> watch({int limit = 150}) => _alerts
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(LabAlert.fromDoc).toList(growable: false));

  Stream<LabAlert?> watchOne(String id) => _db
      .doc('alerts/$id')
      .snapshots()
      .map((doc) => doc.exists ? LabAlert.fromDoc(doc) : null);

  /// Creates an alert. When [sourceKey] is provided the document id is
  /// deterministic, so repeated evaluations (energy watch) cannot duplicate
  /// the same alert.
  Future<String> raise({
    required AlertCategory category,
    required AlertSeverity severity,
    required String title,
    required String message,
    required String createdBy,
    String labId = '',
    String sourceKey = '',
  }) async {
    try {
      final docId = sourceKey.trim().isEmpty
          ? null
          : '${category.name}_${_sanitize(labId)}_${_sanitize(sourceKey)}';
      final ref =
          docId == null ? _alerts.doc() : _alerts.doc(docId);

      if (docId != null) {
        final exists = await _db.runTransaction<bool>((transaction) async {
          final snapshot = await transaction.get(ref);
          if (snapshot.exists) return true;
          transaction.set(ref, <String, dynamic>{
            'category': category.name,
            'severity': severity.name,
            'title': _clamp(title, 120),
            'message': _clamp(message, 500),
            'labId': labId,
            'status': AlertStatus.open.name,
            'sourceKey': _clamp(sourceKey, 120),
            'createdBy': createdBy,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return false;
        });
        if (exists) return ref.id;
      } else {
        await ref.set(<String, dynamic>{
          'category': category.name,
          'severity': severity.name,
          'title': _clamp(title, 120),
          'message': _clamp(message, 500),
          'labId': labId,
          'status': AlertStatus.open.name,
          'sourceKey': '',
          'createdBy': createdBy,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _activity.log(
        'alert_created',
        labId: labId.isEmpty ? null : labId,
        details: title,
      );
      return ref.id;
    } catch (error) {
      throw mapFirestoreError(error, fallback: 'Could not create the alert.');
    }
  }

  Future<void> acknowledge(LabAlert alert, AppUser actor) async {
    if (!alert.status.isOpen) return;
    try {
      await _db.doc('alerts/${alert.id}').update(<String, dynamic>{
        'status': AlertStatus.acknowledged.name,
        'acknowledgedBy': actor.uid,
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _activity.log(
        'alert_acknowledged',
        labId: alert.labId.isEmpty ? null : alert.labId,
        details: alert.title,
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not acknowledge the alert.',
      );
    }
  }

  Future<void> resolve(LabAlert alert, AppUser actor) async {
    if (alert.status.isResolved) return;
    try {
      await _db.doc('alerts/${alert.id}').update(<String, dynamic>{
        'status': AlertStatus.resolved.name,
        'resolvedBy': actor.uid,
        'resolvedAt': FieldValue.serverTimestamp(),
        if (alert.acknowledgedBy == null) ...{
          'acknowledgedBy': actor.uid,
          'acknowledgedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _activity.log(
        'alert_resolved',
        labId: alert.labId.isEmpty ? null : alert.labId,
        details: alert.title,
      );
    } catch (error) {
      throw mapFirestoreError(error, fallback: 'Could not resolve the alert.');
    }
  }

  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _clamp(String value, int max) {
    final text = value.trim();
    return text.length <= max ? text : text.substring(0, max);
  }
}

final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => AlertRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
  ),
);

final alertsProvider = StreamProvider<List<LabAlert>>(
  (ref) => ref.watch(alertRepositoryProvider).watch(),
);

final alertProvider = StreamProvider.family<LabAlert?, String>(
  (ref, id) => ref.watch(alertRepositoryProvider).watchOne(id),
);

final openAlertsProvider = Provider<List<LabAlert>>((ref) {
  final alerts = ref.watch(alertsProvider).valueOrNull ?? const <LabAlert>[];
  return alerts.where((alert) => !alert.status.isResolved).toList(
        growable: false,
      );
});

final activeAlertCountProvider = Provider<int>(
  (ref) => ref.watch(openAlertsProvider).length,
);

final energyAlertsProvider = Provider<List<LabAlert>>((ref) {
  final alerts = ref.watch(openAlertsProvider);
  return alerts
      .where((alert) => alert.category == AlertCategory.energy)
      .toList(growable: false);
});

String alertLabLabel(LabAlert alert, Map<String, Lab> labs) {
  if (alert.labId.isEmpty) return '';
  return labs[alert.labId]?.displayName ?? alert.labId;
}
