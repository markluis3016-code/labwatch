import 'package:flutter/material.dart';

import '../../shared/models/app_user.dart';
import '../theme/app_theme.dart';

class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      UserRole.admin => AppColors.royal,
      UserRole.staff => AppColors.success,
      UserRole.instructor => AppColors.warning,
    };
    return _Chip(label: role.label, color: color, icon: Icons.badge_outlined);
  }
}

class AccountStatusChip extends StatelessWidget {
  const AccountStatusChip(this.status, {super.key});

  final AccountStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      AccountStatus.active => (AppColors.success, Icons.check_circle_outline),
      AccountStatus.pending => (AppColors.warning, Icons.hourglass_top_rounded),
      AccountStatus.disabled => (AppColors.critical, Icons.block_outlined),
    };
    return _Chip(label: status.label, color: color, icon: icon);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
