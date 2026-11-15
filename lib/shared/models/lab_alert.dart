import 'package:cloud_firestore/cloud_firestore.dart';

enum AlertCategory {
  energy,
  lab,
  equipment,
  reservation,
  account,
  system;

  static AlertCategory parse(Object? value) {
    final name = value is String ? value.trim() : '';
    for (final category in AlertCategory.values) {
      if (category.name == name) return category;
    }
    return AlertCategory.system;
  }

  String get label => switch (this) {
        AlertCategory.energy => 'Energy saving',
        AlertCategory.lab => 'Laboratory',
        AlertCategory.equipment => 'Equipment',
        AlertCategory.reservation => 'Reservation',
        AlertCategory.account => 'Account',
        AlertCategory.system => 'System',
      };
}

enum AlertSeverity {
  info,
  warning,
  critical;

  static AlertSeverity parse(Object? value) {
    final name = value is String ? value.trim() : '';
    for (final severity in AlertSeverity.values) {
      if (severity.name == name) return severity;
    }
    return AlertSeverity.warning;
  }

  String get label => switch (this) {
        AlertSeverity.info => 'Info',
        AlertSeverity.warning => 'Warning',
        AlertSeverity.critical => 'Critical',
      };
}

enum AlertStatus {
  open,
  acknowledged,
  resolved;

  static AlertStatus parse(Object? value) {
    final name = value is String ? value.trim() : '';
    for (final status in AlertStatus.values) {
      if (status.name == name) return status;
    }
    return AlertStatus.open;
  }

  String get label => switch (this) {
        AlertStatus.open => 'Open',
        AlertStatus.acknowledged => 'Acknowledged',
        AlertStatus.resolved => 'Resolved',
      };

  bool get isOpen => this == AlertStatus.open;
  bool get isResolved => this == AlertStatus.resolved;
}

/// Alert stored at `alerts/{id}`. Energy alerts use a deterministic document
/// id so a repeated evaluation cannot create duplicates.
class LabAlert {
  const LabAlert({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.message,
    this.labId = '',
    this.status = AlertStatus.open,
    this.sourceKey = '',
    this.createdBy = '',
    this.createdAt,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.resolvedBy,
    this.resolvedAt,
  });

  final String id;
  final AlertCategory category;
  final AlertSeverity severity;
  final String title;
  final String message;
  final String labId;
  final AlertStatus status;
  final String sourceKey;
  final String createdBy;
  final DateTime? createdAt;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;

  bool get isActive => !status.isResolved;

  factory LabAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return LabAlert(
      id: doc.id,
      category: AlertCategory.parse(data['category']),
      severity: AlertSeverity.parse(data['severity']),
      title: _string(data['title']).trim().isEmpty
          ? 'Laboratory alert'
          : _string(data['title']),
      message: _string(data['message']),
      labId: _string(data['labId']),
      status: AlertStatus.parse(data['status']),
      sourceKey: _string(data['sourceKey']),
      createdBy: _string(data['createdBy']),
      createdAt: _date(data['createdAt']),
      acknowledgedBy: _string(data['acknowledgedBy']),
      acknowledgedAt: _date(data['acknowledgedAt']),
      resolvedBy: _string(data['resolvedBy']),
      resolvedAt: _date(data['resolvedAt']),
    );
  }
}

DateTime? _date(Object? value) =>
    value is Timestamp ? value.toDate() : null;

String _string(Object? value) => value is String ? value : '';
