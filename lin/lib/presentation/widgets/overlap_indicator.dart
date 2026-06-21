import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Match strength (`Contact.overlapScore`, 0.0–1.0) as two overlapping circles.
///
/// Bigger overlap = stronger match. Tier-colored (moss / amber / neutral —
/// never red, since low match is not a failure state). A quiet trailing
/// percentage sits beside the circles as a precision fallback.
///
/// LIST ROWS ONLY. The detail page uses [ConnectionThread] instead.
class OverlapIndicator extends StatelessWidget {
  final double score;
  final double radius;
  final bool showPercent;

  const OverlapIndicator({
    super.key,
    required this.score,
    this.radius = 11,
    this.showPercent = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    final tier = MatchTierX.fromScore(score);
    final clamped = score.clamp(0.0, 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(radius * 3.2, radius * 2),
          painter: _OverlapPainter(
            score: clamped,
            you: tier.color(tokens),
            them: tier.soft(tokens),
            surface: tokens.cardSurface,
          ),
        ),
        if (showPercent) ...[
          const SizedBox(width: 8),
          Text(
            '${(clamped * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _OverlapPainter extends CustomPainter {
  final double score;
  final Color you;
  final Color them;
  final Color surface;

  _OverlapPainter({
    required this.score,
    required this.you,
    required this.them,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final cy = size.height / 2;
    // Centers move closer together as score rises: fully apart (just touching)
    // at 0, heavily overlapped at 1.
    final maxGap = r * 1.4;
    final gap = maxGap * (1 - score) + r * 0.55;
    final leftX = size.width / 2 - gap / 2;
    final rightX = size.width / 2 + gap / 2;

    // Thin surface-colored stroke keeps the two circles legible where they
    // overlap, regardless of background.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = surface;

    final themPaint = Paint()..color = them.withValues(alpha: 0.85);
    final youPaint = Paint()..color = you;

    canvas.drawCircle(Offset(rightX, cy), r, themPaint);
    canvas.drawCircle(Offset(rightX, cy), r, stroke);
    canvas.drawCircle(Offset(leftX, cy), r, youPaint);
    canvas.drawCircle(Offset(leftX, cy), r, stroke);
  }

  @override
  bool shouldRepaint(_OverlapPainter old) =>
      old.score != score || old.you != you || old.them != them;
}
