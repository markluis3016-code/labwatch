import 'package:cloud_firestore/cloud_firestore.dart';

enum ReservationStatus {
  pending,
  approved,
  rejected,
  cancelled,
  completed;

  static ReservationStatus parse(Object? value) {
    final name = value is String ? value.trim() : '';
    for (final status in ReservationStatus.values) {
      if (status.name == name) return status;
    }
    return ReservationStatus.cancelled;
  }

  String get label => switch (this) {
        ReservationStatus.pending => 'Pending',
        ReservationStatus.approved => 'Approved',
        ReservationStatus.rejected => 'Rejected',
        ReservationStatus.cancelled => 'Cancelled',
        ReservationStatus.completed => 'Completed',
      };

  bool get blocksSlot =>
      this == ReservationStatus.pending || this == ReservationStatus.approved;
  bool get isUpcoming =>
      this == ReservationStatus.pending || this == ReservationStatus.approved;
}

/// Booking stored at `reservations/{id}`.
class Reservation {
  const Reservation({
    required this.id,
    required this.labId,
    required this.labName,
    required this.title,
    required this.instructorId,
    required this.instructorName,
    required this.startAt,
    required this.endAt,
    this.status = ReservationStatus.pending,
    this.purpose = '',
    this.createdAt,
    this.updatedAt,
    this.decidedBy,
    this.decisionNote,
  });

  final String id;
  final String labId;
  final String labName;
  final String title;
  final String instructorId;
  final String instructorName;
  final DateTime startAt;
  final DateTime endAt;
  final ReservationStatus status;
  final String purpose;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? decidedBy;
  final String? decisionNote;

  Duration get duration => endAt.difference(startAt);

  bool overlaps(DateTime start, DateTime end) =>
      startAt.isBefore(end) && endAt.isAfter(start);

  bool get isFinished => endAt.isBefore(DateTime.now());

  factory Reservation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final start = _date(data['startAt']);
    final end = _date(data['endAt']);
    return Reservation(
      id: doc.id,
      labId: _string(data['labId']),
      labName: _string(data['labName']),
      title: _string(data['title']).trim().isEmpty
          ? 'Laboratory reservation'
          : _string(data['title']),
      instructorId: _string(data['instructorId']),
      instructorName: _string(data['instructorName']),
      startAt: start ?? DateTime.fromMillisecondsSinceEpoch(0),
      endAt: end ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: ReservationStatus.parse(data['status']),
      purpose: _string(data['purpose']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      decidedBy: _string(data['decidedBy']),
      decisionNote: _string(data['decisionNote']),
    );
  }
}

/// Pure validation used by the form, the repository transaction and tests.
class ReservationValidator {
  static const minDuration = Duration(minutes: 15);
  static const maxDuration = Duration(hours: 8);
  static const openingHour = 6;
  static const closingHour = 22;

  /// Returns a user-facing error, or null when the window is valid.
  static String? validateWindow({
    required DateTime start,
    required DateTime end,
    required DateTime now,
  }) {
    if (!end.isAfter(start)) return 'The end time must be after the start time.';
    if (end.difference(start) < minDuration) {
      return 'Reserve at least 15 minutes.';
    }
    if (end.difference(start) > maxDuration) {
      return 'A single reservation cannot exceed 8 hours.';
    }
    if (start.isBefore(now.subtract(const Duration(minutes: 5)))) {
      return 'Choose a start time in the future.';
    }
    if (end.difference(now) > const Duration(days: 180)) {
      return 'Reservations can be made up to 180 days ahead.';
    }
    if (start.hour < openingHour ||
        end.hour > closingHour ||
        (end.hour == closingHour && end.minute > 0)) {
      return 'Laboratories are available from '
          '${_two(openingHour)}:00 to ${_two(closingHour)}:00.';
    }
    return null;
  }

  static String? validateDetails({
    required String title,
    required String purpose,
    required String labId,
  }) {
    if (labId.trim().isEmpty) return 'Choose a laboratory.';
    if (title.trim().length < 3) return 'Give the reservation a short title.';
    if (title.trim().length > 100) return 'Keep the title under 100 characters.';
    if (purpose.trim().length > 500) {
      return 'Keep the purpose under 500 characters.';
    }
    return null;
  }

  /// First conflicting reservation, if any.
  static Reservation? findConflict({
    required Iterable<Reservation> existing,
    required String labId,
    required DateTime start,
    required DateTime end,
    String? ignoreId,
  }) {
    for (final reservation in existing) {
      if (reservation.labId != labId) continue;
      if (ignoreId != null && reservation.id == ignoreId) continue;
      if (!reservation.status.blocksSlot) continue;
      if (reservation.overlaps(start, end)) return reservation;
    }
    return null;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

DateTime? _date(Object? value) =>
    value is Timestamp ? value.toDate() : null;

String _string(Object? value) => value is String ? value : '';
