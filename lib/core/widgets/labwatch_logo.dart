import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Professional LabWatch mark: lab flask + monitoring signal.
/// Drawn with theme-aware colors so it works on light and dark backgrounds.
class LabWatchMark extends StatelessWidget {
  const LabWatchMark({super.key, this.size = 40, this.rounded = true});

  final double size;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? scheme.primary : const Color(0xFF0B1F45);
    final accent = isDark ? const Color(0xFFBFDBFE) : scheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          background: bg,
          foreground: Colors.white,
          accent: accent,
          rounded: rounded,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.rounded,
  });

  final Color background;
  final Color foreground;
  final Color accent;
  final bool rounded;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(rounded ? s * 0.24 : s * 0.12),
    );
    canvas.drawRRect(rrect, Paint()..color = background);

    final stroke = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Flask body
    final flask = Path()
      ..moveTo(s * 0.41, s * 0.22)
      ..lineTo(s * 0.59, s * 0.22)
      ..lineTo(s * 0.59, s * 0.30)
      ..lineTo(s * 0.55, s * 0.34)
      ..lineTo(s * 0.55, s * 0.47)
      ..lineTo(s * 0.70, s * 0.70)
      ..arcToPoint(
        Offset(s * 0.62, s * 0.80),
        radius: Radius.circular(s * 0.09),
        clockwise: true,
      )
      ..lineTo(s * 0.38, s * 0.80)
      ..arcToPoint(
        Offset(s * 0.30, s * 0.70),
        radius: Radius.circular(s * 0.09),
        clockwise: true,
      )
      ..lineTo(s * 0.45, s * 0.47)
      ..lineTo(s * 0.45, s * 0.34)
      ..lineTo(s * 0.41, s * 0.30)
      ..close();
    canvas.drawPath(flask, stroke);

    // Liquid line
    canvas.drawLine(
      Offset(s * 0.36, s * 0.62),
      Offset(s * 0.64, s * 0.62),
      Paint()
        ..color = accent.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(s * 0.50, s * 0.71),
      s * 0.035,
      Paint()..color = foreground,
    );

    // Monitoring signal arcs (top-right)
    final signal = Paint()
      ..color = accent.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.038
      ..strokeCap = StrokeCap.round;
    final center = Offset(s * 0.72, s * 0.30);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.07),
      -math.pi / 3,
      2 * math.pi / 3,
      false,
      signal,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.125),
      -math.pi / 3,
      2 * math.pi / 3,
      false,
      signal,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.foreground != foreground ||
      oldDelegate.accent != accent;
}

/// Primary logo: mark + "LabWatch" wordmark.
class LabWatchLogo extends StatelessWidget {
  const LabWatchLogo({
    super.key,
    this.markSize = 40,
    this.showWordmark = true,
    this.compact = false,
  });

  final double markSize;
  final bool showWordmark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = LabWatchMark(size: markSize);
    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: compact ? 8 : 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LabWatch',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (compact
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
              ),
              if (!compact)
                Text(
                  'Laboratory monitoring',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
