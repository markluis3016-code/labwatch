import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_notification.dart';
import '../../alerts/data/alert_repository.dart';
import '../../authentication/data/auth_repository.dart';
import '../../scheduling/data/reservation_repository.dart';

/// Read state lives under the user's own document, so no notification content
/// has to be duplicated or fabricated. Everything shown is derived from real
/// alerts, reservations and account state.
class NotificationRepository {
  NotificationRepository(this._db);

  final FirebaseFirestore _db;

  Stream<Set<String>> watchReadKeys(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('notificationReads')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());

  Future<void> markRead(String uid, String key) async {
    try {
      await _db
          .doc('users/$uid/notificationReads/${_docId(key)}')
          .set(<String, dynamic>{
        'notificationKey': key,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not mark the notification as read.',
      );
    }
  }

  Future<void> markAllRead(String uid, Iterable<String> keys) async {
    final batch = _db.batch();
    for (final key in keys) {
      batch.set(
        _db.doc('users/$uid/notificationReads/${_docId(key)}'),
        <String, dynamic>{
          'notificationKey': key,
          'readAt': FieldValue.serverTimestamp(),
        },
      );
    }
    try {
      await batch.commit();
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not mark notifications as read.',
      );
    }
  }

  static String _docId(String key) => key.replaceAll('/', '_');
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(FirebaseFirestore.instance),
);

final notificationReadKeysProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <String>{});
  return ref.watch(notificationRepositoryProvider).watchReadKeys(user.uid);
});

final notificationsProvider = Provider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const [];

  final alerts = ref.watch(openAlertsProvider);
  final reservations = ref.watch(visibleReservationsProvider);
  final now = DateTime.now();
  final upcoming = reservations
      .where((reservation) =>
          reservation.status.isUpcoming && reservation.endAt.isAfter(now))
      .map(
        (reservation) => (
          id: reservation.id,
          labName: reservation.labName,
          startAt: reservation.startAt,
        ),
      );

  return NotificationBuilder.build(
    alerts: alerts,
    upcomingReservations: upcoming,
    accountNeedsAttention: user.statusNote != null,
    accountMessage: user.statusNote,
    now: now,
  );
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final read = ref.watch(notificationReadKeysProvider).valueOrNull ??
      const <String>{};
  final items = ref.watch(notificationsProvider);
  return items.where((item) => !read.contains(item.key)).length;
});
