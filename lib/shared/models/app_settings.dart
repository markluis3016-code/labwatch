import 'package:cloud_firestore/cloud_firestore.dart';

/// Operational settings at `config/app`. Written by admins only.
class AppSettings {
  const AppSettings({
    this.energyInactivityMinutes = 10,
    this.energyAlertsEnabled = true,
    this.updatedAt,
  });

  static const defaults = AppSettings();

  /// How long a laboratory must be empty with lights or AC on before an
  /// energy-saving alert is raised.
  final int energyInactivityMinutes;
  final bool energyAlertsEnabled;
  final DateTime? updatedAt;

  factory AppSettings.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final minutes = data['energyInactivityMinutes'];
    return AppSettings(
      energyInactivityMinutes: minutes is num
          ? minutes.toInt().clamp(1, 240)
          : defaults.energyInactivityMinutes,
      energyAlertsEnabled:
          data['energyAlertsEnabled'] is bool
              ? data['energyAlertsEnabled'] as bool
              : defaults.energyAlertsEnabled,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  AppSettings copyWith({
    int? energyInactivityMinutes,
    bool? energyAlertsEnabled,
  }) =>
      AppSettings(
        energyInactivityMinutes:
            energyInactivityMinutes ?? this.energyInactivityMinutes,
        energyAlertsEnabled: energyAlertsEnabled ?? this.energyAlertsEnabled,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'energyInactivityMinutes': energyInactivityMinutes,
        'energyAlertsEnabled': energyAlertsEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
