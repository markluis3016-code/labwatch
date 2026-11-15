import 'lab_alert.dart';

enum NotificationCategory {
  alerts,
  energy,
  reservations,
  equipment,
  account,
  system;

  static NotificationCategory parse(Object? value) {
    final name = value is String ? value.trim() : '';
    for (final category in NotificationCategory.values) {
      if (category.name == name) return category;
    }
    return NotificationCategory.system;
  }

  String get label => switch (this) {
        NotificationCategory.alerts => 'Laboratory alerts',
        NotificationCategory.energy => 'Energy saving',
        NotificationCategory.reservations => 'Reservations',
        NotificationCategory.equipment => 'Equipment',
        NotificationCategory.account => 'Account',
        NotificationCategory.system => 'System',
      };
}

/// Derived in-app notification. Nothing is fabricated: each entry maps to a
/// real Firestore alert, reservation or account state. Read state is stored
/// separately at `users/{uid}/notificationReads/{key}`.
class AppNotification {
  const AppNotification({
    required this.key,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.route = '/alerts',
    this.severity = AlertSeverity.warning,
  });

  final String key;
  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime? createdAt;
  final String route;
  final AlertSeverity severity;
}

/// Pure builder so notification rules are unit testable without Firestore.
class NotificationBuilder {
  static List<AppNotification> build({
    required Iterable<LabAlert> alerts,
    required Iterable<({String id, String labName, DateTime startAt})>
        upcomingReservations,
    required bool accountNeedsAttention,
    required String? accountMessage,
    required DateTime now,
  }) {
    final items = <AppNotification>[];

    for (final alert in alerts) {
      if (alert.status.isResolved) continue;
      items.add(
        AppNotification(
          key: 'alert:${alert.id}',
          category: alert.category == AlertCategory.energy
              ? NotificationCategory.energy
              : alert.category == AlertCategory.equipment
                  ? NotificationCategory.equipment
                  : alert.category == AlertCategory.reservation
                      ? NotificationCategory.reservations
                      : NotificationCategory.alerts,
          title: alert.title,
          body: alert.message,
          createdAt: alert.createdAt,
          route: '/alerts',
          severity: alert.severity,
        ),
      );
    }

    for (final reservation in upcomingReservations) {
      final startsIn = reservation.startAt.difference(now);
      if (startsIn.isNegative || startsIn > const Duration(hours: 24)) continue;
      items.add(
        AppNotification(
          key: 'reservation:${reservation.id}',
          category: NotificationCategory.reservations,
          title: startsIn.inMinutes < 60
              ? 'Reservation starts soon'
              : 'Upcoming reservation',
          body:
              '${reservation.labName} at ${_time(reservation.startAt)}'
              '${startsIn.inMinutes < 60 ? ' (${startsIn.inMinutes} min)' : ''}',
          createdAt: now,
          route: '/schedule',
          severity: AlertSeverity.info,
        ),
      );
    }

    if (accountNeedsAttention && accountMessage != null) {
      items.add(
        AppNotification(
          key: 'account:status',
          category: NotificationCategory.account,
          title: 'Account needs attention',
          body: accountMessage,
          createdAt: now,
          route: '/more',
          severity: AlertSeverity.critical,
        ),
      );
    }

    items.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return items;
  }

  static String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
