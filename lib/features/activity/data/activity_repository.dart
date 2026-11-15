import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/activity_entry.dart';

/// Writes append-only activity entries as the signed-in user.
///
/// The Firestore rules require an active, verified account; failures are
/// swallowed so logging never blocks the operation the user asked for.
class ActivityRepository {
  ActivityRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<void> log(
    String action, {
    String? labId,
    String? details,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final data = <String, dynamic>{
      'userId': uid,
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (labId != null && labId.trim().isNotEmpty) {
      data['labId'] = labId.trim();
    }
    if (details != null && details.trim().isNotEmpty) {
      final text = details.trim();
      data['details'] = text.length > 500 ? text.substring(0, 500) : text;
    }

    try {
      await _db.collection('activity').add(data);
    } catch (_) {
      // Auditing is best-effort on the client. Critical audit trails should
      // be written by a trusted server instead.
    }
  }

  /// Admins read the whole trail; everyone else reads only their own.
  Stream<List<ActivityEntry>> watch({
    required bool allUsers,
    required String userId,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('activity');
    if (!allUsers) {
      query = query.where('userId', isEqualTo: userId);
    }
    return query
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(ActivityEntry.fromDoc).toList(growable: false));
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) =>
      ActivityRepository(FirebaseFirestore.instance, FirebaseAuth.instance),
);
