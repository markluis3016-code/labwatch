import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/lab.dart';
import '../../activity/data/activity_repository.dart';
import '../../authentication/data/auth_repository.dart';

class LabRepository {
  LabRepository(this._db, this._activity);

  final FirebaseFirestore _db;
  final ActivityRepository _activity;

  CollectionReference<Map<String, dynamic>> get _labs =>
      _db.collection('labs');

  Stream<List<Lab>> watchLabs({int limit = 100}) {
    return _labs.limit(limit).snapshots().map((snapshot) {
      final labs = snapshot.docs.map(Lab.fromDoc).toList(growable: false);
      return [...labs]..sort((a, b) {
          final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });
    });
  }

  Stream<Lab?> watchLab(String labId) => _db
      .doc('labs/$labId')
      .snapshots()
      .map((doc) => doc.exists ? Lab.fromDoc(doc) : null);

  Future<Lab> getLab(String labId) async {
    try {
      final doc = await _db.doc('labs/$labId').get();
      if (!doc.exists) {
        throw StateError('Laboratory not found.');
      }
      return Lab.fromDoc(doc);
    } catch (error) {
      throw mapFirestoreError(error, fallback: 'Could not load the laboratory.');
    }
  }

  /// Admins create and edit lab metadata. Rules enforce the same limit.
  Future<String> saveLab(Lab lab, {required bool isNew}) async {
    try {
      final ref = isNew ? _labs.doc() : _labs.doc(lab.id);
      final data = lab.toMap();
      if (isNew) data['createdAt'] = FieldValue.serverTimestamp();
      await ref.set(data, SetOptions(merge: true));
      await _activity.log(
        isNew ? 'lab_created' : 'lab_updated',
        labId: ref.id,
        details: lab.name,
      );
      return ref.id;
    } catch (error) {
      throw mapFirestoreError(error, fallback: 'Could not save the laboratory.');
    }
  }

  Future<void> setStatus(Lab lab, LabStatus status) async {
    try {
      await _db.doc('labs/${lab.id}').set(
        <String, dynamic>{
          'status': status.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _activity.log(
        'lab_updated',
        labId: lab.id,
        details: 'Status set to ${status.label}',
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not update the laboratory status.',
      );
    }
  }
}

final labRepositoryProvider = Provider<LabRepository>(
  (ref) => LabRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
  ),
);

/// Live lab list for every active account. Rules only allow active users.
final labsProvider = StreamProvider<List<Lab>>(
  (ref) => ref.watch(labRepositoryProvider).watchLabs(),
);

final labProvider = StreamProvider.family<Lab?, String>(
  (ref, labId) => ref.watch(labRepositoryProvider).watchLab(labId),
);

final labsByIdProvider = Provider<Map<String, Lab>>((ref) {
  final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
  return {for (final lab in labs) lab.id: lab};
});

/// Labs the current user may monitor. Admins see all; staff see assigned labs
/// (or all labs when no assignment exists yet); instructors see all because
/// scheduling is institution-wide.
final visibleLabsProvider = Provider<List<Lab>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
  if (user == null) return const [];
  if (user.isAdmin) return labs;
  if (user.isStaff && user.assignedLabIds.isNotEmpty) {
    return labs
        .where((lab) => user.assignedLabIds.contains(lab.id))
        .toList(growable: false);
  }
  return labs;
});

final controllableLabsProvider = Provider<List<Lab>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || !user.mayControlDevices) return const [];

  final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
  if (user.isAdmin) return labs;
  return labs
      .where((lab) => user.assignedLabIds.contains(lab.id))
      .toList(growable: false);
});

/// Resolves display names for assigned lab ids, including ids whose metadata
/// document has not been created yet.
String labLabel(Map<String, Lab> byId, String id) {
  final lab = byId[id];
  if (lab == null) return id;
  return lab.number.trim().isEmpty
      ? lab.displayName
      : '${lab.displayName} · ${lab.number}';
}

String summarizeAssignedLabs(AppUser user, Map<String, Lab> byId) {
  if (user.assignedLabIds.isEmpty) return 'No laboratories assigned';
  return user.assignedLabIds.map((id) => labLabel(byId, id)).join(', ');
}
