import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/errors/firestore_errors.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/reservation.dart';
import '../../activity/data/activity_repository.dart';
import '../../authentication/data/auth_repository.dart';

class ReservationRepository {
  ReservationRepository(this._db, this._activity);

  final FirebaseFirestore _db;
  final ActivityRepository _activity;

  CollectionReference<Map<String, dynamic>> get _reservations =>
      _db.collection('reservations');

  Stream<List<Reservation>> watchAll({int limit = 300}) => _reservations
      .orderBy('startAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(Reservation.fromDoc).toList(growable: false));

  Stream<List<Reservation>> watchMine(String uid, {int limit = 150}) =>
      _reservations
          .where('instructorId', isEqualTo: uid)
          .orderBy('startAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) =>
              snapshot.docs.map(Reservation.fromDoc).toList(growable: false));

  Future<Reservation> create({
    required Lab lab,
    required AppUser actor,
    required DateTime start,
    required DateTime end,
    required String title,
    required String purpose,
  }) async {
    final now = DateTime.now();
    final windowError = ReservationValidator.validateWindow(
      start: start,
      end: end,
      now: now,
    );
    if (windowError != null) throw AppFailure(windowError);
    final detailError = ReservationValidator.validateDetails(
      title: title,
      purpose: purpose,
      labId: lab.id,
    );
    if (detailError != null) throw AppFailure(detailError);
    if (!lab.status.canBeReserved) {
      throw AppFailure(
        '${lab.displayName} is ${lab.status.label.toLowerCase()} and cannot be '
        'reserved right now.',
      );
    }

    final status = actor.isInstructor
        ? ReservationStatus.pending
        : ReservationStatus.approved;
    final ref = _reservations.doc();

    try {
      final candidates = await _candidates(labId: lab.id, start: start, end: end);
      await _db.runTransaction((transaction) async {
        final conflict = await _conflictInTransaction(
          transaction,
          candidates: candidates,
          labId: lab.id,
          start: start,
          end: end,
        );
        if (conflict != null) {
          throw AppFailure(
            'That time overlaps an existing reservation '
            '(${_range(conflict.startAt, conflict.endAt)}). Choose another slot.',
          );
        }
        transaction.set(ref, <String, dynamic>{
          'labId': lab.id,
          'labName': lab.displayName,
          'title': title.trim(),
          'purpose': purpose.trim(),
          'instructorId': actor.uid,
          'instructorName':
              actor.displayName.isEmpty ? actor.email : actor.displayName,
          'startAt': Timestamp.fromDate(start),
          'endAt': Timestamp.fromDate(end),
          'status': status.name,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (status == ReservationStatus.approved) ...{
            'decidedBy': actor.uid,
            'decisionNote': 'Created by ${actor.role.label.toLowerCase()}.',
          },
        });
      });
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not create the reservation.',
      );
    }

    await _activity.log(
      'reservation_created',
      labId: lab.id,
      details: '${lab.displayName}: ${_range(start, end)} (${status.label})',
    );

    return Reservation(
      id: ref.id,
      labId: lab.id,
      labName: lab.displayName,
      title: title.trim(),
      instructorId: actor.uid,
      instructorName:
          actor.displayName.isEmpty ? actor.email : actor.displayName,
      startAt: start,
      endAt: end,
      status: status,
      purpose: purpose.trim(),
    );
  }

  Future<void> approve(Reservation reservation, AppUser actor) async {
    if (reservation.status != ReservationStatus.pending) {
      throw const AppFailure('Only pending reservations can be approved.');
    }
    try {
      final candidates = await _candidates(
        labId: reservation.labId,
        start: reservation.startAt,
        end: reservation.endAt,
      );
      await _db.runTransaction((transaction) async {
        final labSnapshot =
            await transaction.get(_db.doc('labs/${reservation.labId}'));
        if (!labSnapshot.exists) {
          throw const AppFailure('The laboratory no longer exists.');
        }
        final lab = Lab.fromDoc(labSnapshot);
        if (!lab.status.canBeReserved) {
          throw AppFailure(
            '${lab.displayName} is ${lab.status.label.toLowerCase()} and cannot '
            'be approved right now.',
          );
        }
        final conflict = await _conflictInTransaction(
          transaction,
          candidates: candidates,
          labId: reservation.labId,
          start: reservation.startAt,
          end: reservation.endAt,
          ignoreId: reservation.id,
        );
        if (conflict != null) {
          throw AppFailure(
            'This slot now overlaps another reservation '
            '(${_range(conflict.startAt, conflict.endAt)}). Ask the instructor '
            'to rebook.',
          );
        }
        transaction.update(
          _reservations.doc(reservation.id),
          <String, dynamic>{
            'status': ReservationStatus.approved.name,
            'decidedBy': actor.uid,
            'decisionNote': '',
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      });
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not approve the reservation.',
      );
    }
    await _activity.log(
      'reservation_approved',
      labId: reservation.labId,
      details:
          '${reservation.labName}: ${_range(reservation.startAt, reservation.endAt)}',
    );
  }

  Future<void> reject(
    Reservation reservation,
    AppUser actor, {
    String reason = '',
  }) async {
    if (reservation.status != ReservationStatus.pending) {
      throw const AppFailure('Only pending reservations can be rejected.');
    }
    try {
      await _db.doc('reservations/${reservation.id}').update(
        <String, dynamic>{
          'status': ReservationStatus.rejected.name,
          'decidedBy': actor.uid,
          'decisionNote': reason.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not reject the reservation.',
      );
    }
    await _activity.log(
      'reservation_rejected',
      labId: reservation.labId,
      details: '${reservation.labName}: ${_range(reservation.startAt, reservation.endAt)}'
          '${reason.trim().isEmpty ? '' : ' — ${reason.trim()}'}',
    );
  }

  Future<void> cancel(Reservation reservation, AppUser actor) async {
    if (reservation.status == ReservationStatus.completed ||
        reservation.status == ReservationStatus.cancelled) {
      throw const AppFailure('This reservation can no longer be cancelled.');
    }
    if (reservation.instructorId != actor.uid && !actor.isAdmin) {
      throw const AppFailure('Only the owner can cancel this reservation.');
    }
    try {
      await _db.doc('reservations/${reservation.id}').update(
        <String, dynamic>{
          'status': ReservationStatus.cancelled.name,
          'decisionNote': 'Cancelled by ${actor.displayName.isEmpty ? actor.email : actor.displayName}.',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not cancel the reservation.',
      );
    }
    await _activity.log(
      'reservation_cancelled',
      labId: reservation.labId,
      details: reservation.labName,
    );
  }

  Future<void> complete(Reservation reservation, AppUser actor) async {
    if (!reservation.status.blocksSlot) {
      throw const AppFailure('Only pending or approved reservations can be completed.');
    }
    try {
      await _db.doc('reservations/${reservation.id}').update(
        <String, dynamic>{
          'status': ReservationStatus.completed.name,
          'decidedBy': actor.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (error) {
      throw mapFirestoreError(
        error,
        fallback: 'Could not complete the reservation.',
      );
    }
    await _activity.log(
      'reservation_completed',
      labId: reservation.labId,
      details: reservation.labName,
    );
  }

  /// Candidate reservations whose start window can overlap the requested slot.
  /// Queried outside the transaction because Firestore transactions only allow
  /// document reads, not query reads.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _candidates({
    required String labId,
    required DateTime start,
    required DateTime end,
  }) async {
    final snapshot = await _reservations
        .where('labId', isEqualTo: labId)
        .where(
          'startAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            start.subtract(ReservationValidator.maxDuration),
          ),
        )
        .where('startAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    return snapshot.docs;
  }

  /// Re-reads candidates inside the transaction so the overlap check is based
  /// on current committed state.
  Future<Reservation?> _conflictInTransaction(
    Transaction transaction, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> candidates,
    required String labId,
    required DateTime start,
    required DateTime end,
    String? ignoreId,
  }) async {
    final existing = <Reservation>[];
    for (final doc in candidates) {
      final snapshot = await transaction.get(doc.reference);
      if (!snapshot.exists) continue;
      existing.add(Reservation.fromDoc(snapshot));
    }
    return ReservationValidator.findConflict(
      existing: existing,
      labId: labId,
      start: start,
      end: end,
      ignoreId: ignoreId,
    );
  }

  static String _range(DateTime start, DateTime end) {
    String two(int value) => value.toString().padLeft(2, '0');
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final date = '${start.year}-${two(start.month)}-${two(start.day)}';
    final from = '${two(start.hour)}:${two(start.minute)}';
    final to = '${two(end.hour)}:${two(end.minute)}';
    return sameDay ? '$date $from–$to' : '$date $from – ${two(end.month)}/${two(end.day)} $to';
  }
}

final reservationRepositoryProvider = Provider<ReservationRepository>(
  (ref) => ReservationRepository(
    FirebaseFirestore.instance,
    ref.watch(activityRepositoryProvider),
  ),
);

final reservationsProvider = StreamProvider<List<Reservation>>(
  (ref) => ref.watch(reservationRepositoryProvider).watchAll(),
);

final myReservationsProvider = StreamProvider<List<Reservation>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Reservation>[]);
  return ref.watch(reservationRepositoryProvider).watchMine(user.uid);
});

/// Pending + approved reservations still ahead, soonest first.
final upcomingReservationsProvider = Provider<List<Reservation>>((ref) {
  final reservations =
      ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
  final now = DateTime.now();
  final upcoming = reservations
      .where((reservation) =>
          reservation.status.isUpcoming && reservation.endAt.isAfter(now))
      .toList(growable: false)
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  return upcoming;
});

final pendingReservationsProvider = Provider<List<Reservation>>((ref) {
  final reservations =
      ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
  return reservations
      .where((reservation) => reservation.status == ReservationStatus.pending)
      .toList(growable: false);
});

/// Reservations visible to the signed-in user: instructors only see their own
/// on the schedule screen; staff and admins see the institution-wide calendar.
final visibleReservationsProvider = Provider<List<Reservation>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const [];
  if (user.isAdmin || user.isStaff) {
    return ref.watch(reservationsProvider).valueOrNull ?? const [];
  }
  return ref.watch(myReservationsProvider).valueOrNull ?? const [];
});
