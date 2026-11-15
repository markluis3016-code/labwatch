import 'package:flutter/material.dart';

import '../../shared/models/equipment.dart';
import '../../shared/models/lab.dart';
import '../../shared/models/lab_alert.dart';
import '../../shared/models/reservation.dart';
import 'app_theme.dart';

/// Central colour mapping so statuses look identical on every screen.
extension LabStatusColor on LabStatus {
  Color get color => switch (this) {
        LabStatus.available => AppColors.success,
        LabStatus.reserved => AppColors.warning,
        LabStatus.occupied => AppColors.critical,
        LabStatus.maintenance => AppColors.info,
        LabStatus.offline => AppColors.lightMuted,
        LabStatus.unknown => AppColors.lightMuted,
      };

  IconData get icon => switch (this) {
        LabStatus.available => Icons.check_circle_outline,
        LabStatus.reserved => Icons.event_available_outlined,
        LabStatus.occupied => Icons.sensors,
        LabStatus.maintenance => Icons.build_outlined,
        LabStatus.offline => Icons.power_off,
        LabStatus.unknown => Icons.help_outline,
      };
}

extension EquipmentConditionColor on EquipmentCondition {
  Color get color => switch (this) {
        EquipmentCondition.good => AppColors.success,
        EquipmentCondition.needsRepair => AppColors.warning,
        EquipmentCondition.damaged => AppColors.critical,
        EquipmentCondition.missing => AppColors.critical,
        EquipmentCondition.unknown => AppColors.lightMuted,
      };

  IconData get icon => switch (this) {
        EquipmentCondition.good => Icons.verified_outlined,
        EquipmentCondition.needsRepair => Icons.build_outlined,
        EquipmentCondition.damaged => Icons.report_problem_outlined,
        EquipmentCondition.missing => Icons.remove_circle_outline,
        EquipmentCondition.unknown => Icons.help_outline,
      };
}

extension ReservationStatusColor on ReservationStatus {
  Color get color => switch (this) {
        ReservationStatus.pending => AppColors.warning,
        ReservationStatus.approved => AppColors.success,
        ReservationStatus.rejected => AppColors.critical,
        ReservationStatus.cancelled => AppColors.lightMuted,
        ReservationStatus.completed => AppColors.info,
      };

  IconData get icon => switch (this) {
        ReservationStatus.pending => Icons.hourglass_top_rounded,
        ReservationStatus.approved => Icons.check_circle_outline,
        ReservationStatus.rejected => Icons.cancel_outlined,
        ReservationStatus.cancelled => Icons.block_outlined,
        ReservationStatus.completed => Icons.done_all,
      };
}

extension AlertSeverityColor on AlertSeverity {
  Color get color => switch (this) {
        AlertSeverity.info => AppColors.info,
        AlertSeverity.warning => AppColors.warning,
        AlertSeverity.critical => AppColors.critical,
      };

  IconData get icon => switch (this) {
        AlertSeverity.info => Icons.info_outline,
        AlertSeverity.warning => Icons.warning_amber_rounded,
        AlertSeverity.critical => Icons.report_gmailerrorred_outlined,
      };
}

extension AlertCategoryIcon on AlertCategory {
  IconData get icon => switch (this) {
        AlertCategory.energy => Icons.energy_savings_leaf_outlined,
        AlertCategory.lab => Icons.science_outlined,
        AlertCategory.equipment => Icons.inventory_2_outlined,
        AlertCategory.reservation => Icons.event_available_outlined,
        AlertCategory.account => Icons.manage_accounts_outlined,
        AlertCategory.system => Icons.settings_outlined,
      };
}
