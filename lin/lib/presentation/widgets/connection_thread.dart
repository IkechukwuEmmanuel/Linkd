import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Relationship strength (`Contact.relationshipStrength`, 1–10) as a
/// "connection thread": two small avatars joined by a line whose treatment
/// encodes strength, with a tier label at the end.
///
///   close tie (≥7): solid moss line, 2.5px
///   forming (4–6):  dashed amber line, 2px
///   just met (<4):  dotted neutral line, 1.5px
///
/// DETAIL PAGE ONLY. List rows use [OverlapIndicator] instead.
class ConnectionThread extends StatelessWidget {
  final int strength;
  final String youInitial;
  final String themInitial;

  const ConnectionThread({
    super.key,
    required this.strength,
    this.youInitial = 'you',
    required this.themInitial,
  });

  String _label(MatchTier tier) => switch (tier) {
        MatchTier.strong => 'close tie',
        MatchTier.moderate => 'forming',
        MatchTier.low => 'just met',
      };

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    final tier = MatchTierX.fromStrength(strength);
    final color = tier.color(tokens);

    return Row(
      children: [
        _avatar(context, tokens, tokens.tierStrong, 'you'),
        Expanded(
          child: SizedBox(
            height: 24,
            child: CustomPaint(
              painter: _ThreadPainter(tier: tier, color: color),
            ),
          ),
        ),
        _avatar(context, tokens, color, themInitial),
        const SizedBox(width: 10),
        Text(
          _label(tier),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _avatar(
      BuildContext context, MossTokens tokens, Color color, String text) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        text.isNotEmpty ? text[0].toLowerCase() : '?',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: color),
      ),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  final MatchTier tier;
  final Color color;

  _ThreadPainter({required this.tier, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;

    switch (tier) {
      case MatchTier.strong:
        paint.strokeWidth = 2.5;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        break;
      case MatchTier.moderate:
        paint.strokeWidth = 2;
        _dashed(canvas, size.width, y, paint, dash: 10, gap: 6);
        break;
      case MatchTier.low:
        paint.strokeWidth = 1.5;
        paint.color = color.withValues(alpha: 0.7);
        _dashed(canvas, size.width, y, paint, dash: 3, gap: 6);
        break;
    }
  }

  void _dashed(Canvas canvas, double width, double y, Paint paint,
      {required double dash, required double gap}) {
    double x = 0;
    while (x < width) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.tier != tier || old.color != color;
}
