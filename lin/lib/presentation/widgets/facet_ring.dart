import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Growth-rings graphic for a facet (the user's own identity facets).
///
/// This is the facets' distinct visual language — NOT the memory-card shape,
/// overlap circles, or connection thread. Concentric rings (not a pie/donut):
/// the number of visible rings + their saturation encode strength/confidence.
///
///   strong/confirmed: 4 rings, light (outer) → solid saturated center
///   still forming:    1–2 rings, lighter, smaller center
///   fading:           fewest, lightest rings
///
/// One painter, used at both list (52px) and detail (84px) sizes via [size].
class FacetRing extends StatelessWidget {
  /// 0.0–1.0 — typically the facet's confidence (or weight/10).
  final double strength;
  final MatchTier tier;
  final double size;

  const FacetRing({
    super.key,
    required this.strength,
    required this.tier,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          strength: strength.clamp(0.0, 1.0),
          core: tier.color(tokens),
          mid: tier.soft(tokens),
          outer: tokens.tierLowSoft,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double strength;
  final Color core;
  final Color mid;
  final Color outer;

  _RingPainter({
    required this.strength,
    required this.core,
    required this.mid,
    required this.outer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    // 1..4 rings from strength.
    final ringCount = (strength * 4).ceil().clamp(1, 4);
    final ringWidth = maxR / 4.2;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth * 0.7;

    // Draw rings outermost → inner, fading from outer (lightest) to core.
    for (int i = 0; i < ringCount; i++) {
      final r = maxR - (i * ringWidth) - ringWidth * 0.4;
      if (r <= 0) break;
      // i==0 is outermost (lightest); deeper rings approach the core color.
      final t = ringCount == 1 ? 1.0 : i / (ringCount - 1);
      stroke.color = Color.lerp(outer, mid, t)!;
      canvas.drawCircle(center, r, stroke);
    }

    // Solid filled center; size scales with strength.
    final coreR = maxR * (0.18 + 0.22 * strength);
    canvas.drawCircle(center, coreR, Paint()..color = core);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.strength != strength ||
      old.core != core ||
      old.mid != mid ||
      old.outer != outer;
}
