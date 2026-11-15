import 'package:flutter/material.dart';

import '../../features/monitoring/domain/telemetry.dart';
import '../theme/app_theme.dart';

/// Always-visible provenance badge: LIVE DATA / SAMPLE DATA / OFFLINE.
class DataOriginBadge extends StatelessWidget {
  const DataOriginBadge(this.origin, {super.key});
  final DataOrigin origin;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (origin) {
      DataOrigin.live => ('LIVE DATA', AppColors.success),
      DataOrigin.sample => ('SAMPLE DATA', AppColors.warning),
      DataOrigin.offline => ('OFFLINE', AppColors.critical),
    };
    return Semantics(
      label: 'Data source: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    super.key,
  });
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: t.labelLarge)),
            ]),
            Text(value,
                style: t.titleLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
            if (subtitle != null) Text(subtitle!, style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
