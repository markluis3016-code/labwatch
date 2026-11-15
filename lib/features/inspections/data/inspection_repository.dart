import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/inspection.dart';
import '../../../shared/models/lab_alert.dart';
import '../../activity/data/activity_repository.dart';
import '../../alerts/data/alert_repository.dart';
import '../../authentication/data/auth_repository.dart';
import '../../equipment/data/equipment_repository.dart';

class InspectionRepository {
  InspectionRepository(
    this._db,
    this._activity,
    this._alerts,
    this._equipment,
  );

  final FirebaseFirestore _db;
  final ActivityRepository _activity;
  final AlertRepository _alerts;
  final EquipmentRepository _equipment;

  CollectionReference<Map<String, dynamic>> get _inspections =>
      _db.collection('inspections');

  Stream<List<Inspection>> watchForLab(String labId, {int limit = 80}) =>
      _inspections
          .where('labId', isEqualTo: labId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) =>
              snapshot.docs.map(Inspection.fromDoc).toList(growable: false));

  Stream<List<Inspection>> watchMine(String uid, {int limit = 80}) =>
      _inspections
          .where('inspectorId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) =>
              snapshot.docs.map(Inspection.fromDoc).toList(growable: false));

  Stream<List<Inspection>> watchRecent({int limit = 120}) => _inspections
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(Inspection.fromDoc).toList(growable: false));

  /// Saves the checklist, raises one alert per problematic item and records
  /// the inspection in the activity trail. All writes are client-visible,
  /// rule-validated operations (no fabricated results).
  Future<String> create(
    Inspection inspection, {
    required AppUser actor,
    Inspection? before,
  }) async {
    final notes = inspection.notes.trim();
    if (notes.length > 500) {
      throw const AppFailure('Keep inspection notes under 500 characters.');
    }
    if (inspection.items.isEmpty) {
      throw const AppFailure(
        'Add at least one equipment item before saving the inspection.',
      );
    }

    final regressed = inspection.type == InspectionType.after && before != null
        ? regressions(before: before, after: inspection)
        : const <InspectionItem>[];
    final regressedIds = regressed.map((item) => item.equipmentId).toSet();

    try {
      final ref = _inspections.doc();
      await ref.set(inspection.toMap());

      final problemItems = inspection.items.where(
        (item) =>
            item.hasProblem ||
            item.quantityFound < item.quantityExpected ||
            regressedIds.contains(item.equipmentId),
      );

      var index = 0;
      for (final item in problemItems) {
        final isRegression = regressedIds.contains(item.equipmentId);
        await _alerts.raise(
          category: AlertCategory.equipment,
          severity: item.condition == EquipmentCondition.missing ||
                  item.condition == EquipmentCondition.damaged
              ? AlertSeverity.critical
              : AlertSeverity.warning,
          title: isRegression
              ? 'Equipment changed during use: ${item.name}'
              : 'Equipment issue found: ${item.name}',
          message: [
            '${inspection.type.label} inspection in ${inspection.labName}.',
            'Condition: ${item.condition.label}.',
            'Expected ${item.quantityExpected}, found ${item.quantityFound}.',
            if (item.notes.trim().isNotEmpty) item.notes.trim(),
            if (inspection.notes.trim().isNotEmpty) inspection.notes.trim(),
          ].join(' '),
          labId: inspection.labId,
          sourceKey: '${ref.id}_$index',
          createdBy: actor.uid,
        );
        index++;
      }

      final inspectedAt = DateTime.now();
      for (final item in inspection.items) {
        await _equipment.markInspected(
          item.equipmentId,
          at: inspectedAt,
          actor: actor,
        );
      }

      await _activity.log(
        'inspection_completed',
        labId: inspection.labId,
        details: '${inspection.type.label}: ${inspection.labName} '
            '(${inspection.items.length} items, '
            '${inspection.problemCount} issue(s))',
      );
      return ref.id;
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not save the inspection.',
      );
    }
  }
}

final inspectionRepositoryProvider = Provider<InspectionRepository>(
  (ref) => InspectionRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
    ref.watch(alertRepositoryProvider),
    ref.watch(equipmentRepositoryProvider),
  ),
);

final labInspectionsProvider =
    StreamProvider.family<List<Inspection>, String>((ref, labId) {
  return ref.watch(inspectionRepositoryProvider).watchForLab(labId);
});

final myInspectionsProvider = StreamProvider<List<Inspection>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Inspection>[]);
  return ref.watch(inspectionRepositoryProvider).watchMine(user.uid);
});

final recentInspectionsProvider = StreamProvider<List<Inspection>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Inspection>[]);
  return ref.watch(inspectionRepositoryProvider).watchRecent();
});

/// Latest before/after checklist per lab, used to pre-fill the next one.
final latestInspectionProvider =
    FutureProvider.family<Inspection?, ({String labId, InspectionType type})>(
        (ref, key) async {
  final snapshots = await FirebaseFirestore.instance
      .collection('inspections')
      .where('labId', isEqualTo: key.labId)
      .where('type', isEqualTo: key.type.name)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();
  if (snapshots.docs.isEmpty) return null;
  return Inspection.fromDoc(snapshots.docs.first);
});
