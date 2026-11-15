import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/lab_alert.dart';
import '../../activity/data/activity_repository.dart';
import '../../alerts/data/alert_repository.dart';

class EquipmentRepository {
  EquipmentRepository(this._db, this._activity, this._alerts);

  final FirebaseFirestore _db;
  final ActivityRepository _activity;
  final AlertRepository _alerts;

  CollectionReference<Map<String, dynamic>> get _equipment =>
      _db.collection('equipment');

  Stream<List<Equipment>> watchAll({int limit = 300}) {
    return _equipment.orderBy('name').limit(limit).snapshots().map(
          (snapshot) => snapshot.docs
              .map(Equipment.fromDoc)
              .toList(growable: false),
        );
  }

  Stream<List<Equipment>> watchForLab(String labId) {
    return _equipment
        .where('labId', isEqualTo: labId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(Equipment.fromDoc)
            .toList(growable: false));
  }

  Stream<Equipment?> watchOne(String id) => _db
      .doc('equipment/$id')
      .snapshots()
      .map((doc) => doc.exists ? Equipment.fromDoc(doc) : null);

  Stream<List<Equipment>> watchInspectedBy(String uid, {int limit = 100}) {
    return _equipment
        .where('lastInspectedBy', isEqualTo: uid)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(Equipment.fromDoc)
            .toList(growable: false));
  }

  Future<String> save(
    Equipment equipment, {
    required bool isNew,
    required AppUser actor,
  }) async {
    try {
      final ref = isNew ? _equipment.doc() : _equipment.doc(equipment.id);
      final data = equipment.toMap();
      if (isNew) data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedBy'] = actor.uid;
      await ref.set(data, SetOptions(merge: true));
      await _activity.log(
        isNew ? 'equipment_created' : 'equipment_updated',
        labId: equipment.labId,
        details: equipment.name,
      );
      return ref.id;
    } catch (error) {
      throw mapFirestoreError(error, fallback: 'Could not save the equipment.');
    }
  }

  Future<void> setCondition(
    Equipment equipment,
    EquipmentCondition condition, {
    String? note,
    required AppUser actor,
  }) async {
    try {
      await _db.doc('equipment/${equipment.id}').update(<String, dynamic>{
        'condition': condition.name,
        'lastInspectedAt': FieldValue.serverTimestamp(),
        'lastInspectedBy': actor.uid,
        if (note != null && note.trim().isNotEmpty) 'notes': note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _activity.log(
        'equipment_updated',
        labId: equipment.labId,
        details: '${equipment.name}: ${condition.label}',
      );
      if (condition.isIssue) {
        await _alerts.raise(
          category: AlertCategory.equipment,
          severity: condition == EquipmentCondition.missing
              ? AlertSeverity.critical
              : AlertSeverity.warning,
          title: '${equipment.name} marked ${condition.label.toLowerCase()}',
          message: note?.trim().isNotEmpty == true
              ? note!.trim()
              : '${equipment.name} was marked ${condition.label.toLowerCase()} '
                  'during an equipment check.',
          labId: equipment.labId,
          sourceKey: 'condition_${condition.name}_'
              '${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
          createdBy: actor.uid,
        );
      }
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not update the equipment condition.',
      );
    }
  }

  /// Instructors cannot edit inventory, but they can report a problem. This
  /// creates an alert and an activity entry (rules allow both).
  Future<void> reportProblem(
    Equipment equipment, {
    required String description,
    required AppUser reporter,
  }) async {
    final text = description.trim();
    if (text.length < 10) {
      throw const AppFailure(
        'Describe the problem in at least 10 characters.',
      );
    }
    try {
      await _alerts.raise(
        category: AlertCategory.equipment,
        severity: AlertSeverity.warning,
        title: 'Equipment problem: ${equipment.name}',
        message: text,
        labId: equipment.labId,
        sourceKey: reporter.uid,
        createdBy: reporter.uid,
      );
      await _activity.log(
        'equipment_reported',
        labId: equipment.labId,
        details: '${equipment.name}: $text',
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not submit the equipment report.',
      );
    }
  }

  Future<void> markInspected(
    String equipmentId, {
    required DateTime at,
    required AppUser actor,
  }) async {
    try {
      await _db.doc('equipment/$equipmentId').update(<String, dynamic>{
        'lastInspectedAt': Timestamp.fromDate(at),
        'lastInspectedBy': actor.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Inspection records remain the source of truth if this best-effort
      // timestamp update is blocked.
    }
  }

  Future<void> delete(Equipment equipment) async {
    try {
      await _db.doc('equipment/${equipment.id}').delete();
      await _activity.log(
        'equipment_deleted',
        labId: equipment.labId,
        details: equipment.name,
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not delete the equipment.',
      );
    }
  }
}

final equipmentRepositoryProvider = Provider<EquipmentRepository>(
  (ref) => EquipmentRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
    ref.watch(alertRepositoryProvider),
  ),
);

final equipmentProvider = StreamProvider<List<Equipment>>(
  (ref) => ref.watch(equipmentRepositoryProvider).watchAll(),
);

final labEquipmentProvider = StreamProvider.family<List<Equipment>, String>(
  (ref, labId) => ref.watch(equipmentRepositoryProvider).watchForLab(labId),
);

final equipmentByIdProvider = Provider<Map<String, Equipment>>((ref) {
  final items = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
  return {for (final item in items) item.id: item};
});

final equipmentIssuesProvider = Provider<List<Equipment>>((ref) {
  final items = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
  return items
      .where((item) => item.condition.isIssue)
      .toList(growable: false);
});

final equipmentNeedingRepairProvider = Provider<List<Equipment>>((ref) {
  final items = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
  return items
      .where(
        (item) =>
            item.condition == EquipmentCondition.needsRepair ||
            item.condition.isIssue,
      )
      .toList(growable: false);
});

String equipmentLabLabel(Equipment equipment, Map<String, Lab> labs) {
  final lab = labs[equipment.labId];
  return lab?.displayName ?? equipment.labId;
}
