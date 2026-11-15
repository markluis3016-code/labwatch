import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_user.dart';
import '../../activity/data/activity_repository.dart';
import '../../authentication/data/auth_repository.dart';

/// Administrator-only account operations. Firestore rules are still the real
/// enforcement; these guards mainly protect the UI from obvious mistakes.
class UserAdminRepository {
  UserAdminRepository(this._db, this._auth, this._activity);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ActivityRepository _activity;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AppFailure('You are signed out. Please sign in again.');
    }
    return uid;
  }

  Stream<List<AppUser>> watchUsers() {
    return _db.collection('users').snapshots().map((snapshot) {
      final users = snapshot.docs.map(AppUser.fromDoc).toList(growable: false);
      return [...users]..sort((a, b) {
          final aName = a.displayName.isEmpty ? a.email : a.displayName;
          final bName = b.displayName.isEmpty ? b.email : b.displayName;
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });
    });
  }

  Future<void> approve(
    String uid,
    UserRole role, {
    String? targetLabel,
  }) async {
    _assertNotSelf(uid);
    if (role == UserRole.admin) {
      throw const AppFailure(
        'Administrator accounts must be created with the Firebase Admin SDK.',
      );
    }
    await _update(uid, <String, dynamic>{
      'role': role.name,
      'status': AccountStatus.active.name,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': _uid,
      'statusNote': FieldValue.delete(),
    });
    await _activity.log(
      'user_approved',
      details: '${targetLabel ?? uid} approved as ${role.label}',
    );
  }

  Future<void> reject(String uid, {String? targetLabel}) async {
    _assertNotSelf(uid);
    await _update(uid, <String, dynamic>{
      'status': AccountStatus.disabled.name,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': _uid,
      'statusNote': 'Registration was rejected by an administrator.',
    });
    await _activity.log(
      'user_rejected',
      details: '${targetLabel ?? uid} registration rejected',
    );
  }

  Future<void> setStatus(
    String uid,
    AccountStatus status, {
    String? targetLabel,
  }) async {
    _assertNotSelf(uid);
    if (status == AccountStatus.pending) {
      throw const AppFailure('Accounts cannot be moved back to pending.');
    }
    await _update(uid, <String, dynamic>{
      'status': status.name,
      'statusNote': status == AccountStatus.active
          ? FieldValue.delete()
          : 'Account deactivated by an administrator.',
    });
    await _activity.log(
      'user_updated',
      details: '${targetLabel ?? uid} set to ${status.label.toLowerCase()}',
    );
  }

  Future<void> setRole(
    String uid,
    UserRole role, {
    String? targetLabel,
  }) async {
    _assertNotSelf(uid);
    if (role == UserRole.admin) {
      throw const AppFailure(
        'Administrator accounts must be created with the Firebase Admin SDK.',
      );
    }
    await _update(uid, <String, dynamic>{'role': role.name});
    await _activity.log(
      'user_updated',
      details: '${targetLabel ?? uid} role changed to ${role.label}',
    );
  }

  Future<void> setAssignedLabs(
    String uid,
    List<String> labIds, {
    String? targetLabel,
  }) async {
    _assertNotSelf(uid);
    final clean = <String>[];
    for (final raw in labIds) {
      final id = raw.trim();
      if (id.isNotEmpty && !clean.contains(id)) clean.add(id);
    }
    if (clean.length > 100) {
      throw const AppFailure('Assign at most 100 laboratories.');
    }
    await _update(uid, <String, dynamic>{'assignedLabIds': clean});
    await _activity.log(
      'user_updated',
      details: '${targetLabel ?? uid} lab assignments updated',
    );
  }

  void _assertNotSelf(String uid) {
    if (uid == _uid) {
      throw const AppFailure(
        'You cannot change your own role, status or lab assignments.',
      );
    }
  }

  Future<void> _update(String uid, Map<String, dynamic> data) async {
    try {
      await _db.doc('users/$uid').update(<String, dynamic>{
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const AppFailure(
          'Only an active administrator can change accounts.',
        );
      }
      throw const AppFailure(
        'Could not update the account. Check your connection and try again.',
      );
    } catch (_) {
      throw const AppFailure(
        'Could not update the account. Check your connection and try again.',
      );
    }
  }
}

final userAdminRepositoryProvider = Provider<UserAdminRepository>(
  (ref) => UserAdminRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
    ref.watch(activityRepositoryProvider),
  ),
);

/// Live user list for admins. Non-admins get an empty list and the router
/// prevents them from reaching the management screen at all.
final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || !me.isAdmin) {
    return Stream.value(const <AppUser>[]);
  }
  return ref.watch(userAdminRepositoryProvider).watchUsers();
});
